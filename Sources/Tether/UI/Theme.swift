import AppKit
import SwiftUI

extension Color {
    /// A colour that resolves differently in light and dark appearances.
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    init(hex: String) {
        self.init(nsColor: NSColor(hex: hex) ?? .labelColor)
    }
}

extension NSColor {
    /// Parses RRGGBB or RRGGBBAA (leading # optional).
    convenience init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6 || text.count == 8, let value = UInt64(text, radix: 16) else { return nil }
        let hasAlpha = text.count == 8
        let r = CGFloat((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let g = CGFloat((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let b = CGFloat((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let a = hasAlpha ? CGFloat(value & 0xFF) / 255 : 1
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }

    static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
}

/// Selectable colour themes. Each one supplies an accent (tuned per appearance so it stays
/// readable) and the colours of the soft light behind the glass.
enum Skin: String, CaseIterable, Identifiable {
    case aurora, jarvis, midnight, sage, sunset, rose, graphite

    var id: String { rawValue }

    @MainActor var title: String {
        switch self {
        case .aurora: return L("Aurora", "오로라")
        case .jarvis: return "JARVIS"
        case .midnight: return L("Midnight", "미드나이트")
        case .sage: return L("Sage", "세이지")
        case .sunset: return L("Sunset", "선셋")
        case .rose: return L("Rose", "로즈")
        case .graphite: return L("Graphite", "그래파이트")
        }
    }

    var accent: Color {
        switch self {
        case .aurora: return .dynamic(light: .rgb(0.29, 0.36, 0.95), dark: .rgb(0.53, 0.60, 1.0))
        case .jarvis: return .dynamic(light: .rgb(0.0, 0.52, 0.72), dark: .rgb(0.235, 0.863, 1.0))
        case .midnight: return .dynamic(light: .rgb(0.36, 0.33, 0.86), dark: .rgb(0.60, 0.58, 1.0))
        case .sage: return .dynamic(light: .rgb(0.12, 0.52, 0.34), dark: .rgb(0.36, 0.80, 0.56))
        case .sunset: return .dynamic(light: .rgb(0.88, 0.36, 0.18), dark: .rgb(1.0, 0.58, 0.40))
        case .rose: return .dynamic(light: .rgb(0.84, 0.22, 0.48), dark: .rgb(1.0, 0.50, 0.70))
        case .graphite: return .dynamic(light: .rgb(0.30, 0.33, 0.38), dark: .rgb(0.74, 0.77, 0.82))
        }
    }

    /// Three lights that drift behind the interface.
    var glow: [Color] {
        switch self {
        case .aurora: return [Color(hex: "5B6CFF"), Color(hex: "B15CFF"), Color(hex: "27C7C0")]
        case .jarvis: return [Color(hex: "1FB6FF"), Color(hex: "1E5BFF"), Color(hex: "3CF0E0")]
        case .midnight: return [Color(hex: "6E63FF"), Color(hex: "3B2F8F"), Color(hex: "4F7BFF")]
        case .sage: return [Color(hex: "3FB37F"), Color(hex: "9BD97A"), Color(hex: "2AA6A0")]
        case .sunset: return [Color(hex: "FF7A4D"), Color(hex: "FF4D8D"), Color(hex: "FFB347")]
        case .rose: return [Color(hex: "FF5C9A"), Color(hex: "C86BFF"), Color(hex: "FF9A8B")]
        case .graphite: return [Color(hex: "8A93A6"), Color(hex: "5C6475"), Color(hex: "A7B0C0")]
        }
    }
}

/// Shared surface colours. The card / chip / hover fills are the ATFM glass recipe:
/// translucent white over blur with a hairline edge.
@MainActor
enum Theme {
    static let cardRadius: CGFloat = 14
    static let controlRadius: CGFloat = 9

    static var accent: Color { AppSettings.shared.skin.accent }

    static func cardFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.58)
    }

    static func cardStroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
    }

    static func hoverFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05)
    }

    static func chipFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
    }

    /// The writing surface: more opaque than a card so long text stays easy to read.
    static func pageFill(_ scheme: ColorScheme) -> Color {
        let clarity = AppSettings.shared.glassClarity
        return scheme == .dark
            ? Color(white: 0.11).opacity(0.86 - 0.26 * clarity)
            : Color.white.opacity(0.92 - 0.22 * clarity)
    }

    /// Inserted objects sit *in* the page: a faint inset tone rather than a raised box.
    static func embedFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.045) : Color.black.opacity(0.028)
    }

    static func fieldFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.22) : Color.white.opacity(0.72)
    }

    /// Colours a Space can be tagged with.
    static let spaceColors: [Color] = [
        Color(hex: "5B6CFF"), Color(hex: "2A9DF4"), Color(hex: "18B5A4"), Color(hex: "34B36B"),
        Color(hex: "E6A417"), Color(hex: "F2733B"), Color(hex: "E8507E"), Color(hex: "A565F0"),
    ]

    static func spaceColor(_ index: Int) -> Color {
        spaceColors[((index % spaceColors.count) + spaceColors.count) % spaceColors.count]
    }

    /// Eight-slot categorical chart palette, validated for colour-vision deficiency in both
    /// appearances. Slots are assigned in order and never recycled by rank.
    static let chartPalette: [Color] = [
        .dynamic(light: NSColor(hex: "2A78D6")!, dark: NSColor(hex: "3987E5")!),
        .dynamic(light: NSColor(hex: "EB6834")!, dark: NSColor(hex: "D95926")!),
        .dynamic(light: NSColor(hex: "1BAF7A")!, dark: NSColor(hex: "199E70")!),
        .dynamic(light: NSColor(hex: "EDA100")!, dark: NSColor(hex: "C98500")!),
        .dynamic(light: NSColor(hex: "E87BA4")!, dark: NSColor(hex: "D55181")!),
        .dynamic(light: NSColor(hex: "008300")!, dark: NSColor(hex: "0CA30C")!),
        .dynamic(light: NSColor(hex: "6250D6")!, dark: NSColor(hex: "9085E9")!),
        .dynamic(light: NSColor(hex: "E34948")!, dark: NSColor(hex: "E66767")!),
    ]

    static func chartColor(_ slot: Int) -> Color {
        chartPalette[((slot % chartPalette.count) + chartPalette.count) % chartPalette.count]
    }

    static let positive = Color.dynamic(light: NSColor(hex: "0C8A0C")!, dark: NSColor(hex: "3FC25A")!)
    static let negative = Color.dynamic(light: NSColor(hex: "D03A3A")!, dark: NSColor(hex: "F07070")!)
}

