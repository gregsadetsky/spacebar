// draws the app icon (a spacebar key with a tiny preview card on it) at every
// size iconutil wants, writes App/icon/AppIcon.icns. run: make icon
import AppKit

func draw(_ size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let s = size
    let ctx = NSGraphicsContext.current!.cgContext
    // background: rounded squircle-ish, dark slate
    let bg = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: s, height: s), xRadius: s * 0.225, yRadius: s * 0.225)
    let gradient = NSGradient(colors: [NSColor(calibratedRed: 0.17, green: 0.20, blue: 0.27, alpha: 1), NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.14, alpha: 1)])!
    gradient.draw(in: bg, angle: -90)
    // the key cap
    let capRect = NSRect(x: s * 0.12, y: s * 0.16, width: s * 0.76, height: s * 0.30)
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.015), blur: s * 0.04, color: NSColor.black.withAlphaComponent(0.6).cgColor)
    let cap = NSBezierPath(roundedRect: capRect, xRadius: s * 0.06, yRadius: s * 0.06)
    NSColor(calibratedWhite: 0.93, alpha: 1).setFill()
    cap.fill()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    let capTop = NSBezierPath(roundedRect: capRect.insetBy(dx: s * 0.02, dy: s * 0.03).offsetBy(dx: 0, dy: s * 0.015), xRadius: s * 0.045, yRadius: s * 0.045)
    NSColor(calibratedWhite: 0.99, alpha: 1).setFill()
    capTop.fill()
    // the preview card popping up from the key
    let card = NSRect(x: s * 0.26, y: s * 0.50, width: s * 0.48, height: s * 0.34)
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.05, color: NSColor.black.withAlphaComponent(0.5).cgColor)
    let cardPath = NSBezierPath(roundedRect: card, xRadius: s * 0.04, yRadius: s * 0.04)
    NSColor(calibratedRed: 0.04, green: 0.42, blue: 1.0, alpha: 1).setFill()
    cardPath.fill()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    // a few "map" dots and a line on the card
    NSColor.white.withAlphaComponent(0.95).setFill()
    let dots: [(CGFloat, CGFloat, CGFloat)] = [(0.35, 0.70, 0.030), (0.47, 0.76, 0.024), (0.58, 0.64, 0.034), (0.66, 0.74, 0.022), (0.41, 0.58, 0.022)]
    for (x, y, r) in dots {
        NSBezierPath(ovalIn: NSRect(x: s * x - s * r, y: s * y - s * r, width: s * r * 2, height: s * r * 2)).fill()
    }
    let line = NSBezierPath()
    line.move(to: NSPoint(x: s * 0.35, y: s * 0.70)); line.line(to: NSPoint(x: s * 0.47, y: s * 0.76)); line.line(to: NSPoint(x: s * 0.58, y: s * 0.64)); line.line(to: NSPoint(x: s * 0.66, y: s * 0.74))
    line.lineWidth = s * 0.018; line.lineCapStyle = .round; line.lineJoinStyle = .round
    NSColor.white.withAlphaComponent(0.8).setStroke(); line.stroke()
    img.unlockFocus()
    return img
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = out.deletingLastPathComponent().appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for (name, px) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    let img = draw(CGFloat(px))
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent("\(name).png"))
}
let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil"); p.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try! p.run(); p.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(p.terminationStatus == 0 ? "wrote \(out.path)" : "iconutil failed")
