// Generates AppIcon.icns: a warm ivory tile with two nodes joined by a coral-to-amber tether.
// Usage: make-icon <output.icns>
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func render(px: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high
    let cg = ctx.cgContext

    let s = CGFloat(px)
    let inset = s * 0.09
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.225
    let body = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    // Soft drop shadow so the light tile holds its edge on a light Dock.
    NSGraphicsContext.saveGraphicsState()
    let drop = NSShadow()
    drop.shadowColor = NSColor.black.withAlphaComponent(0.20)
    drop.shadowBlurRadius = s * 0.035
    drop.shadowOffset = NSSize(width: 0, height: -s * 0.014)
    drop.set()
    color(0xFFFAF0).setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Base: ivory, warming towards the lower right, with a glass sheen across the top.
    NSGradient(colors: [color(0xFFFAF0), color(0xF1E3CC)])!.draw(in: body, angle: -55)
    NSGraphicsContext.saveGraphicsState()
    body.addClip()
    let corner = NSPoint(x: rect.maxX - rect.width * 0.1, y: rect.minY + rect.height * 0.05)
    NSGradient(colors: [color(0xFFB86B, 0.45), color(0xFFB86B, 0)])!
        .draw(fromCenter: corner, radius: 0, toCenter: corner, radius: rect.width * 0.75, options: [])
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.55), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // The tether: an S-curve from the lower-left node to the upper-right node, coral → amber.
    let a = NSPoint(x: rect.minX + rect.width * 0.27, y: rect.minY + rect.height * 0.27)
    let b = NSPoint(x: rect.maxX - rect.width * 0.27, y: rect.maxY - rect.height * 0.27)
    let span = b.x - a.x
    let curve = NSBezierPath()
    curve.move(to: a)
    curve.curve(to: b, controlPoint1: NSPoint(x: a.x + span * 0.78, y: a.y), controlPoint2: NSPoint(x: a.x + span * 0.22, y: b.y))
    let lineWidth = rect.width * 0.062
    let d = rect.width * 0.165
    let pieces = [
        curve.cgPath.copy(strokingWithWidth: lineWidth, lineCap: .round, lineJoin: .round, miterLimit: 10),
        CGPath(ellipseIn: CGRect(x: a.x - d / 2, y: a.y - d / 2, width: d, height: d), transform: nil),
        CGPath(ellipseIn: CGRect(x: b.x - d / 2, y: b.y - d / 2, width: d, height: d), transform: nil),
    ]
    NSGraphicsContext.saveGraphicsState()
    let glyphShadow = NSShadow()
    glyphShadow.shadowColor = color(0xC2410C, 0.22)
    glyphShadow.shadowBlurRadius = rect.width * 0.03
    glyphShadow.shadowOffset = NSSize(width: 0, height: -rect.width * 0.012)
    glyphShadow.set()
    cg.beginTransparencyLayer(auxiliaryInfo: nil)
    // One clip per piece: overlapping subpaths in a single clip would cancel out where they cross.
    for piece in pieces {
        cg.saveGState()
        cg.addPath(piece)
        cg.clip()
        NSGradient(colors: [color(0xFF4F6E), color(0xFF9A2E)])!
            .draw(from: a, to: b, options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation])
        cg.restoreGState()
    }
    cg.endTransparencyLayer()
    NSGraphicsContext.restoreGraphicsState()

    // Hairline rim.
    NSColor.black.withAlphaComponent(0.10).setStroke()
    let rim = NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.004, dy: s * 0.004), xRadius: radius, yRadius: radius)
    rim.lineWidth = max(1, s * 0.006)
    rim.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("Tether-AppIcon.iconset")
try? FileManager.default.removeItem(at: tmp)
try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(px: base).write(to: tmp.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(px: base * 2).write(to: tmp.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", tmp.path, "-o", output]
try! task.run()
task.waitUntilExit()
try? FileManager.default.removeItem(at: tmp)
print(task.terminationStatus == 0 ? "wrote \(output)" : "iconutil failed")
exit(task.terminationStatus)
