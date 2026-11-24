import AppKit
import SwiftUI
import Observation

enum AppLanguage: String, CaseIterable, Identifiable {
    case en, ko
    var id: String { rawValue }
    var title: String { self == .ko ? "한국어" : "English" }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
}

enum LineSpacingChoice: String, CaseIterable, Identifiable {
    case compact, normal, relaxed
    var id: String { rawValue }
    var points: CGFloat {
        switch self {
        case .compact: return 2
        case .normal: return 5
        case .relaxed: return 9
        }
    }
}

enum ContentWidthChoice: String, CaseIterable, Identifiable {
    case narrow, regular, wide
    var id: String { rawValue }
    var points: CGFloat {
        switch self {
        case .narrow: return 620
        case .regular: return 760
        case .wide: return 940
        }
    }
}

/// Typefaces offered for the interface and the editor. All ship with macOS.
enum FontChoice: String, CaseIterable, Identifiable {
    case system, rounded, serif, gothicNeo, avenir, helvetica, charter, mono

    var id: String { rawValue }

    /// Faces that work for interface text (monospace is editor-only).
    static let interface: [FontChoice] = [.system, .rounded, .serif, .gothicNeo, .avenir, .helvetica, .charter]

    var title: String {
        switch self {
        case .system: return "SF Pro"
        case .rounded: return "SF Rounded"
        case .serif: return "New York"
        case .gothicNeo: return "Apple SD Gothic Neo"
        case .avenir: return "Avenir Next"
        case .helvetica: return "Helvetica Neue"
        case .charter: return "Charter"
        case .mono: return "SF Mono"
        }
    }

    private var family: String? {
        switch self {
        case .gothicNeo: return "Apple SD Gothic Neo"
        case .avenir: return "Avenir Next"
        case .helvetica: return "Helvetica Neue"
        case .charter: return "Charter"
        default: return nil
        }
    }

    func nsFont(size: CGFloat, bold: Bool = false) -> NSFont {
        let weight: NSFont.Weight = bold ? .bold : .regular
        switch self {
        case .system:
            return .systemFont(ofSize: size, weight: weight)
        case .rounded, .serif:
            let base = NSFont.systemFont(ofSize: size, weight: weight)
            let design: NSFontDescriptor.SystemDesign = self == .rounded ? .rounded : .serif
            if let descriptor = base.fontDescriptor.withDesign(design), let font = NSFont(descriptor: descriptor, size: size) {
                return font
            }
            return base
        case .mono:
            return .monospacedSystemFont(ofSize: size, weight: weight)
        default:
            let traits: NSFontTraitMask = bold ? .boldFontMask : []
            return NSFontManager.shared.font(withFamily: family ?? "", traits: traits, weight: bold ? 9 : 5, size: size)
                ?? .systemFont(ofSize: size, weight: weight)
        }
    }

    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch self {
        case .system: return .system(size: size, weight: weight)
        case .rounded: return .system(size: size, weight: weight, design: .rounded)
        case .serif: return .system(size: size, weight: weight, design: .serif)
        case .mono: return .system(size: size, weight: weight, design: .monospaced)
        default: return .custom(family ?? "", fixedSize: size).weight(weight)
        }
    }
}

