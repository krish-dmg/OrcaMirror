import Foundation
import AVFoundation
import CoreMedia
import CoreVideo

enum CaptureState {
    case idle
    case connecting(deviceName: String)
    case streaming(deviceName: String, size: CGSize, fps: Double)
    case paused
    case failed(String)
}

final class CaptureController: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private(set) var currentDevice: AVCaptureDevice?
    private var currentInput: AVCaptureDeviceInput?
    private var audioDataOutput: AVCaptureAudioDataOutput?
    private var videoDataOutput: AVCaptureVideoDataOutput?
    private var audioPlayer = LowLatencyAudioPlayer()

    private let videoQueue = DispatchQueue(label: "com.orca.mirror.videoQueue", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "com.orca.mirror.audioQueue", qos: .userInteractive)

    private var frameTimestamps: [CFTimeInterval] = []
    private var lastFPSReportTime: CFTimeInterval = 0
    private(set) var currentResolution: CGSize = .zero
    private(set) var currentFPS: Double = 0.0

    private(set) var activePreset: AVCaptureSession.Preset = .hd1920x1080
    private(set) var targetFPS: Int = 60

    var isAudioMuted: Bool = false {
        didSet {
            audioPlayer.isMuted = isAudioMuted
        }
    }

    var audioVolume: Float = 1.0 {
        didSet {
            audioPlayer.volume = audioVolume
        }
    }

    var onStateChanged: ((CaptureState) -> Void)?
    var onResolutionChanged: ((CGSize) -> Void)?
    var onFPSUpdated: ((Double) -> Void)?

    override init() {
        super.init()
        if let saved = UserDefaults.standard.string(forKey: "OrcaMirror_ResolutionPreset") {
            switch saved {
            case "native":
                activePreset = .high
            case "720p":
                activePreset = .hd1280x720
            default:
                activePreset = .hd1920x1080
            }
        } else {
            activePreset = .hd1920x1080
        }
        session.sessionPreset = activePreset
    }

    func setQualityPreset(_ preset: AVCaptureSession.Preset) {
        activePreset = preset
        let key: String
        switch preset {
        case .high: key = "native"
        case .hd1280x720: key = "720p"
        default: key = "1080p"
        }
        UserDefaults.standard.set(key, forKey: "OrcaMirror_ResolutionPreset")
        session.beginConfiguration()
        if session.canSetSessionPreset(preset) {
            session.sessionPreset = preset
        }
        session.commitConfiguration()
    }

    func setTargetFPS(_ fps: Int) {
        targetFPS = fps
        applyTargetFPS()
    }

    private func applyTargetFPS() {
        for conn in session.connections {
            if conn.inputPorts.contains(where: { $0.mediaType == .video }) {
                if conn.isVideoMinFrameDurationSupported {
                    if targetFPS > 0 {
                        conn.videoMinFrameDuration = CMTime(value: 1, timescale: Int32(targetFPS))
                        conn.videoMaxFrameDuration = CMTime(value: 1, timescale: Int32(targetFPS))
                    } else {
                        conn.videoMinFrameDuration = .invalid
                        conn.videoMaxFrameDuration = .invalid
                    }
                }
            }
        }
    }

    func start(with device: AVCaptureDevice) {
        stop()

        currentDevice = device
        onStateChanged?(.connecting(deviceName: device.localizedName))

        let videoAuth = AVCaptureDevice.authorizationStatus(for: .video)
        if videoAuth == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self = self else { return }
                if granted {
                    self.requestAudioAccessIfNeeded(device: device)
                } else {
                    DispatchQueue.main.async {
                        self.onStateChanged?(.failed("Camera permission was denied."))
                    }
                }
            }
        } else if videoAuth == .authorized {
            requestAudioAccessIfNeeded(device: device)
        } else {
            onStateChanged?(.failed("Camera permission is not authorized for OrcaMirror."))
        }
    }

    private func requestAudioAccessIfNeeded(device: AVCaptureDevice) {
        let audioAuth = AVCaptureDevice.authorizationStatus(for: .audio)
        if audioAuth == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                self?.performSessionSetup(device: device)
            }
        } else {
            performSessionSetup(device: device)
        }
    }

    private func performSessionSetup(device: AVCaptureDevice) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            self.session.beginConfiguration()

            do {
                let input = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.currentInput = input
                } else {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async {
                        self.onStateChanged?(.failed("Cannot attach video stream from \(device.localizedName)."))
                    }
                    return
                }

                // Add Audio Data Output directly connected to LowLatencyAudioPlayer
                let audioData = AVCaptureAudioDataOutput()
                audioData.setSampleBufferDelegate(self.audioPlayer, queue: self.audioQueue)
                if self.session.canAddOutput(audioData) {
                    self.session.addOutput(audioData)
                    self.audioDataOutput = audioData
                }

                // Add Video Data Output for real-time resolution and framerate tracking
                let videoOut = AVCaptureVideoDataOutput()
                videoOut.alwaysDiscardsLateVideoFrames = true
                videoOut.setSampleBufferDelegate(self, queue: self.videoQueue)
                if self.session.canAddOutput(videoOut) {
                    self.session.addOutput(videoOut)
                    self.videoDataOutput = videoOut
                }

                self.session.commitConfiguration()
                self.audioPlayer.start()
                self.session.startRunning()
                self.applyTargetFPS()
                print("[CaptureController] session isRunning=\(self.session.isRunning), connections=\(self.session.connections.count)")

                DispatchQueue.main.async {
                    self.onStateChanged?(.streaming(deviceName: device.localizedName, size: self.currentResolution, fps: 0))
                }
            } catch {
                self.session.commitConfiguration()
                print("[CaptureController] setup error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.onStateChanged?(.failed(error.localizedDescription))
                }
            }
        }
    }

    func stop() {
        if session.isRunning {
            session.stopRunning()
        }

        audioPlayer.stop()

        session.beginConfiguration()
        if let input = currentInput {
            session.removeInput(input)
            currentInput = nil
        }
        if let audioData = audioDataOutput {
            session.removeOutput(audioData)
            audioDataOutput = nil
        }
        if let videoOut = videoDataOutput {
            session.removeOutput(videoOut)
            videoDataOutput = nil
        }
        session.commitConfiguration()

        currentDevice = nil
        currentResolution = .zero
        currentFPS = 0
        frameTimestamps.removeAll()
        onStateChanged?(.idle)
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        frameTimestamps.append(now)

        // Keep 1 second window
        frameTimestamps.removeAll { now - $0 > 1.0 }
        let calculatedFPS = Double(frameTimestamps.count)

        if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let width = CGFloat(CVPixelBufferGetWidth(imageBuffer))
            let height = CGFloat(CVPixelBufferGetHeight(imageBuffer))
            let size = CGSize(width: width, height: height)

            if size != currentResolution && width > 0 && height > 0 {
                currentResolution = size
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.onResolutionChanged?(size)
                    if let dev = self.currentDevice {
                        self.onStateChanged?(.streaming(deviceName: dev.localizedName, size: size, fps: self.currentFPS))
                    }
                }
            }
        }

        if now - lastFPSReportTime >= 0.5 {
            lastFPSReportTime = now
            currentFPS = calculatedFPS
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.onFPSUpdated?(calculatedFPS)
                if let dev = self.currentDevice, self.currentResolution != .zero {
                    self.onStateChanged?(.streaming(deviceName: dev.localizedName, size: self.currentResolution, fps: calculatedFPS))
                }
            }
        }
    }
}
