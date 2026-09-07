import UIKit

// Tokens del sistema de diseño (ver DESIGN.md). Un solo acento: negro.
enum ThemeMode: String {
    case light, sepia, dark
}

struct Palette {
    let bg: UIColor, text: UIColor, secondary: UIColor, hairline: UIColor
    let bgHex: String, textHex: String, secondaryHex: String, hairlineHex: String

    static func of(_ mode: ThemeMode) -> Palette {
        switch mode {
        case .light:
            return Palette(bg: hex(0xFFFFFF), text: hex(0x171717), secondary: hex(0x666666), hairline: hex(0xEBEBEB),
                           bgHex: "#ffffff", textHex: "#171717", secondaryHex: "#666666", hairlineHex: "#ebebeb")
        case .sepia:
            return Palette(bg: hex(0xF7F3EA), text: hex(0x2B2620), secondary: hex(0x6E6558), hairline: hex(0xE6DFD2),
                           bgHex: "#f7f3ea", textHex: "#2b2620", secondaryHex: "#6e6558", hairlineHex: "#e6dfd2")
        case .dark:
            return Palette(bg: hex(0x000000), text: hex(0xEDEDED), secondary: hex(0xA1A1A1), hairline: hex(0x2A2A2A),
                           bgHex: "#000000", textHex: "#ededed", secondaryHex: "#a1a1a1", hairlineHex: "#2a2a2a")
        }
    }

    private static func hex(_ v: UInt32) -> UIColor {
        return UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}

enum Fonts {
    // Figtree viene empaquetada (UIAppFonts). Si falla la carga, cae al sistema.
    static func ui(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "Figtree-Bold"
        case .semibold: name = "Figtree-SemiBold"
        case .medium: name = "Figtree-Medium"
        default: name = "Figtree-Regular"
        }
        return UIFont(name: name, size: size) ?? UIFont.systemFont(ofSize: size, weight: weight)
    }

    static func mono(_ size: CGFloat) -> UIFont {
        return UIFont(name: "Menlo-Regular", size: size) ?? UIFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
    }

    /// Figtree con numerales tabulares si la fuente los trae (feature 6/0 de SFNTLayoutTypes: number spacing / monospaced).
    static func tabular(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let base = ui(size, weight: weight)
        let feature: [UIFontDescriptor.FeatureKey: Int] = [.featureIdentifier: 6, .typeIdentifier: 0]
        let d = base.fontDescriptor.addingAttributes([.featureSettings: [feature]])
        return UIFont(descriptor: d, size: size)
    }

    /// Tracking 0.06 em para los textos en mayúsculas (ver DESIGN.md).
    static func tracked(_ label: UILabel, _ text: String) {
        let size = label.font?.pointSize ?? 12
        label.attributedText = NSAttributedString(string: text, attributes: [.kern: size * 0.06])
    }
}

// Preferencias del usuario. UserDefaults alcanza: son pocas y chicas.
final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard
    private init() {}

    var theme: ThemeMode {
        get { return ThemeMode(rawValue: d.string(forKey: "theme") ?? "") ?? .light }
        set { d.set(newValue.rawValue, forKey: "theme"); NotificationCenter.default.post(name: .themeChanged, object: nil) }
    }
    var palette: Palette { return Palette.of(theme) }

    /// Tamaño base del texto en px (el resto escala proporcional a Docs).
    var fontSize: Double {
        get { let v = d.double(forKey: "fontSize"); return v > 0 ? v : 19 }
        set { d.set(min(max(newValue, 14), 30), forKey: "fontSize"); Settings.postTypography() }
    }
    /// Interlineado (multiplicador). Docs usa 1.15; en pantalla 1.35 lee mejor.
    var lineHeight: Double {
        get { let v = d.double(forKey: "lineHeight"); return v > 0 ? v : 1.35 }
        set { d.set(min(max(newValue, 1.1), 1.9), forKey: "lineHeight"); Settings.postTypography() }
    }
    var preachFontSize: Double {
        get { let v = d.double(forKey: "preachFontSize"); return v > 0 ? v : 27 }
        set { d.set(min(max(newValue, 20), 40), forKey: "preachFontSize"); Settings.postTypography() }
    }
    private static func postTypography() {
        NotificationCenter.default.post(name: .typographyChanged, object: nil)
    }
    var pinEnabled: Bool {
        get { return d.object(forKey: "pinEnabled") == nil ? true : d.bool(forKey: "pinEnabled") }
        set { d.set(newValue, forKey: "pinEnabled") }
    }
    var touchIDEnabled: Bool {
        get { return d.object(forKey: "touchID") == nil ? true : d.bool(forKey: "touchID") }
        set { d.set(newValue, forKey: "touchID") }
    }
    /// Hash del PIN. Por defecto el mismo PIN que la PWA (224466).
    var pinHash: String {
        get { return d.string(forKey: "pinHash") ?? Pin.hash("224466") }
        set { d.set(newValue, forKey: "pinHash") }
    }
    var contentBaseURL: String {
        get { return d.string(forKey: "contentBaseURL") ?? "" }
        set { d.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "contentBaseURL") }
    }
    var lastSync: Date? {
        get { return d.object(forKey: "lastSync") as? Date }
        set { d.set(newValue, forKey: "lastSync") }
    }
    var lastOpenedDocID: String? {
        get { return d.string(forKey: "lastOpened") }
        set { d.set(newValue, forKey: "lastOpened") }
    }
}

extension Notification.Name {
    static let themeChanged = Notification.Name("lector.themeChanged")
    static let typographyChanged = Notification.Name("lector.typographyChanged")
    static let contentChanged = Notification.Name("lector.contentChanged")
}
