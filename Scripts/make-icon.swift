// Generates AppIcon.icns: a glass-like rounded square with two nodes joined by a tether.
// Usage: make-icon <output.icns>
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"

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

    let s = CGFloat(px)
    let inset = s * 0.09
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.225
    let body = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    // Base: indigo → violet, with a teal light rising from the lower right.
    NSGradient(colors: [
        NSColor(srgbRed: 0.36, green: 0.42, blue: 1.00, alpha: 1),
        NSColor(srgbRed: 0.62, green: 0.36, blue: 0.98, alpha: 1),
    ])!.draw(in: body, angle: -55)
    NSGraphicsContext.saveGraphicsState()
    body.addClip()
    NSGradient(colors: [
        NSColor(srgbRed: 0.15, green: 0.78, blue: 0.75, alpha: 0.85),
        NSColor(srgbRed: 0.15, green: 0.78, blue: 0.75, alpha: 0),
    ])!.draw(fromCenter: NSPoint(x: rect.maxX - rect.width * 0.1, y: rect.minY + rect.height * 0.05), radius: 0,
             toCenter: NSPoint(x: rect.maxX - rect.width * 0.1, y: rect.minY + rect.height * 0.05), radius: rect.width * 0.75, options: [])
    // Glass sheen across the top.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.34), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // The tether: an S-curve from the lower-left node to the upper-right node.
    let a = NSPoint(x: rect.minX + rect.width * 0.27, y: rect.minY + rect.height * 0.27)
    let b = NSPoint(x: rect.maxX - rect.width * 0.27, y: rect.maxY - rect.height * 0.27)
    let span = b.x - a.x
    let curve = NSBezierPath()
    curve.move(to: a)
    curve.curve(to: b, controlPoint1: NSPoint(x: a.x + span * 0.78, y: a.y), controlPoint2: NSPoint(x: a.x + span * 0.22, y: b.y))
    curve.lineWidth = rect.width * 0.062
    curve.lineCapStyle = .round
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowBlurRadius = rect.width * 0.03
    shadow.shadowOffset = NSSize(width: 0, height: -rect.width * 0.012)
    shadow.set()
    NSColor.white.setStroke()
    curve.stroke()
    NSColor.white.setFill()
    let d = rect.width * 0.165
    NSBezierPath(ovalIn: NSRect(x: a.x - d / 2, y: a.y - d / 2, width: d, height: d)).fill()
    NSBezierPath(ovalIn: NSRect(x: b.x - d / 2, y: b.y - d / 2, width: d, height: d)).fill()

    // Hairline rim.
    NSShadow().set()
    NSColor.white.withAlphaComponent(0.28).setStroke()
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