/// App-wide preferences, persisted in UserDefaults. Demo/screenshot runs use their own suite
/// so they never disturb the real preferences.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    @ObservationIgnored private let defaults: UserDefaults

    var language: AppLanguage { didSet { defaults.set(language.rawValue, forKey: "language") } }
    var appearance: AppearanceMode { didSet { defaults.set(appearance.rawValue, forKey: "appearance"); applyAppearance() } }
    var skin: Skin { didSet { defaults.set(skin.rawValue, forKey: "skin") } }
    var uiFont: FontChoice { didSet { defaults.set(uiFont.rawValue, forKey: "uiFont") } }
    var editorFont: FontChoice { didSet { defaults.set(editorFont.rawValue, forKey: "editorFont") } }
    var editorFontSize: Double { didSet { defaults.set(editorFontSize, forKey: "editorFontSize") } }
    var lineSpacing: LineSpacingChoice { didSet { defaults.set(lineSpacing.rawValue, forKey: "lineSpacing") } }
    var contentWidth: ContentWidthChoice { didSet { defaults.set(contentWidth.rawValue, forKey: "contentWidth") } }
    var spellCheck: Bool { didSet { defaults.set(spellCheck, forKey: "spellCheck") } }
    var animations: Bool { didSet { defaults.set(animations, forKey: "animations") } }
    /// 0 = solid surfaces, 1 = the most see-through glass.
    var glassClarity: Double { didSet { defaults.set(glassClarity, forKey: "glassClarity") } }
    var ambientMotion: Bool { didSet { defaults.set(ambientMotion, forKey: "ambientMotion") } }

    private init() {
        let env = ProcessInfo.processInfo.environment
        if env["TETHER_DATA_DIR"] != nil {
            let suite = "com.geonhee.tether.demo"
            UserDefaults.standard.removePersistentDomain(forName: suite)
            defaults = UserDefaults(suiteName: suite) ?? .standard
        } else {
            defaults = .standard
        }
        let d = defaults
        let systemKorean = Locale.preferredLanguages.first?.hasPrefix("ko") ?? false
        language = AppLanguage(rawValue: env["TETHER_LANG"] ?? d.string(forKey: "language") ?? "") ?? (systemKorean ? .ko : .en)
        appearance = AppearanceMode(rawValue: env["TETHER_APPEARANCE"] ?? d.string(forKey: "appearance") ?? "") ?? .system
        skin = Skin(rawValue: env["TETHER_SKIN"] ?? d.string(forKey: "skin") ?? "") ?? .aurora
        uiFont = FontChoice(rawValue: d.string(forKey: "uiFont") ?? "") ?? .system
        editorFont = FontChoice(rawValue: d.string(forKey: "editorFont") ?? "") ?? .system
        editorFontSize = d.object(forKey: "editorFontSize") as? Double ?? 15
        lineSpacing = LineSpacingChoice(rawValue: d.string(forKey: "lineSpacing") ?? "") ?? .normal
        contentWidth = ContentWidthChoice(rawValue: d.string(forKey: "contentWidth") ?? "") ?? .regular
        spellCheck = d.object(forKey: "spellCheck") as? Bool ?? false
        animations = d.object(forKey: "animations") as? Bool ?? true
        glassClarity = d.object(forKey: "glassClarity") as? Double ?? 0.6
        ambientMotion = d.object(forKey: "ambientMotion") as? Bool ?? true
    }

    func applyAppearance() {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    /// Changes whenever something that affects how saved text is laid out changes.
    var typographyStamp: String {
        "\(editorFont.rawValue)|\(editorFontSize)|\(lineSpacing.rawValue)"
    }
}

/// Picks the string for the current interface language.
@MainActor
func L(_ en: String, _ ko: String) -> String {
    AppSettings.shared.language == .ko ? ko : en
}

extension Font {
    /// Interface font in the user's chosen typeface.
    @MainActor
    static func app(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        AppSettings.shared.uiFont.font(size: size, weight: weight)
    }
}

/// Animation presets that collapse to "no animation" when the user turns motion off.
@MainActor
enum Motion {
    static var enabled: Bool {
        AppSettings.shared.animations && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    static var spring: Animation? { enabled ? .spring(response: 0.38, dampingFraction: 0.82) : nil }
    static var snappy: Animation? { enabled ? .spring(response: 0.26, dampingFraction: 0.86) : nil }
    static var smooth: Animation? { enabled ? .easeInOut(duration: 0.28) : nil }
    static var gentle: Animation? { enabled ? .easeOut(duration: 0.5) : nil }
}
