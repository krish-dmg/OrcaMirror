import Cocoa
import AVFoundation

final class ControlsWindowController: NSWindowController {
    private let captureController: CaptureController
    private weak var mirrorVC: MirrorViewController?

    private let presetPopup = NSPopUpButton()
    private let brightnessSlider = NSSlider()
    private let contrastSlider = NSSlider()
    private let saturationSlider = NSSlider()
    private let gammaSlider = NSSlider()
    private let sharpnessSlider = NSSlider()

    private let brightnessLabel = NSTextField(labelWithString: "0%")
    private let contrastLabel = NSTextField(labelWithString: "100%")
    private let saturationLabel = NSTextField(labelWithString: "100%")
    private let gammaLabel = NSTextField(labelWithString: "1.00")
    private let sharpnessLabel = NSTextField(labelWithString: "20%")

    private let qualityPopup = NSPopUpButton()
    private let scalingPopup = NSPopUpButton()
    private let liveStatsLabel = NSTextField(labelWithString: "Active Feed: 1920x1080 @ 60 FPS")

    private let volumeSlider = NSSlider()
    private let muteCheckbox = NSButton(checkboxWithTitle: "Mute Audio", target: nil, action: nil)

    init(captureController: CaptureController, mirrorVC: MirrorViewController) {
        self.captureController = captureController
        self.mirrorVC = mirrorVC

        let panel = NSPanel(
            contentRect: NSRect(x: 200, y: 200, width: 380, height: 600),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Display & Stream Controls"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false

        super.init(window: panel)

        setupUI()
        syncWithCurrentSettings()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let panel = window, let contentView = panel.contentView else { return }

        let scrollView = NSScrollView(frame: contentView.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 14
        rootStack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 20, right: 20)
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        // 1. Color Grading & Texture Section
        let colorHeader = makeHeaderLabel(text: "COLOR PROFILES & TEXTURE CLARITY")
        rootStack.addArrangedSubview(colorHeader)

        // Preset row
        let presetRow = makeLabelAndControlRow(label: "Color Profile:", control: presetPopup)
        for preset in ColorPreset.allCases {
            presetPopup.addItem(withTitle: preset.rawValue)
        }
        presetPopup.target = self
        presetPopup.action = #selector(presetChanged(_:))
        rootStack.addArrangedSubview(presetRow)

        // Sharpness row (GPU-accelerated CISharpenLuminance)
        sharpnessSlider.minValue = 0.00
        sharpnessSlider.maxValue = 1.00
        sharpnessSlider.target = self
        sharpnessSlider.action = #selector(sharpnessChanged(_:))
        rootStack.addArrangedSubview(makeSliderRow(label: "Sharpness (Clarity):", slider: sharpnessSlider, valueLabel: sharpnessLabel))

        // Brightness row
        brightnessSlider.minValue = -0.30
        brightnessSlider.maxValue = 0.30
        brightnessSlider.target = self
        brightnessSlider.action = #selector(brightnessChanged(_:))
        rootStack.addArrangedSubview(makeSliderRow(label: "Brightness:", slider: brightnessSlider, valueLabel: brightnessLabel))

        // Contrast row
        contrastSlider.minValue = 0.70
        contrastSlider.maxValue = 1.60
        contrastSlider.target = self
        contrastSlider.action = #selector(contrastChanged(_:))
        rootStack.addArrangedSubview(makeSliderRow(label: "Contrast:", slider: contrastSlider, valueLabel: contrastLabel))

        // Saturation row
        saturationSlider.minValue = 0.00
        saturationSlider.maxValue = 2.00
        saturationSlider.target = self
        saturationSlider.action = #selector(saturationChanged(_:))
        rootStack.addArrangedSubview(makeSliderRow(label: "Saturation:", slider: saturationSlider, valueLabel: saturationLabel))

        // Gamma row
        gammaSlider.minValue = 0.60
        gammaSlider.maxValue = 1.40
        gammaSlider.target = self
        gammaSlider.action = #selector(gammaChanged(_:))
        rootStack.addArrangedSubview(makeSliderRow(label: "Gamma (Shadows):", slider: gammaSlider, valueLabel: gammaLabel))

        // Reset Preset Button
        let resetBtn = NSButton(title: "Reset to Studio Calibrated", target: self, action: #selector(resetToCalibratedAction))
        resetBtn.bezelStyle = .rounded
        rootStack.addArrangedSubview(resetBtn)

        rootStack.addArrangedSubview(makeSeparator())

        // 2. Window Display & Scaling Modes (OBS Safe)
        let stretchHeader = makeHeaderLabel(text: "DISPLAY RATIOS & SCALING (OBS SAFE)")
        rootStack.addArrangedSubview(stretchHeader)

        let stretchBtnStack = NSStackView()
        stretchBtnStack.orientation = .horizontal
        stretchBtnStack.spacing = 8

        let nativeBtn = NSButton(title: "Native Non-Stretched (Cmd+8)", target: self, action: #selector(nativeNonStretchedAction))
        nativeBtn.bezelStyle = .rounded
        stretchBtnStack.addArrangedSubview(nativeBtn)

        let macStretchBtn = NSButton(title: "MacBook 16:10 (Cmd+0)", target: self, action: #selector(macStretchAction))
        macStretchBtn.bezelStyle = .rounded
        stretchBtnStack.addArrangedSubview(macStretchBtn)

        let wideStretchBtn = NSButton(title: "16:9 (Cmd+9)", target: self, action: #selector(wideStretchAction))
        wideStretchBtn.bezelStyle = .rounded
        stretchBtnStack.addArrangedSubview(wideStretchBtn)

        rootStack.addArrangedSubview(stretchBtnStack)

        // Scaling mode row
        scalingPopup.removeAllItems()
        scalingPopup.addItem(withTitle: "Native Aspect Fit (Preserve 4:3)")
        scalingPopup.addItem(withTitle: "Stretch to Window (No Black Bars)")
        scalingPopup.addItem(withTitle: "Aspect Fill (Crop to Window)")
        scalingPopup.target = self
        scalingPopup.action = #selector(scalingChanged(_:))
        rootStack.addArrangedSubview(makeLabelAndControlRow(label: "Fill Mode:", control: scalingPopup))

        rootStack.addArrangedSubview(makeSeparator())

        // 3. Performance & Quality Section
        let perfHeader = makeHeaderLabel(text: "STREAM RESOLUTION (60 FPS HARDWARE LOCKED)")
        rootStack.addArrangedSubview(perfHeader)

        // Quality preset row
        qualityPopup.removeAllItems()
        qualityPopup.addItem(withTitle: "1080p Stream High Quality (1920x1080)")
        qualityPopup.addItem(withTitle: "Native Device Resolution")
        qualityPopup.addItem(withTitle: "720p Performance (1280x720)")
        qualityPopup.target = self
        qualityPopup.action = #selector(qualityChanged(_:))
        rootStack.addArrangedSubview(makeLabelAndControlRow(label: "Hardware Preset:", control: qualityPopup))

        liveStatsLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        liveStatsLabel.textColor = .secondaryLabelColor
        rootStack.addArrangedSubview(liveStatsLabel)

        rootStack.addArrangedSubview(makeSeparator())

        // 4. Audio Section
        let audioHeader = makeHeaderLabel(text: "AUDIO PASSTHROUGH")
        rootStack.addArrangedSubview(audioHeader)

        volumeSlider.minValue = 0.0
        volumeSlider.maxValue = 1.0
        volumeSlider.target = self
        volumeSlider.action = #selector(volumeChanged(_:))
        rootStack.addArrangedSubview(makeSliderRow(label: "Volume:", slider: volumeSlider, valueLabel: nil))

        muteCheckbox.target = self
        muteCheckbox.action = #selector(muteToggled(_:))
        rootStack.addArrangedSubview(muteCheckbox)

        contentView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor)
        ])
    }

    private func makeHeaderLabel(text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        label.textColor = NSColor.secondaryLabelColor
        return label
    }

    private func makeSeparator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 340).isActive = true
        return box
    }

