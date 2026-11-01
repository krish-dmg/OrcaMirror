import Cocoa
import CoreImage

enum ColorPreset: String, CaseIterable {
    case calibratedStudio = "Studio Calibrated (Tamed Brightness)"
    case competitiveEsports = "Competitive E-Sports (High-Vis)"
    case amoledPunch = "AMOLED Punch (Deep Blacks)"
    case vibrantGaming = "Vibrant Gaming (Punchy)"
    case coolCompetitive = "Cool Competitive (Clarity)"
    case cinematicWarm = "Cinematic Warm (Cozy Stream)"
    case hdrEmulation = "HDR Emulation (Dynamic Pop)"
    case rawNative = "Raw Native (Passthrough)"
    case custom = "Custom"
}

final class ColorProfileManager {
    static let shared = ColorProfileManager()

    private let defaults = UserDefaults.standard

    var currentPreset: ColorPreset = .calibratedStudio {
        didSet {
            defaults.set(currentPreset.rawValue, forKey: "OrcaMirror_Preset")
            applyPresetValues(currentPreset)
            notifyChanged()
        }
    }

    var brightness: Float = -0.07 {
        didSet {
            defaults.set(brightness, forKey: "OrcaMirror_Brightness")
            notifyChanged()
        }
    }

    var contrast: Float = 1.08 {
        didSet {
            defaults.set(contrast, forKey: "OrcaMirror_Contrast")
            notifyChanged()
        }
    }

    var saturation: Float = 1.04 {
        didSet {
            defaults.set(saturation, forKey: "OrcaMirror_Saturation")
            notifyChanged()
        }
    }

    var gamma: Float = 0.92 {
        didSet {
            defaults.set(gamma, forKey: "OrcaMirror_Gamma")
            notifyChanged()
        }
    }

    var sharpness: Float = 0.20 {
        didSet {
            defaults.set(sharpness, forKey: "OrcaMirror_Sharpness")
            notifyChanged()
        }
    }

    var onProfileChanged: (() -> Void)?

    private init() {
        loadSavedValues()
    }

    private func loadSavedValues() {
        if let savedPresetStr = defaults.string(forKey: "OrcaMirror_Preset"),
           let savedPreset = ColorPreset(rawValue: savedPresetStr) {
            currentPreset = savedPreset
            if savedPreset == .custom {
                brightness = defaults.float(forKey: "OrcaMirror_Brightness")
                contrast = defaults.object(forKey: "OrcaMirror_Contrast") != nil ? defaults.float(forKey: "OrcaMirror_Contrast") : 1.0
                saturation = defaults.object(forKey: "OrcaMirror_Saturation") != nil ? defaults.float(forKey: "OrcaMirror_Saturation") : 1.0
                gamma = defaults.object(forKey: "OrcaMirror_Gamma") != nil ? defaults.float(forKey: "OrcaMirror_Gamma") : 1.0
                sharpness = defaults.object(forKey: "OrcaMirror_Sharpness") != nil ? defaults.float(forKey: "OrcaMirror_Sharpness") : 0.20
            } else {
                applyPresetValues(savedPreset)
            }
        } else {
            currentPreset = .calibratedStudio
            applyPresetValues(.calibratedStudio)
        }

        if defaults.object(forKey: "OrcaMirror_Sharpness") != nil {
            sharpness = defaults.float(forKey: "OrcaMirror_Sharpness")
        }
    }

    func selectPreset(_ preset: ColorPreset) {
        currentPreset = preset
    }

    private func applyPresetValues(_ preset: ColorPreset) {
        switch preset {
        case .calibratedStudio:
            brightness = -0.07
            contrast = 1.08
            saturation = 1.04
            gamma = 0.92
            sharpness = 0.20

        case .competitiveEsports:
            brightness = -0.02
            contrast = 1.18
            saturation = 1.15
            gamma = 0.85
            sharpness = 0.45

        case .amoledPunch:
            brightness = -0.06
            contrast = 1.26
            saturation = 1.28
            gamma = 0.94
            sharpness = 0.25

        case .vibrantGaming:
            brightness = -0.04
            contrast = 1.14
            saturation = 1.22
            gamma = 0.92
            sharpness = 0.30

        case .coolCompetitive:
            brightness = -0.03
            contrast = 1.12
            saturation = 1.08
            gamma = 0.90
            sharpness = 0.35

        case .cinematicWarm:
            brightness = -0.05
            contrast = 1.08
            saturation = 1.05
            gamma = 0.95
            sharpness = 0.15

        case .hdrEmulation:
            brightness = -0.04
            contrast = 1.22
            saturation = 1.18
            gamma = 0.88
            sharpness = 0.40

        case .rawNative:
            brightness = 0.0
            contrast = 1.0
            saturation = 1.0
            gamma = 1.0
            sharpness = 0.0

        case .custom:
            break
        }
    }

    func applyToLayer(_ layer: CALayer) {
        if currentPreset == .rawNative && brightness == 0.0 && contrast == 1.0 && saturation == 1.0 && gamma == 1.0 && sharpness == 0.0 {
            layer.filters = nil
            return
        }

        var filters: [CIFilter] = []

        if let colorControls = CIFilter(name: "CIColorControls") {
            colorControls.setDefaults()
            colorControls.setValue(brightness, forKey: kCIInputBrightnessKey)
            colorControls.setValue(contrast, forKey: kCIInputContrastKey)
            colorControls.setValue(saturation, forKey: kCIInputSaturationKey)
            filters.append(colorControls)
        }

        if let gammaAdjust = CIFilter(name: "CIGammaAdjust") {
            gammaAdjust.setDefaults()
            gammaAdjust.setValue(gamma, forKey: "inputPower")
            filters.append(gammaAdjust)
        }

        if sharpness > 0.01, let sharpen = CIFilter(name: "CISharpenLuminance") {
            sharpen.setDefaults()
            sharpen.setValue(sharpness, forKey: "inputSharpness")
            filters.append(sharpen)
        }

        layer.filters = filters
    }

    private func notifyChanged() {
        onProfileChanged?()
    }
}
