import Foundation
import AVFoundation
import CoreMediaIO

extension Notification.Name {
    static let orcaDevicesChanged = Notification.Name("OrcaMirrorDevicesChanged")
}

final class DeviceManager {
    static let shared = DeviceManager()

    private init() {
        enableScreenCaptureDevices()
        setupNotificationObservers()
    }

    func enableScreenCaptureDevices() {
        var prop = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var allow: UInt32 = 1
        let dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = CMIOObjectSetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &prop,
            0,
            nil,
            dataSize,
            &allow
        )
        if status != noErr {
            NSLog("CoreMediaIO: Failed to set allowScreenCaptureDevices: %d", status)
        }
    }

    func availableIOSDevices() -> [AVCaptureDevice] {
        let externalType: AVCaptureDevice.DeviceType
        if #available(macOS 14.0, *) {
            externalType = .external
        } else {
            externalType = .externalUnknown
        }

        let muxedDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [externalType],
            mediaType: .muxed,
            position: .unspecified
        )
        var devices = muxedDiscovery.devices.filter { isIOSDevice($0) }

        if devices.isEmpty {
            let videoDiscovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [externalType],
                mediaType: .video,
                position: .unspecified
            )
            devices = videoDiscovery.devices.filter { isIOSDevice($0) }
        }

        return devices
    }

    private func isIOSDevice(_ device: AVCaptureDevice) -> Bool {
        if device.modelID == "iOS Device" {
            return true
        }
        let lower = device.localizedName.lowercased()
        return lower.contains("ipad") || lower.contains("iphone")
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasConnectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            let devices = self.availableIOSDevices()
            NotificationCenter.default.post(name: .orcaDevicesChanged, object: devices)
        }

        NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            let devices = self.availableIOSDevices()
            NotificationCenter.default.post(name: .orcaDevicesChanged, object: devices)
        }
    }
}
