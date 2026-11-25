import AppKit
import SwiftUI

// MARK: SVG path → SwiftUI Path

/// Minimal SVG path-data reader (M L H V C S A Z, absolute and relative; arcs must be circular).
enum SVGPath {
    static func path(_ data: String) -> Path {
        var path = Path()
        let chars = Array(data)
        var index = 0
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastControl: CGPoint?
        var command: Character = "M"

        func skipSeparators() {
            while index < chars.count, chars[index] == " " || chars[index] == "," || chars[index] == "\n" { index += 1 }
        }
        func hasNumber() -> Bool {
            skipSeparators()
            guard index < chars.count else { return false }
            let c = chars[index]
            return c.isNumber || c == "-" || c == "." || c == "+"
        }
        func number() -> CGFloat {
            skipSeparators()
            var text = ""
            var seenDot = false
            if index < chars.count, chars[index] == "-" || chars[index] == "+" { text.append(chars[index]); index += 1 }
            while index < chars.count {
                let c = chars[index]
                if c.isNumber { text.append(c) } else if c == ".", !seenDot { seenDot = true; text.append(c) } else { break }
                index += 1
            }
            return CGFloat(Double(text) ?? 0)
        }
        func flag() -> Bool {
            skipSeparators()
            guard index < chars.count else { return false }
            let value = chars[index] == "1"
            index += 1
            return value
        }
        func point(relative: Bool) -> CGPoint {
            let x = number(), y = number()
            return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }

        while index < chars.count {
            skipSeparators()
            guard index < chars.count else { break }
            if chars[index].isLetter {
                command = chars[index]
                index += 1
            }
            let relative = command.isLowercase
            switch command.uppercased() {
            case "M":
                current = point(relative: relative)
                start = current
                path.move(to: current)
                command = relative ? "l" : "L"
                lastControl = nil
            case "L":
                current = point(relative: relative)
                path.addLine(to: current)
                lastControl = nil
            case "H":
                let x = number()
                current.x = relative ? current.x + x : x
                path.addLine(to: current)
                lastControl = nil
            case "V":
                let y = number()
                current.y = relative ? current.y + y : y
                path.addLine(to: current)
                lastControl = nil
            case "C":
                let c1 = point(relative: relative), c2 = point(relative: relative), end = point(relative: relative)
                path.addCurve(to: end, control1: c1, control2: c2)
                lastControl = c2
                current = end
            case "S":
                let c2 = point(relative: relative), end = point(relative: relative)
                let c1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                path.addCurve(to: end, control1: c1, control2: c2)
                lastControl = c2
                current = end
            case "A":
                let rx = number()
                _ = number()
                _ = number()
                let large = flag(), sweep = flag()
                let end = point(relative: relative)
                addArc(to: &path, from: current, to: end, radius: rx, large: large, sweep: sweep)
                current = end
                lastControl = nil
            case "Z":
                path.closeSubpath()
                current = start
                lastControl = nil
            default:
                index += 1
            }
            // Never stall on something unexpected: step past it.
            skipSeparators()
            if index < chars.count, !chars[index].isLetter, command.uppercased() == "Z" || !hasNumber() { index += 1 }
        }
        return path
    }

    private static func addArc(to path: inout Path, from p0: CGPoint, to p1: CGPoint, radius: CGFloat, large: Bool, sweep: Bool) {
        let hx = (p0.x - p1.x) / 2, hy = (p0.y - p1.y) / 2
        let half = hx * hx + hy * hy
        guard half > 0 else { return }
        let r = max(radius, half.squareRoot())
        let coefficient = (large != sweep ? 1 : -1) * (max(0, r * r - half) / half).squareRoot()
        let center = CGPoint(x: coefficient * hy + (p0.x + p1.x) / 2, y: -coefficient * hx + (p0.y + p1.y) / 2)
        let startAngle = Angle(radians: atan2(p0.y - center.y, p0.x - center.x))
        let endAngle = Angle(radians: atan2(p1.y - center.y, p1.x - center.x))
        path.addArc(center: center, radius: r, startAngle: startAngle, endAngle: endAngle, clockwise: !sweep)
    }
}

/// The GitHub mark, drawn from its path so it scales and tints like an SF Symbol.
struct GitHubMark: Shape {
    private static let base = SVGPath.path("M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0 0 16 8c0-4.42-3.58-8-8-8z")

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 16
        let transform = CGAffineTransform(translationX: rect.midX - 8 * scale, y: rect.midY - 8 * scale).scaledBy(x: scale, y: scale)
        return Self.base.applying(transform)
    }
}

