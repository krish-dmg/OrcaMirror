import Cocoa
import AVFoundation

final class VideoPreviewView: NSView {
    var previewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }

    override func makeBackingLayer() -> CALayer {
        let l = AVCaptureVideoPreviewLayer()
        if let saved = UserDefaults.standard.string(forKey: "OrcaMirror_VideoGravity") {
            l.videoGravity = AVLayerVideoGravity(rawValue: saved)
        } else {
            l.videoGravity = .resize
        }
        return l
    }
}

final class MirrorViewController: NSViewController {
    let captureController: CaptureController
    let previewView = VideoPreviewView()

    private let emptyStateContainer = NSView()
    private let emptyTitleLabel = NSTextField(labelWithString: "No iPad Connected")
    private let emptySubtitleLabel = NSTextField(labelWithString: "Connect your iPad via USB, unlock the screen, and trust this Mac.")
    private let spinner = NSProgressIndicator()

    init(captureController: CaptureController) {
        self.captureController = captureController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 859, height: 600))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupPreviewView()
        setupEmptyState()
        setupBindings()
        applyColorGrading()
    }

    private func setupPreviewView() {
        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.wantsLayer = true
        previewView.previewLayer.session = captureController.session
        view.addSubview(previewView)

        NSLayoutConstraint.activate([
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupEmptyState() {
        emptyStateContainer.translatesAutoresizingMaskIntoConstraints = false
        emptyStateContainer.wantsLayer = true
        view.addSubview(emptyStateContainer)

        emptyTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyTitleLabel.font = NSFont.systemFont(ofSize: 18, weight: .bold)
        emptyTitleLabel.textColor = NSColor(white: 0.9, alpha: 1.0)
        emptyTitleLabel.alignment = .center

        emptySubtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        emptySubtitleLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        emptySubtitleLabel.textColor = NSColor(white: 0.6, alpha: 1.0)
        emptySubtitleLabel.alignment = .center
        emptySubtitleLabel.maximumNumberOfLines = 2

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.startAnimation(nil)

        emptyStateContainer.addSubview(emptyTitleLabel)
        emptyStateContainer.addSubview(emptySubtitleLabel)
        emptyStateContainer.addSubview(spinner)

        NSLayoutConstraint.activate([
            emptyStateContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateContainer.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStateContainer.widthAnchor.constraint(lessThanOrEqualToConstant: 450),

            spinner.centerXAnchor.constraint(equalTo: emptyStateContainer.centerXAnchor),
            spinner.topAnchor.constraint(equalTo: emptyStateContainer.topAnchor),

            emptyTitleLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 16),
            emptyTitleLabel.leadingAnchor.constraint(equalTo: emptyStateContainer.leadingAnchor),
            emptyTitleLabel.trailingAnchor.constraint(equalTo: emptyStateContainer.trailingAnchor),

            emptySubtitleLabel.topAnchor.constraint(equalTo: emptyTitleLabel.bottomAnchor, constant: 8),
            emptySubtitleLabel.leadingAnchor.constraint(equalTo: emptyStateContainer.leadingAnchor),
            emptySubtitleLabel.trailingAnchor.constraint(equalTo: emptyStateContainer.trailingAnchor),
            emptySubtitleLabel.bottomAnchor.constraint(equalTo: emptyStateContainer.bottomAnchor)
        ])
    }

    private func setupBindings() {
        captureController.onStateChanged = { [weak self] state in
            DispatchQueue.main.async {
                self?.handleStateChange(state)
            }
        }

        ColorProfileManager.shared.onProfileChanged = { [weak self] in
            DispatchQueue.main.async {
                self?.applyColorGrading()
            }
        }
    }

    func applyColorGrading() {
        ColorProfileManager.shared.applyToLayer(previewView.previewLayer)
    }

    func setVideoGravity(_ gravity: AVLayerVideoGravity) {
        previewView.previewLayer.videoGravity = gravity
        UserDefaults.standard.set(gravity.rawValue, forKey: "OrcaMirror_VideoGravity")
    }

    func handleStateChange(_ state: CaptureState) {
        switch state {
        case .idle:
            emptyTitleLabel.stringValue = "No iPad Connected"
            emptySubtitleLabel.stringValue = "Connect your iPad via USB, unlock the screen, and trust this Mac."
            emptyStateContainer.isHidden = false
            spinner.startAnimation(nil)

        case .connecting(let name):
            emptyTitleLabel.stringValue = "Connecting to \(name)..."
            emptySubtitleLabel.stringValue = "Initializing low-latency hardware capture session."
            emptyStateContainer.isHidden = false
            spinner.startAnimation(nil)

        case .streaming:
            // Zero watermark overlays: completely clean stream display
            emptyStateContainer.isHidden = true
            spinner.stopAnimation(nil)

        case .paused:
            break

        case .failed(let err):
            emptyTitleLabel.stringValue = "Connection Issue"
            emptySubtitleLabel.stringValue = err
            emptyStateContainer.isHidden = false
            spinner.stopAnimation(nil)
        }
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            (view.window?.windowController as? MirrorWindowController)?.toggleFullscreen()
        } else {
            super.mouseDown(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu(title: "Mirror Actions")
        let mwc = view.window?.windowController as? MirrorWindowController

        menu.addItem(withTitle: "Display & Color Controls... (Cmd+,)", action: #selector(openControlsAction), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())

        let isFull = (mwc?.isBorderlessFullscreen == true)
        menu.addItem(withTitle: isFull ? "Exit Fullscreen (Esc / Cmd+F)" : "Enter Fullscreen (Cmd+F)", action: #selector(toggleFullscreenAction), keyEquivalent: "")
        menu.addItem(withTitle: "Borderless Fullscreen (Cmd+Shift+F)", action: #selector(toggleBorderlessAction), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Native iPad (Non-Stretched 4:3) (Cmd+8)", action: #selector(nativeNonStretchedAction), keyEquivalent: "")
        menu.addItem(withTitle: "MacBook 16:10 Stretched (Windowed) (Cmd+0)", action: #selector(macStretchAction), keyEquivalent: "")
        menu.addItem(withTitle: "Widescreen 16:9 Stretched (Windowed) (Cmd+9)", action: #selector(wideStretchAction), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())

        let isFloating = (view.window?.level == .floating)
        let floatItem = NSMenuItem(title: "Always on Top (Cmd+T)", action: #selector(toggleFloatingAction), keyEquivalent: "")
        floatItem.state = isFloating ? .on : .off
        menu.addItem(floatItem)

        let isLocked = (mwc?.isAspectRatioLocked == true)
        let lockItem = NSMenuItem(title: "Lock Native Aspect Ratio (Cmd+L)", action: #selector(toggleAspectRatioLockAction), keyEquivalent: "")
        lockItem.state = isLocked ? .on : .off
        menu.addItem(lockItem)

        menu.addItem(NSMenuItem.separator())

        let muteItem = NSMenuItem(title: captureController.isAudioMuted ? "Unmute Audio (Cmd+Shift+M)" : "Mute Audio (Cmd+Shift+M)", action: #selector(toggleMuteAction), keyEquivalent: "")
        menu.addItem(muteItem)

        menu.addItem(NSMenuItem.separator())

        // Color profiles submenu
        let colorSubmenu = NSMenu(title: "Color Profile")
        for preset in ColorPreset.allCases {
            let item = NSMenuItem(title: preset.rawValue, action: #selector(selectPresetFromMenu(_:)), keyEquivalent: "")
            item.state = (ColorProfileManager.shared.currentPreset == preset) ? .on : .off
            colorSubmenu.addItem(item)
        }
        let colorMenuItem = NSMenuItem(title: "Color Profile", action: nil, keyEquivalent: "")
        colorMenuItem.submenu = colorSubmenu
        menu.addItem(colorMenuItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(withTitle: "Actual Size (100%)", action: #selector(actualSizeAction), keyEquivalent: "")
        menu.addItem(withTitle: "Scale 75%", action: #selector(scale75Action), keyEquivalent: "")
        menu.addItem(withTitle: "Scale 50%", action: #selector(scale50Action), keyEquivalent: "")

        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Reconnect Device (Cmd+R)", action: #selector(reconnectAction), keyEquivalent: "")

        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    @objc private func openControlsAction() {
        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else { return }
        appDelegate.openControlsPanel()
    }

    @objc private func selectPresetFromMenu(_ sender: NSMenuItem) {
        if let preset = ColorPreset(rawValue: sender.title) {
            ColorProfileManager.shared.selectPreset(preset)
        }
    }

    @objc private func toggleFullscreenAction() {
        (view.window?.windowController as? MirrorWindowController)?.toggleFullscreen()
    }

    @objc private func toggleBorderlessAction() {
        (view.window?.windowController as? MirrorWindowController)?.toggleBorderlessWindowed()
    }

    @objc private func nativeNonStretchedAction() {
        (view.window?.windowController as? MirrorWindowController)?.setNativeNonStretched()
    }

    @objc private func macStretchAction() {
        (view.window?.windowController as? MirrorWindowController)?.setStretchMacBookRetina()
    }

    @objc private func wideStretchAction() {
        (view.window?.windowController as? MirrorWindowController)?.setStretchWidescreen16x9()
    }

    @objc private func toggleAspectRatioLockAction() {
        guard let winController = view.window?.windowController as? MirrorWindowController else { return }
        winController.isAspectRatioLocked.toggle()
    }

    @objc private func toggleFloatingAction() {
        guard let win = view.window else { return }
        win.level = (win.level == .floating) ? .normal : .floating
    }

    @objc private func toggleMuteAction() {
        captureController.isAudioMuted.toggle()
    }

    @objc private func actualSizeAction() {
        guard let winController = view.window?.windowController as? MirrorWindowController else { return }
        winController.setScale(1.0)
    }

    @objc private func scale75Action() {
        guard let winController = view.window?.windowController as? MirrorWindowController else { return }
        winController.setScale(0.75)
    }

    @objc private func scale50Action() {
        guard let winController = view.window?.windowController as? MirrorWindowController else { return }
        winController.setScale(0.5)
    }

    @objc private func reconnectAction() {
        guard let winController = view.window?.windowController as? MirrorWindowController else { return }
        winController.reconnectCurrentDevice()
    }
}
