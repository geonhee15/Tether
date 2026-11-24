import SwiftUI

/// Keep-awake mode: the Mac and its display stay on, and the window shows nothing but the
/// Tether mark over slowly bending curves. Holding the mark for a second returns to the app.
struct AwakeView: View {
    let since: Date

    @Environment(AppUI.self) private var ui
    @Environment(\.colorScheme) private var scheme
    @State private var progress: CGFloat = 0
    @State private var breathing = false
    @State private var appeared = false

    private let holdSeconds = 1.0

    var body: some View {
        ZStack {
            // Fully opaque: whatever was on screen is hidden while the Mac sits unattended.
            scheme == .dark ? Color(hex: "121114") : Color(hex: "FFFAF0")
            WindowDragArea()

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !Motion.enabled)) { timeline in
                Canvas { context, size in
                    drawCurves(in: &context, size: size, time: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
            .allowsHitTesting(false)

            VStack(spacing: 26) {
                mark
                VStack(spacing: 6) {
                    Text(L("Keeping your Mac awake", "절전 방지 중"))
                        .font(.app(22, .bold))
                    TimelineView(.periodic(from: since, by: 1)) { timeline in
                        Text(elapsed(timeline.date.timeIntervalSince(since)) + "  ·  "
                             + L("the display and the Mac won't sleep", "화면과 Mac이 잠들지 않아요"))
                            .font(.app(13)).monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                VStack(spacing: 5) {
                    Label(L("Press and hold the icon for a second to return", "돌아가려면 아이콘을 1초간 길게 누르세요"),
                          systemImage: "hand.tap")
                        .font(.app(12.5, .medium))
                        .foregroundStyle(.secondary)
                    Text(L("or press ⇧⌘K", "또는 ⇧⌘K"))
                        .font(.app(11.5))
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 6)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(Motion.gentle) { appeared = true }
            if Motion.enabled {
                withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) { breathing = true }
            }
        }
    }

    /// The icon, wrapped in a ring that fills while it is held.
    private var mark: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(LinearGradient(colors: [TetherLogo.coral, TetherLogo.amber], startPoint: .bottomLeading, endPoint: .topTrailing),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            TetherLogo(size: 104)
                .scaleEffect(progress > 0 ? 0.94 : (breathing ? 1.03 : 1))
        }
        .frame(width: 164, height: 164)
        .contentShape(Circle())
        .onLongPressGesture(minimumDuration: holdSeconds, maximumDistance: 80) {
            ui.setAwake(false)
        } onPressingChanged: { pressing in
            withAnimation(pressing ? .linear(duration: holdSeconds) : .easeOut(duration: 0.25)) {
                progress = pressing ? 1 : 0
            }
        }
        .help(L("Press and hold to return", "길게 눌러 돌아가기"))
        .accessibilityLabel(L("Return to Tether", "Tether로 돌아가기"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { ui.setAwake(false) }
    }

    private func elapsed(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }

    /// Six tethers crossing the window, each an S-curve whose bend slowly changes, with a node
    /// gliding along it.
    private func drawCurves(in context: inout GraphicsContext, size: CGSize, time: Double) {
        let w = size.width, h = size.height
        let count = 6
        for index in 0..<count {
            let f = Double(index) / Double(count - 1)
            let phase = Double(index) * 1.7
            let start = CGPoint(x: -24, y: h * (0.16 + 0.68 * f) + sin(time * 0.21 + phase) * h * 0.05)
            let end = CGPoint(x: w + 24, y: h * (0.84 - 0.68 * f) + cos(time * 0.17 + phase * 0.6) * h * 0.05)
            let c1 = CGPoint(x: w * (0.30 + 0.07 * sin(time * 0.13 + phase)),
                             y: start.y + sin(time * 0.31 + phase) * h * 0.24)
            let c2 = CGPoint(x: w * (0.70 + 0.07 * cos(time * 0.11 + phase)),
                             y: end.y - cos(time * 0.27 + phase * 1.3) * h * 0.24)

            var path = Path()
            path.move(to: start)
            path.addCurve(to: end, control1: c1, control2: c2)
            let strength = 0.16 + 0.10 * (0.5 + 0.5 * sin(time * 0.19 + phase))
            let gradient = Gradient(colors: [TetherLogo.coral.opacity(strength), TetherLogo.amber.opacity(strength)])
            context.stroke(path, with: .linearGradient(gradient, startPoint: start, endPoint: end),
                           style: StrokeStyle(lineWidth: 1.4 + CGFloat(index % 3) * 0.9, lineCap: .round))

            // A node travelling along the tether.
            var u = (time * (0.018 + 0.006 * Double(index % 3)) + f * 0.61).truncatingRemainder(dividingBy: 1)
            if index % 2 == 1 { u = 1 - u }
            let point = cubic(start, c1, c2, end, at: u)
            let radius = 3.2 + CGFloat(index % 3)
            let fade = min(1, min(u, 1 - u) * 8)   // ease in and out at the window edges
            let dot = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            context.fill(dot, with: .color((index % 2 == 0 ? TetherLogo.coral : TetherLogo.amber).opacity(0.75 * fade)))
        }
    }

    private func cubic(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, at t: Double) -> CGPoint {
        let s = 1 - t
        let a = s * s * s, b = 3 * s * s * t, c = 3 * s * t * t, d = t * t * t
        return CGPoint(x: a * p0.x + b * p1.x + c * p2.x + d * p3.x, y: a * p0.y + b * p1.y + c * p2.y + d * p3.y)
    }
}