/// Icon-only shortcut to a GitHub page.
struct GitHubButton: View {
    var url: URL
    var size: CGFloat = 16
    @State private var hovering = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            GitHubMark()
                .fill(hovering ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                .frame(width: size, height: size)
                .padding(4)
                .contentShape(Rectangle())
                .scaleEffect(hovering ? 1.12 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.snappy, value: hovering)
        .help("GitHub · " + (url.host ?? "") + url.path)
        .accessibilityLabel("GitHub")
    }
}

/// Version on one line, developer + GitHub shortcut under it (or side by side when `compact`).
struct CreditFooter: View {
    var compact = false

    var body: some View {
        if compact {
            HStack(spacing: 6) {
                Text("\(AppInfo.name) v\(AppInfo.version)").monospacedDigit()
                Text("·").foregroundStyle(.tertiary)
                Text("Developed by \(AppInfo.developer)")
                GitHubButton(url: AppInfo.developerURL, size: 13)
            }
            .font(.app(11))
            .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 3) {
                Text("v\(AppInfo.version)")
                    .font(.app(11, .medium)).monospacedDigit()
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text("Developed by \(AppInfo.developer)")
                        .font(.app(11))
                        .foregroundStyle(.secondary)
                    GitHubButton(url: AppInfo.developerURL, size: 14)
                }
            }
        }
    }
}

/// App mark, matching the app icon: an ivory tile with two nodes joined by a coral-to-amber tether.
/// It keeps its own colours in every theme so the app is recognisable wherever it appears.
struct TetherLogo: View {
    var size: CGFloat = 64

    static let coral = Color(hex: "FF4F6E")
    static let amber = Color(hex: "FF9A2E")

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
        let tether = LinearGradient(colors: [Self.coral, Self.amber], startPoint: .bottomLeading, endPoint: .topTrailing)
        ZStack {
            shape.fill(LinearGradient(colors: [Color(hex: "FFFAF0"), Color(hex: "F1E3CC")], startPoint: .topLeading, endPoint: .bottomTrailing))
            shape.fill(RadialGradient(colors: [Color(hex: "FFB86B").opacity(0.45), .clear], center: .bottomTrailing,
                                      startRadius: 0, endRadius: size * 0.8))
            shape.fill(LinearGradient(colors: [.white.opacity(0.55), .clear], startPoint: .top, endPoint: .center))
            TetherGlyph()
                .stroke(tether, style: StrokeStyle(lineWidth: size * 0.065, lineCap: .round))
                .padding(size * 0.24)
            GeometryReader { geo in
                let inset = size * 0.24, d = size * 0.17
                Circle().fill(Self.coral).frame(width: d, height: d)
                    .position(x: inset, y: geo.size.height - inset)
                Circle().fill(Self.amber).frame(width: d, height: d)
                    .position(x: geo.size.width - inset, y: inset)
            }
            shape.strokeBorder(.black.opacity(0.10), lineWidth: 1)
        }
        .frame(width: size, height: size)
        .shadow(color: Color(hex: "FF7A4D").opacity(0.30), radius: size * 0.18, y: size * 0.08)
        .accessibilityHidden(true)
    }
}

struct TetherGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                      control1: CGPoint(x: rect.minX + rect.width * 0.75, y: rect.maxY),
                      control2: CGPoint(x: rect.minX + rect.width * 0.25, y: rect.minY))
        return path
    }
}

// MARK: Buttons

/// Borderless icon button with a soft hover plate.
struct IconButton: View {
    var symbol: String
    var size: CGFloat = 13
    var side: CGFloat = 28
    var active = false
    var tint: Color? = nil
    var help: String = ""
    var action: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(active ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(tint ?? .primary.opacity(0.82)))
                .frame(width: side, height: side)
                .background(
                    RoundedRectangle(cornerRadius: side * 0.3, style: .continuous)
                        .fill(active ? Theme.accent.opacity(0.16) : (hovering ? Theme.hoverFill(scheme) : .clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.35)
        .onHover { hovering = $0 }
        .animation(Motion.snappy, value: hovering)
        .animation(Motion.snappy, value: active)
        .help(help)
        .accessibilityLabel(help)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.app(13, .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .frame(minHeight: 34)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.82)], startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 1))
            .shadow(color: Theme.accent.opacity(configuration.isPressed ? 0.1 : 0.3), radius: 8, y: 3)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(enabled ? 1 : 0.45)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

