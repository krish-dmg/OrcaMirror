import Cocoa
import AVFoundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: MirrorWindowController?
    private var controlsWindowController: ControlsWindowController?
    private let captureController = CaptureController()
    private var deviceMenu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        setupMainMenu()

        windowController = MirrorWindowController(captureController: captureController)
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)

        updateDeviceMenu()
        NotificationCenter.default.addObserver(
            forName: .orcaDevicesChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateDeviceMenu()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func openControlsPanel() {
        if controlsWindowController == nil,
           let win = windowController?.window,
           let mvc = win.contentViewController as? MirrorViewController {
            controlsWindowController = ControlsWindowController(captureController: captureController, mirrorVC: mvc)
        }
        controlsWindowController?.syncWithCurrentSettings()
        controlsWindowController?.showWindow(nil)
        controlsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Menu Construction

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App Menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About OrcaMirror", action: #selector(aboutAction), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Preferences / Controls...", action: #selector(openControlsAction), keyEquivalent: ",")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide OrcaMirror", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit OrcaMirror", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Device Menu
        let deviceMenuItem = NSMenuItem()
        deviceMenuItem.title = "Device"
        let devMenu = NSMenu(title: "Device")
        devMenu.addItem(withTitle: "Reconnect / Refresh", action: #selector(reconnectAction), keyEquivalent: "r")
        devMenu.addItem(NSMenuItem.separator())
        self.deviceMenu = devMenu
        deviceMenuItem.submenu = devMenu
        mainMenu.addItem(deviceMenuItem)

        // Color Menu
        let colorMenuItem = NSMenuItem()
        colorMenuItem.title = "Color"
        let colorMenu = NSMenu(title: "Color")
        for preset in ColorPreset.allCases {
            let item = NSMenuItem(title: preset.rawValue, action: #selector(selectPresetAction(_:)), keyEquivalent: "")
            colorMenu.addItem(item)
        }
        colorMenu.addItem(NSMenuItem.separator())
        colorMenu.addItem(withTitle: "Color Adjustments...", action: #selector(openControlsAction), keyEquivalent: "c")
        colorMenuItem.submenu = colorMenu
        mainMenu.addItem(colorMenuItem)

        // Resolution & Quality Menu
        let qualityMenuItem = NSMenuItem()
        qualityMenuItem.title = "Resolution & Presets"
        let qualityMenu = NSMenu(title: "Resolution & Presets")
        qualityMenu.addItem(withTitle: "1080p Stream High Quality (1920x1080)", action: #selector(setQuality1080Action), keyEquivalent: "")
        qualityMenu.addItem(withTitle: "Native Device Resolution", action: #selector(setQualityHighAction), keyEquivalent: "")
        qualityMenu.addItem(withTitle: "720p Performance (1280x720)", action: #selector(setQuality720Action), keyEquivalent: "")
        qualityMenu.addItem(NSMenuItem.separator())
        qualityMenu.addItem(withTitle: "Native Aspect Ratio (Non-Stretched)", action: #selector(setNativeNonStretchedAction), keyEquivalent: "8")
        qualityMenu.addItem(withTitle: "MacBook 16:10 Stretched (Windowed)", action: #selector(setStretchMacBookRetinaAction), keyEquivalent: "0")
        qualityMenu.addItem(withTitle: "Widescreen 16:9 Stretched (Windowed)", action: #selector(setStretchWidescreen16x9Action), keyEquivalent: "9")
        qualityMenuItem.submenu = qualityMenu
        mainMenu.addItem(qualityMenuItem)

        // View Menu
        let viewMenuItem = NSMenuItem()
        viewMenuItem.title = "View"
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Native Aspect Ratio (Non-Stretched)", action: #selector(setNativeNonStretchedAction), keyEquivalent: "8")
        viewMenu.addItem(withTitle: "MacBook 16:10 Stretched (Windowed)", action: #selector(setStretchMacBookRetinaAction), keyEquivalent: "0")
        viewMenu.addItem(withTitle: "Widescreen 16:9 Stretched (Windowed)", action: #selector(setStretchWidescreen16x9Action), keyEquivalent: "9")
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(withTitle: "Toggle Native Fullscreen", action: #selector(toggleFullscreenAction), keyEquivalent: "f")
        let borderlessItem = NSMenuItem(title: "Borderless Fullscreen (Current Desktop)", action: #selector(toggleBorderlessWindowedAction), keyEquivalent: "f")
        borderlessItem.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(borderlessItem)
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(withTitle: "Always on Top", action: #selector(toggleFloatingAction), keyEquivalent: "t")
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(withTitle: "Actual Size (100%)", action: #selector(scale100Action), keyEquivalent: "1")
        viewMenu.addItem(withTitle: "Scale 75%", action: #selector(scale75Action), keyEquivalent: "2")
        viewMenu.addItem(withTitle: "Scale 50%", action: #selector(scale50Action), keyEquivalent: "3")
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Audio Menu
        let audioMenuItem = NSMenuItem()
        audioMenuItem.title = "Audio"
        let audioMenu = NSMenu(title: "Audio")
        let muteItem = NSMenuItem(title: "Mute Audio", action: #selector(toggleMuteAction), keyEquivalent: "m")
        muteItem.keyEquivalentModifierMask = [.command, .shift]
        audioMenu.addItem(muteItem)
        audioMenu.addItem(NSMenuItem.separator())
        audioMenu.addItem(withTitle: "Volume 100%", action: #selector(setVolume100Action), keyEquivalent: "")
        audioMenu.addItem(withTitle: "Volume 75%", action: #selector(setVolume75Action), keyEquivalent: "")
        audioMenu.addItem(withTitle: "Volume 50%", action: #selector(setVolume50Action), keyEquivalent: "")
        audioMenu.addItem(withTitle: "Volume 25%", action: #selector(setVolume25Action), keyEquivalent: "")
        audioMenuItem.submenu = audioMenu
        mainMenu.addItem(audioMenuItem)

        // Window Menu
        let windowMenuItem = NSMenuItem()
        windowMenuItem.title = "Window"
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func updateDeviceMenu() {
        guard let devMenu = deviceMenu else { return }

        while devMenu.items.count > 2 {
            devMenu.removeItem(at: 2)
        }

        let devices = DeviceManager.shared.availableIOSDevices()
        if devices.isEmpty {
            let item = NSMenuItem(title: "No iOS Devices Detected", action: nil, keyEquivalent: "")
            item.isEnabled = false
            devMenu.addItem(item)
        } else {
            for (idx, dev) in devices.enumerated() {
                let isCurrent = (dev.uniqueID == captureController.currentDevice?.uniqueID)
                let item = NSMenuItem(
                    title: "\(dev.localizedName)\(isCurrent ? " (Active)" : "")",
                    action: #selector(selectDeviceAction(_:)),
                    keyEquivalent: ""
                )
                item.tag = idx
                item.state = isCurrent ? .on : .off
                devMenu.addItem(item)
            }
        }
    }

    // MARK: - Actions

    @objc private func aboutAction() {
        let alert = NSAlert()
        alert.messageText = "OrcaMirror"
        alert.informativeText = "High-performance native macOS USB iPhone & iPad screen mirror.\nDirect AVFoundation hardware capture with zero AirPlay overhead.\nNative 60 FPS, ultra-low latency, custom color profiles."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc func openControlsAction() {
        openControlsPanel()
    }

    @objc private func selectPresetAction(_ sender: NSMenuItem) {
        if let preset = ColorPreset(rawValue: sender.title) {
            ColorProfileManager.shared.selectPreset(preset)
            controlsWindowController?.syncWithCurrentSettings()
        }
    }

    @objc private func setNativeNonStretchedAction() {
        windowController?.setNativeNonStretched()
        controlsWindowController?.syncWithCurrentSettings()
    }

    @objc private func setStretchMacBookRetinaAction() {
        windowController?.setStretchMacBookRetina()
        controlsWindowController?.syncWithCurrentSettings()
    }

    @objc private func setStretchWidescreen16x9Action() {
        windowController?.setStretchWidescreen16x9()
        controlsWindowController?.syncWithCurrentSettings()
    }

    @objc private func setQualityHighAction() {
        captureController.setQualityPreset(.high)
        controlsWindowController?.syncWithCurrentSettings()
    }

    @objc private func setQuality1080Action() {
        captureController.setQualityPreset(.hd1920x1080)
        controlsWindowController?.syncWithCurrentSettings()
    }

    @objc private func setQuality720Action() {
        captureController.setQualityPreset(.hd1280x720)
        controlsWindowController?.syncWithCurrentSettings()
    }

    @objc private func setFitScalingAction() {
        guard let mvc = windowController?.window?.contentViewController as? MirrorViewController else { return }
        mvc.setVideoGravity(.resizeAspect)
        windowController?.isAspectRatioLocked = true
        controlsWindowController?.syncWithCurrentSettings()
    }

    @objc private func setFillScalingAction() {
        guard let mvc = windowController?.window?.contentViewController as? MirrorViewController else { return }
        mvc.setVideoGravity(.resizeAspectFill)
        windowController?.isAspectRatioLocked = false
        controlsWindowController?.syncWithCurrentSettings()
    }

    @objc private func setStretchScalingAction() {
        guard let mvc = windowController?.window?.contentViewController as? MirrorViewController else { return }
        mvc.setVideoGravity(.resize)
        windowController?.isAspectRatioLocked = false
        controlsWindowController?.syncWithCurrentSettings()
    }

    @objc private func reconnectAction() {
        windowController?.reconnectCurrentDevice()
    }

    @objc private func selectDeviceAction(_ sender: NSMenuItem) {
        let devices = DeviceManager.shared.availableIOSDevices()
        if sender.tag >= 0 && sender.tag < devices.count {
            captureController.start(with: devices[sender.tag])
            updateDeviceMenu()
        }
    }

    @objc private func toggleFullscreenAction() {
        windowController?.toggleFullscreen()
    }

    @objc private func toggleBorderlessWindowedAction() {
        windowController?.toggleBorderlessWindowed()
    }

    @objc private func toggleAspectRatioLockAction() {
        windowController?.isAspectRatioLocked.toggle()
    }

    @objc private func toggleFloatingAction() {
        guard let win = windowController?.window else { return }
        win.level = (win.level == .floating) ? .normal : .floating
    }

    @objc private func scale100Action() {
        windowController?.setScale(1.0)
    }

    @objc private func scale75Action() {
        windowController?.setScale(0.75)
    }

    @objc private func scale50Action() {
        windowController?.setScale(0.5)
    }

    @objc private func toggleMuteAction() {
        captureController.isAudioMuted.toggle()
        controlsWindowController?.syncWithCurrentSettings()
    }

    @objc private func setVolume100Action() {
        captureController.audioVolume = 1.0
        captureController.isAudioMuted = false
        controlsWindowController?.syncWithCurrentSettings()
    }

    @objc private func setVolume75Action() {
        captureController.audioVolume = 0.75
        captureController.isAudioMuted = false
        controlsWindowController?.syncWithCurrentSettings()
    }

    @objc private func setVolume50Action() {
        captureController.audioVolume = 0.5
        captureController.isAudioMuted = false
        controlsWindowController?.syncWithCurrentSettings()
    }

    @objc private func setVolume25Action() {
        captureController.audioVolume = 0.25
        captureController.isAudioMuted = false
        controlsWindowController?.syncWithCurrentSettings()
    }
}
