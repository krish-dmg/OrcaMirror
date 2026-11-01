import Foundation
import AVFoundation
import AudioToolbox
import CoreMediaIO
import Darwin

final class LowLatencyAudioPlayer: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private var audioUnit: AudioUnit?
    private var isRunning = false
    private var unfairLock = os_unfair_lock()

    // Ring buffer: 8192 stereo frames = 16384 Int16 samples (~170ms)
    // Power of two allows single-cycle bitwise masking (& 16383)
    private let capSamples = 16384
    private let mask = 16383
    private var ringBuffer: [Int16]
    private var writeHead = 0
    private var readHead = 0

    var volume: Float = 1.0
    var isMuted: Bool = false

    override init() {
        self.ringBuffer = [Int16](repeating: 0, count: 16384)
        super.init()
        setupAudioUnit()
    }

    private func setupAudioUnit() {
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_DefaultOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        guard let comp = AudioComponentFindNext(nil, &desc) else {
            NSLog("LowLatencyAudioPlayer: Failed to find DefaultOutput AudioComponent")
            return
        }

        var unit: AudioUnit?
        let status = AudioComponentInstanceNew(comp, &unit)
        guard status == noErr, let au = unit else {
            NSLog("LowLatencyAudioPlayer: Failed to create AudioUnit, status=%d", status)
            return
        }
        self.audioUnit = au

        // 48kHz, 2-channel stereo, 16-bit Signed Integer Linear PCM
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 48000.0,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 16,
            mReserved: 0
        )

        AudioUnitSetProperty(
            au,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            0,
            &asbd,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )

        let renderProc: AURenderCallback = { inRefCon, _, _, _, inNumberFrames, ioData -> OSStatus in
            guard let ioData = ioData else { return noErr }
            let player = Unmanaged<LowLatencyAudioPlayer>.fromOpaque(inRefCon).takeUnretainedValue()
            let abl = UnsafeMutableAudioBufferListPointer(ioData)
            guard abl.count > 0, let destPtr = abl[0].mData?.assumingMemoryBound(to: Int16.self) else { return noErr }

            player.renderAudio(into: destPtr, frames: Int(inNumberFrames))
            return noErr
        }

        var cbStruct = AURenderCallbackStruct(
            inputProc: renderProc,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )

        AudioUnitSetProperty(
            au,
            kAudioUnitProperty_SetRenderCallback,
            kAudioUnitScope_Input,
            0,
            &cbStruct,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )

        AudioUnitInitialize(au)
    }

    func start() {
        guard let au = audioUnit, !isRunning else { return }
        os_unfair_lock_lock(&unfairLock)
        writeHead = 0
        readHead = 0
        os_unfair_lock_unlock(&unfairLock)
        let status = AudioOutputUnitStart(au)
        isRunning = (status == noErr)
    }

    func stop() {
        guard let au = audioUnit, isRunning else { return }
        AudioOutputUnitStop(au)
        isRunning = false
    }

    private func renderAudio(into output: UnsafeMutablePointer<Int16>, frames: Int) {
        let vol = isMuted ? 0.0 : volume
        let neededSamples = frames * 2

        os_unfair_lock_lock(&unfairLock)
        let availSamples = (writeHead - readHead + capSamples) & mask
        let toRead = min(neededSamples, availSamples)

        if vol == 1.0 {
            for i in 0..<toRead {
                output[i] = ringBuffer[(readHead + i) & mask]
            }
        } else if vol == 0.0 {
            for i in 0..<toRead {
                output[i] = 0
            }
        } else {
            for i in 0..<toRead {
                let sample = ringBuffer[(readHead + i) & mask]
                output[i] = Int16(clamping: Int32(Float(sample) * vol))
            }
        }

        readHead = (readHead + toRead) & mask

        // Latency control: bound delay to 25-45ms (1200-2160 frames)
        let remaining = (writeHead - readHead + capSamples) & mask
        if remaining > 2160 * 2 {
            let skip = remaining - (1200 * 2)
            readHead = (readHead + skip) & mask
        }
        os_unfair_lock_unlock(&unfairLock)

        // Pad silence on brief underflow
        if toRead < neededSamples {
            output.advanced(by: toRead).initialize(repeating: 0, count: neededSamples - toRead)
        }
    }

    // MARK: - AVCaptureAudioDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isRunning else { return }

        guard let desc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc) else { return }

        var neededSize = 0
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &neededSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: nil
        )
        guard neededSize > 0 else { return }

        let rawPtr = UnsafeMutableRawPointer.allocate(byteCount: neededSize, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { rawPtr.deallocate() }
        let ablPtr = rawPtr.bindMemory(to: AudioBufferList.self, capacity: 1)
        var blockBuffer: CMBlockBuffer?

        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: ablPtr,
            bufferListSize: neededSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return }

        let bufferList = UnsafeMutableAudioBufferListPointer(ablPtr)
        guard bufferList.count > 0 else { return }

        let isFloat = (asbd.pointee.mFormatFlags & kAudioFormatFlagIsFloat) != 0

        os_unfair_lock_lock(&unfairLock)
        defer { os_unfair_lock_unlock(&unfairLock) }

        if bufferList.count == 1 {
            // Interleaved stereo (native iPad format from CoreMediaIO)
            let buf = bufferList[0]
            guard let mData = buf.mData else { return }

            if isFloat {
                let floatPtr = mData.assumingMemoryBound(to: Float.self)
                let sampleCount = Int(buf.mDataByteSize) / 4
                for i in 0..<sampleCount {
                    let clamped = max(-1.0, min(1.0, floatPtr[i]))
                    ringBuffer[(writeHead + i) & mask] = Int16(clamped * 32767.0)
                }
                writeHead = (writeHead + sampleCount) & mask
            } else {
                let int16Ptr = mData.assumingMemoryBound(to: Int16.self)
                let sampleCount = Int(buf.mDataByteSize) / 2
                for i in 0..<sampleCount {
                    ringBuffer[(writeHead + i) & mask] = int16Ptr[i]
                }
                writeHead = (writeHead + sampleCount) & mask
            }
        } else if bufferList.count >= 2 {
            // Non-interleaved stereo: buffer 0 is Left, buffer 1 is Right
            let b0 = bufferList[0]
            let b1 = bufferList[1]
            guard let mData0 = b0.mData, let mData1 = b1.mData else { return }

            if isFloat {
                let leftPtr = mData0.assumingMemoryBound(to: Float.self)
                let rightPtr = mData1.assumingMemoryBound(to: Float.self)
                let frameCount = Int(b0.mDataByteSize) / 4
                for i in 0..<frameCount {
                    let l = max(-1.0, min(1.0, leftPtr[i]))
                    let r = max(-1.0, min(1.0, rightPtr[i]))
                    ringBuffer[(writeHead + i * 2) & mask] = Int16(l * 32767.0)
                    ringBuffer[(writeHead + i * 2 + 1) & mask] = Int16(r * 32767.0)
                }
                writeHead = (writeHead + frameCount * 2) & mask
            } else {
                let leftPtr = mData0.assumingMemoryBound(to: Int16.self)
                let rightPtr = mData1.assumingMemoryBound(to: Int16.self)
                let frameCount = Int(b0.mDataByteSize) / 2
                for i in 0..<frameCount {
                    ringBuffer[(writeHead + i * 2) & mask] = leftPtr[i]
                    ringBuffer[(writeHead + i * 2 + 1) & mask] = rightPtr[i]
                }
                writeHead = (writeHead + frameCount * 2) & mask
            }
        }
    }

    deinit {
        if let au = audioUnit {
            AudioOutputUnitStop(au)
            AudioUnitUninitialize(au)
            AudioComponentInstanceDispose(au)
        }
    }
}
