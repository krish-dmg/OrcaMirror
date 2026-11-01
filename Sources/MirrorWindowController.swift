import Cocoa
import AVFoundation

final class MirrorWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape key
            if styleMask.contains(.fullScreen) {
                toggleFullScreen(nil)
                return
            }
        }
        super.keyDown(with: event)
    }
}

final class MirrorWindowController: NSWindowController, NSWindowDelegate {
    let captureController: CaptureController
    private(set) var mirrorVC: MirrorViewController!

    var isAspectRatioLocked: Bool = false

    init(captureController: CaptureController) {
        self.captureController = captureController

        let initialRect = NSRect(x: 100, y: 100, width: 1152, height: 720)
        let styleMask: NSWindow.StyleMask = [
            .titled,
            .closable,
            .miniaturizable,
            .resizable
        ]

        let window = MirrorWindow(
            contentRect: initialRect,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )

        super.init(window: window)

        window.delegate = self
        window.title = "OrcaMirror"
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.fullScreenPrimary, .canJoinAllSpaces]
        window.sharingType = .readOnly
        window.backgroundColor = .black
        window.setFrameAutosaveName("OrcaMirrorWindow")

        mirrorVC = MirrorViewController(captureController: captureController)
        window.contentViewController = mirrorVC

        setupCallbacks()

        // Slight delay to allow CoreMediaIO DAL discovery to settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.autoConnect()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupCallbacks() {
        captureController.onStateChanged = { [weak self] state in
            guard let self = self else { return }
            self.mirrorVC.handleStateChange(state)
            self.updateTitle()
        }

        captureController.onResolutionChanged = { [weak self] size in
            guard let self = self else { return }
            self.updateTitle()
        }

        NotificationCenter.default.addObserver(
            forName: .orcaDevicesChanged,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let self = self, let devices = notif.object as? [AVCaptureDevice] else { return }
            if let current = self.captureController.currentDevice {
                if !devices.contains(where: { $0.uniqueID == current.uniqueID }) {
                    // Device disconnected
                    self.captureController.stop()
                }
            } else if let first = devices.first {
                // New device connected
                self.captureController.start(with: first)
            }
        }
    }

    func autoConnect(retryCount: Int = 0) {
        if captureController.currentDevice != nil { return }
        let devices = DeviceManager.shared.availableIOSDevices()
        if let first = devices.first {
            captureController.start(with: first)
        } else if retryCount < 10 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self = self, self.captureController.currentDevice == nil else { return }
                self.autoConnect(retryCount: retryCount + 1)
            }
        }
    }

    func reconnectCurrentDevice() {
        let devices = DeviceManager.shared.availableIOSDevices()
        if let first = devices.first {
            captureController.start(with: first)
        }
    }

    private var preBorderlessFrame: NSRect?

    func toggleFullscreen() {
        window?.toggleFullScreen(nil)
    }

    func toggleBorderlessFullscreen() {
        toggleFullscreen()
    }

    var isBorderlessFullscreen: Bool {
        return preBorderlessFrame != nil || (window?.styleMask.contains(.fullScreen) == true)
    }

    func toggleBorderlessWindowed() {
        guard let win = window, let screen = win.screen ?? NSScreen.main else { return }
        if let oldFrame = preBorderlessFrame {
            preBorderlessFrame = nil
            win.setFrame(oldFrame, display: true)
        } else {
            preBorderlessFrame = win.frame
            win.setFrame(screen.frame, display: true)
        }
    }

    func maximizeToScreen() {
        guard let win = window, let screen = win.screen ?? NSScreen.main else { return }
        win.setFrame(screen.visibleFrame, display: true)
    }

    func setNativeNonStretched() {
        guard let win = window, let screen = win.screen ?? NSScreen.main else { return }
        if win.styleMask.contains(.fullScreen) {
            win.toggleFullScreen(nil)
        }
        mirrorVC.setVideoGravity(.resizeAspect)

        let res = captureController.currentResolution
        let nativeRatio = (res.width > 0 && res.height > 0) ? (res.width / res.height) : (1718.0 / 1200.0)

        let vf = screen.visibleFrame
        let targetHeight = min(vf.height - 80, 760)
        let targetWidth = round(targetHeight * nativeRatio)

        let newOrigin = CGPoint(
            x: vf.midX - targetWidth / 2.0,
            y: vf.midY - targetHeight / 2.0
        )
        win.setFrame(NSRect(origin: newOrigin, size: CGSize(width: targetWidth, height: targetHeight)), display: true)
    }

    func setStretchMacBookRetina() {
        guard let win = window, let screen = win.screen ?? NSScreen.main else { return }
        if win.styleMask.contains(.fullScreen) {
            win.toggleFullScreen(nil)
        }
        mirrorVC.setVideoGravity(.resize)

        let vf = screen.visibleFrame
        let targetHeight = min(vf.height - 80, 760)
        let targetWidth = round(targetHeight * (16.0 / 10.0))

        let newOrigin = CGPoint(
            x: vf.midX - targetWidth / 2.0,
            y: vf.midY - targetHeight / 2.0
        )
        win.setFrame(NSRect(origin: newOrigin, size: CGSize(width: targetWidth, height: targetHeight)), display: true)
    }

    func setStretchWidescreen16x9() {
        guard let win = window, let screen = win.screen ?? NSScreen.main else { return }
        if win.styleMask.contains(.fullScreen) {
            win.toggleFullScreen(nil)
        }
        mirrorVC.setVideoGravity(.resize)

        let vf = screen.visibleFrame
        let targetHeight = min(vf.height - 80, 720)
        let targetWidth = round(targetHeight * (16.0 / 9.0))

        let newOrigin = CGPoint(
            x: vf.midX - targetWidth / 2.0,
            y: vf.midY - targetHeight / 2.0
        )
        win.setFrame(NSRect(origin: newOrigin, size: CGSize(width: targetWidth, height: targetHeight)), display: true)
    }

    func updateTitle() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let win = self.window else { return }
            if let dev = self.captureController.currentDevice {
                win.title = "OrcaMirror — \(dev.localizedName)"
                win.subtitle = ""
            } else {
                win.title = "OrcaMirror"
                win.subtitle = ""
            }
        }
    }

    func setScale(_ factor: CGFloat) {
        guard let win = window else { return }
        if win.styleMask.contains(.fullScreen) {
            win.toggleFullScreen(nil)
        }
        let res = captureController.currentResolution
        let baseWidth = res.width > 0 ? (res.width / 2.0) : 859.0
        let baseHeight = res.height > 0 ? (res.height / 2.0) : 600.0

        let targetWidth = baseWidth * factor
        let targetHeight = baseHeight * factor

        var frame = win.frame
        let oldCenter = CGPoint(x: frame.midX, y: frame.midY)
        frame.size = CGSize(width: targetWidth, height: targetHeight)
        frame.origin = CGPoint(
            x: oldCenter.x - targetWidth / 2.0,
            y: oldCenter.y - targetHeight / 2.0
        )

        win.setFrame(frame, display: true)
    }

    func windowWillClose(_ notification: Notification) {
        captureController.stop()
        NSApplication.shared.terminate(nil)
    }
}