struct SoftButtonStyle: ButtonStyle {
    var tint: Color? = nil
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.app(12, .medium))
            .foregroundStyle(tint ?? .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.chipFill(scheme)))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

// MARK: Inputs

/// Rounded input with an optional leading symbol; lights up in the accent colour when focused.
struct GlassField: View {
    var symbol: String? = nil
    var placeholder: String
    @Binding var text: String
    var secure = false
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 9) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(focused ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                    .frame(width: 18)
            }
            Group {
                if secure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(.app(13))
            .focused($focused)
            .onSubmit(onSubmit)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.fieldFill(scheme)))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(focused ? Theme.accent.opacity(0.7) : Theme.cardStroke(scheme), lineWidth: focused ? 1.5 : 1)
        )
        .animation(Motion.snappy, value: focused)
    }
}

/// Segmented control whose selection slides between options.
struct SlidingPicker<Value: Hashable>: View {
    var options: [(value: Value, label: String, symbol: String?)]
    @Binding var selection: Value
    @Namespace private var namespace
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let selected = option.value == selection
                Button {
                    withAnimation(Motion.snappy) { selection = option.value }
                } label: {
                    HStack(spacing: 5) {
                        if let symbol = option.symbol { Image(systemName: symbol).font(.system(size: 11, weight: .medium)) }
                        if !option.label.isEmpty { Text(option.label).font(.app(12, selected ? .semibold : .regular)) }
                    }
                    .foregroundStyle(selected ? .primary : .secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(scheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.95))
                                .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
                                .matchedGeometryEffect(id: "selection", in: namespace)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.chipFill(scheme)))
    }
}

/// Small rounded label.
struct Chip: View {
    var text: String
    var symbol: String? = nil
    var tint: Color? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .semibold)) }
            Text(text).font(.app(11, .medium)).lineLimit(1)
        }
        .foregroundStyle(tint ?? .secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill((tint ?? .primary).opacity(tint == nil ? (scheme == .dark ? 0.10 : 0.06) : 0.14)))
    }
}

/// Square icon tile used for Spaces.
struct SpaceBadge: View {
    var symbol: String
    var color: Color
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(LinearGradient(colors: [color, color.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).strokeBorder(.white.opacity(0.22), lineWidth: 1))
    }
}

/// Round tile with an account's initial.
struct AccountAvatar: View {
    var name: String
    var size: CGFloat = 36
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(name.trimmingCharacters(in: .whitespaces).prefix(1).uppercased())
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(.primary.opacity(0.85))
            .frame(width: size, height: size)
            .background(Circle().fill(Theme.chipFill(scheme)))
            .overlay(Circle().strokeBorder(Theme.cardStroke(scheme).opacity(1.8), lineWidth: 1))
    }
}

// MARK: Modifiers

private struct HoverLift: ViewModifier {
    var scale: CGFloat
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? scale : 1)
            .onHover { hovering = $0 }
            .animation(Motion.snappy, value: hovering)
    }
}

extension View {
    /// Grows slightly under the pointer.
    func hoverLift(_ scale: CGFloat = 1.03) -> some View { modifier(HoverLift(scale: scale)) }
}

/// Lets the user drag the window from an otherwise empty strip of the interface.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                window?.zoom(nil)
            } else {
                window?.performDrag(with: event)
            }
        }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct SectionLabel: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.app(11, .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .kerning(0.4)
    }
}

/// SF Symbols a Space or node can wear.
enum SymbolSets {
    static let space = ["sparkles", "graduationcap.fill", "person.fill", "house.fill", "briefcase.fill", "hammer.fill",
                        "chevron.left.forwardslash.chevron.right", "film.fill", "paintbrush.pointed.fill", "music.note",
                        "book.fill", "heart.fill", "leaf.fill", "gamecontroller.fill", "camera.fill", "globe.asia.australia.fill",
                        "dumbbell.fill", "lightbulb.fill"]
    static let node = ["doc.text", "note.text", "list.bullet", "lightbulb", "person.2", "chart.bar", "calendar", "book",
                       "star", "flag", "bookmark", "brain", "target", "checklist", "folder", "pencil.and.outline"]
}
