// renders an svg at 1024x1024 over a background colour with WebKit (the only renderer here
// that draws the icon correctly; librsvg drops the keycap). used by scripts/svg-to-icns.sh.
// usage: svg-render <svg path> <css background> <out.png>
import AppKit
import WebKit
let args = CommandLine.arguments
let svg = URL(fileURLWithPath: args[1]), bg = args[2], out = args[3]
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1024, height: 1024), styleMask: [.borderless], backing: .buffered, defer: false)
let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 1024))
window.contentView!.addSubview(web)
window.orderFront(nil)
let html = "<!doctype html><html><body style='margin:0;background:\(bg)'><img src='\(svg.lastPathComponent)' width='1024' height='1024' style='display:block'></body></html>"
let htmlURL = svg.deletingLastPathComponent().appendingPathComponent("_svgshot.html")
try! html.write(to: htmlURL, atomically: true, encoding: .utf8)
web.loadFileURL(htmlURL, allowingReadAccessTo: svg.deletingLastPathComponent())
DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
    let cfg = WKSnapshotConfiguration()
    cfg.snapshotWidth = 1024
    web.takeSnapshot(with: cfg) { image, _ in
        if let image, let t = image.tiffRepresentation, let r = NSBitmapImageRep(data: t), let png = r.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: out)); print("wrote \(out) \(Int(image.size.width))x\(Int(image.size.height))")
        }
        try? FileManager.default.removeItem(at: htmlURL)
        exit(0)
    }
}
app.run()