    private func makeLabelAndControlRow(label: String, control: NSView) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 340).isActive = true

        let lbl = NSTextField(labelWithString: label)
        lbl.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        lbl.widthAnchor.constraint(equalToConstant: 120).isActive = true

        row.addArrangedSubview(lbl)
        row.addArrangedSubview(control)
        return row
    }

    private func makeSliderRow(label: String, slider: NSSlider, valueLabel: NSTextField?) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 340).isActive = true

        let lbl = NSTextField(labelWithString: label)
        lbl.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        lbl.widthAnchor.constraint(equalToConstant: 120).isActive = true
        row.addArrangedSubview(lbl)

        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: 150).isActive = true
        row.addArrangedSubview(slider)

        if let vLabel = valueLabel {
            vLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            vLabel.textColor = .secondaryLabelColor
            vLabel.widthAnchor.constraint(equalToConstant: 50).isActive = true
            row.addArrangedSubview(vLabel)
        }

        return row
    }

    func syncWithCurrentSettings() {
        let cm = ColorProfileManager.shared

        presetPopup.selectItem(withTitle: cm.currentPreset.rawValue)

        sharpnessSlider.floatValue = cm.sharpness
        sharpnessLabel.stringValue = String(format: "%.0f%%", cm.sharpness * 100)

        brightnessSlider.floatValue = cm.brightness
        brightnessLabel.stringValue = String(format: "%+.0f%%", cm.brightness * 100)

        contrastSlider.floatValue = cm.contrast
        contrastLabel.stringValue = String(format: "%.0f%%", cm.contrast * 100)

        saturationSlider.floatValue = cm.saturation
        saturationLabel.stringValue = String(format: "%.0f%%", cm.saturation * 100)

        gammaSlider.floatValue = cm.gamma
        gammaLabel.stringValue = String(format: "%.2f", cm.gamma)

        // Quality Preset
        switch captureController.activePreset {
        case .hd1920x1080: qualityPopup.selectItem(at: 0)
        case .high: qualityPopup.selectItem(at: 1)
        case .hd1280x720: qualityPopup.selectItem(at: 2)
        default: qualityPopup.selectItem(at: 0)
        }

        // Scaling Mode
        if let gravity = mirrorVC?.previewView.previewLayer.videoGravity {
            switch gravity {
            case .resizeAspect: scalingPopup.selectItem(at: 0)
            case .resize: scalingPopup.selectItem(at: 1)
            case .resizeAspectFill: scalingPopup.selectItem(at: 2)
            default: break
            }
        }

        // Live Metrics
        let res = captureController.currentResolution
        let fps = captureController.currentFPS
        let fpsStr = fps > 0 ? "\(Int(round(fps))) FPS" : "60 FPS"
        let resStr = res.width > 0 ? "\(Int(res.width))x\(Int(res.height))" : "1920x1080"
        liveStatsLabel.stringValue = "Stream Metrics: \(resStr) @ \(fpsStr) (Direct 60 FPS)"

        // Audio
        volumeSlider.floatValue = captureController.audioVolume
        muteCheckbox.state = captureController.isAudioMuted ? .on : .off
    }

    // MARK: - Actions

    @objc private func presetChanged(_ sender: NSPopUpButton) {
        guard let title = sender.titleOfSelectedItem,
              let preset = ColorPreset(rawValue: title) else { return }
        ColorProfileManager.shared.selectPreset(preset)
        syncWithCurrentSettings()
    }

    @objc private func sharpnessChanged(_ sender: NSSlider) {
        ColorProfileManager.shared.currentPreset = .custom
        ColorProfileManager.shared.sharpness = sender.floatValue
        presetPopup.selectItem(withTitle: ColorPreset.custom.rawValue)
        sharpnessLabel.stringValue = String(format: "%.0f%%", sender.floatValue * 100)
    }

    @objc private func brightnessChanged(_ sender: NSSlider) {
        ColorProfileManager.shared.currentPreset = .custom
        ColorProfileManager.shared.brightness = sender.floatValue
        presetPopup.selectItem(withTitle: ColorPreset.custom.rawValue)
        brightnessLabel.stringValue = String(format: "%+.0f%%", sender.floatValue * 100)
    }

    @objc private func contrastChanged(_ sender: NSSlider) {
        ColorProfileManager.shared.currentPreset = .custom
        ColorProfileManager.shared.contrast = sender.floatValue
        presetPopup.selectItem(withTitle: ColorPreset.custom.rawValue)
        contrastLabel.stringValue = String(format: "%.0f%%", sender.floatValue * 100)
    }

    @objc private func saturationChanged(_ sender: NSSlider) {
        ColorProfileManager.shared.currentPreset = .custom
        ColorProfileManager.shared.saturation = sender.floatValue
        presetPopup.selectItem(withTitle: ColorPreset.custom.rawValue)
        saturationLabel.stringValue = String(format: "%.0f%%", sender.floatValue * 100)
    }

    @objc private func gammaChanged(_ sender: NSSlider) {
        ColorProfileManager.shared.currentPreset = .custom
        ColorProfileManager.shared.gamma = sender.floatValue
        presetPopup.selectItem(withTitle: ColorPreset.custom.rawValue)
        gammaLabel.stringValue = String(format: "%.2f", sender.floatValue)
    }

    @objc private func resetToCalibratedAction() {
        ColorProfileManager.shared.selectPreset(.calibratedStudio)
        syncWithCurrentSettings()
    }

    @objc private func nativeNonStretchedAction() {
        guard let mvc = mirrorVC else { return }
        (mvc.view.window?.windowController as? MirrorWindowController)?.setNativeNonStretched()
        syncWithCurrentSettings()
    }

    @objc private func macStretchAction() {
        guard let mvc = mirrorVC else { return }
        (mvc.view.window?.windowController as? MirrorWindowController)?.setStretchMacBookRetina()
        syncWithCurrentSettings()
    }

    @objc private func wideStretchAction() {
        guard let mvc = mirrorVC else { return }
        (mvc.view.window?.windowController as? MirrorWindowController)?.setStretchWidescreen16x9()
        syncWithCurrentSettings()
    }

    @objc private func qualityChanged(_ sender: NSPopUpButton) {
        switch sender.indexOfSelectedItem {
        case 0: captureController.setQualityPreset(.hd1920x1080)
        case 1: captureController.setQualityPreset(.high)
        case 2: captureController.setQualityPreset(.hd1280x720)
        default: break
        }
    }

    @objc private func scalingChanged(_ sender: NSPopUpButton) {
        guard let mvc = mirrorVC else { return }
        switch sender.indexOfSelectedItem {
        case 0:
            mvc.setVideoGravity(.resizeAspect)
        case 1:
            mvc.setVideoGravity(.resize)
        case 2:
            mvc.setVideoGravity(.resizeAspectFill)
        default: break
        }
    }

    @objc private func volumeChanged(_ sender: NSSlider) {
        captureController.audioVolume = sender.floatValue
        captureController.isAudioMuted = false
        muteCheckbox.state = .off
    }

    @objc private func muteToggled(_ sender: NSButton) {
        captureController.isAudioMuted = (sender.state == .on)
    }
}