// MARK: Surfaces

struct CardBackground: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var radius: CGFloat
    var fill: Color?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(shape.fill(fill ?? Theme.cardFill(scheme)))
            .overlay(shape.strokeBorder(Theme.cardStroke(scheme), lineWidth: 1).allowsHitTesting(false))
    }
}

/// Liquid Glass on macOS 26, a blur material with a hairline edge on earlier systems.
/// `frost` lays a translucent veil over the glass for surfaces that float above text,
/// so what scrolls underneath never competes with what is on top.
struct GlassSurface<S: InsettableShape>: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var shape: S
    var tint: Color?
    var frost: Double = 0

    private var veil: Color {
        (scheme == .dark ? Color(white: 0.13) : Color.white).opacity(frost)
    }

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .background(shape.fill(veil))
                .glassEffect(tint.map { Glass.regular.tint($0) } ?? Glass.regular, in: shape)
        } else {
            content
                .background(shape.fill(veil))
                .background(shape.fill(.ultraThinMaterial))
                .background(shape.fill(tint ?? .clear))
                .overlay(shape.strokeBorder(Theme.cardStroke(scheme), lineWidth: 1).allowsHitTesting(false))
                .shadow(color: .black.opacity(scheme == .dark ? 0.28 : 0.10), radius: 12, y: 4)
        }
    }
}

extension View {
    func card(radius: CGFloat = 14, fill: Color? = nil) -> some View {
        modifier(CardBackground(radius: radius, fill: fill))
    }

    func glass(radius: CGFloat = 16, tint: Color? = nil, frost: Double = 0) -> some View {
        modifier(GlassSurface(shape: RoundedRectangle(cornerRadius: radius, style: .continuous), tint: tint, frost: frost))
    }

    func glassCapsule(tint: Color? = nil) -> some View {
        modifier(GlassSurface(shape: Capsule(), tint: tint))
    }
}

// MARK: Backdrop

/// Desktop blur behind the whole window.
struct WindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// Blurred desktop + a wash for legibility + three slow lights in the theme colours.
/// Everything glassy in the app refracts this layer.
struct Backdrop: View {
    var spaceColor: Color? = nil
    @Environment(\.colorScheme) private var scheme
    @State private var drift = false

    var body: some View {
        let settings = AppSettings.shared
        let clarity = settings.glassClarity
        var colors = settings.skin.glow
        if let spaceColor { colors[1] = spaceColor }
        let strength = scheme == .dark ? 0.34 : 0.30
        return GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height, side = max(w, h)
            ZStack {
                WindowBlur()
                (scheme == .dark ? Color(white: 0.06) : Color(white: 0.97))
                    .opacity(scheme == .dark ? 0.88 - 0.38 * clarity : 0.86 - 0.36 * clarity)
                glow(colors[0], size: side * 0.95)
                    .position(x: w * (drift ? 0.22 : 0.10), y: h * (drift ? 0.12 : 0.24))
                glow(colors[1], size: side * 0.85)
                    .position(x: w * (drift ? 0.84 : 0.96), y: h * (drift ? 0.30 : 0.14))
                glow(colors[2], size: side * 0.90)
                    .position(x: w * (drift ? 0.58 : 0.44), y: h * (drift ? 0.98 : 0.90))
            }
            .compositingGroup()
            .environment(\.glowStrength, strength)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: settings.skin)
        .onAppear { startDrift() }
        .onChange(of: settings.ambientMotion) { _, _ in startDrift() }
    }

    private func glow(_ color: Color, size: CGFloat) -> some View {
        GlowBlob(color: color).frame(width: size, height: size)
    }

    private func startDrift() {
        let on = AppSettings.shared.ambientMotion && Motion.enabled
        if on {
            withAnimation(.easeInOut(duration: 16).repeatForever(autoreverses: true)) { drift = true }
        } else {
            withAnimation(.easeOut(duration: 0.4)) { drift = false }
        }
    }
}

private struct GlowStrengthKey: EnvironmentKey {
    static let defaultValue = 0.3
}

extension EnvironmentValues {
    var glowStrength: Double {
        get { self[GlowStrengthKey.self] }
        set { self[GlowStrengthKey.self] = newValue }
    }
}

private struct GlowBlob: View {
    var color: Color
    @Environment(\.glowStrength) private var strength

    var body: some View {
        GeometryReader { geo in
            Ellipse().fill(
                RadialGradient(colors: [color.opacity(strength), color.opacity(strength * 0.45), color.opacity(0)],
                               center: .center, startRadius: 0, endRadius: min(geo.size.width, geo.size.height) / 2)
            )
        }
        .allowsHitTesting(false)
    }
}
