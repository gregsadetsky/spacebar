import SwiftUI
import SpacebarKit

@main
struct SpacebarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()

    init() {
        do {
            try Paths.ensureDirectories()
            let bundled = Bundle.main.resourceURL!.appendingPathComponent("Plugins", isDirectory: true)
            let synced = try PluginInstaller.syncBundled(from: bundled, to: Paths.pluginsDir)
            NSLog("spacebar: synced bundled plugins \(synced)")
        } catch {
            NSLog("spacebar: plugin sync failed: \(error)")
        }
    }

    var body: some Scene {
        Window("Spacebar", id: "main") {
            TabView {
                StatusView().tabItem { Text("Status") }
                PluginsView().tabItem { Text("Plugins") }
            }
            .frame(minWidth: 640, minHeight: 380)
            .environmentObject(model)
            .onAppear { model.refresh() }
        }
        .defaultSize(width: 720, height: 440)

        Window("Dev Harness", id: "dev") {
            DevWindow().environmentObject(model)
        }
        .defaultSize(width: 1000, height: 640)
        .commands {
            CommandGroup(after: .windowArrangement) {
                OpenDevWindowButton()
            }
        }
    }
}

struct OpenDevWindowButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Dev Harness") { openWindow(id: "dev") }.keyboardShortcut("d", modifiers: [.command, .shift])
    }
}

/// `Spacebar --dev <file> [--plugin id] [--snapshot out.png] [--theme dark|light]`: headless-ish
/// render used by scripts/smoke.sh and for screenshots without finder
final class AppDelegate: NSObject, NSApplicationDelegate {
    var devWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--dev"), i + 1 < args.count else { return }
        let file = FileInfo(url: URL(fileURLWithPath: args[i + 1]))
        let index = PluginIndex.scanDefault()
        var plugin: InstalledPlugin?
        if let p = args.firstIndex(of: "--plugin"), p + 1 < args.count {
            plugin = index.plugins.first { $0.manifest.id == args[p + 1] }
        } else {
            plugin = index.pick(ext: file.ext, uti: file.uti).plugin
        }
        guard let plugin else { NSLog("spacebar dev: no plugin for \(file.name)"); NSApp.terminate(nil); return }
        let snapshot = args.firstIndex(of: "--snapshot").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        if let t = args.firstIndex(of: "--theme"), t + 1 < args.count {
            NSApp.appearance = NSAppearance(named: args[t + 1] == "dark" ? .darkAqua : .aqua)
        }

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "dev: \(plugin.manifest.id) · \(file.name)"
        let preview = PreviewWebView(frame: window.contentView!.bounds)
        preview.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(preview)
        preview.onLog = { NSLog("spacebar dev [\(plugin.manifest.id)] \($0)") }
        preview.onFinish = { outcome in
            NSLog("spacebar dev: plugin=\(plugin.manifest.id) outcome=\(outcome.label)")
            guard let snapshot else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard let web = preview.webView, outcome.isSuccess else {
                    NSLog("spacebar dev: no webview to snapshot"); NSApp.terminate(nil); return
                }
                web.takeSnapshot(with: nil) { image, error in
                    if let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: snapshot))
                        NSLog("spacebar dev: wrote \(snapshot)")
                    } else {
                        NSLog("spacebar dev: snapshot failed \(String(describing: error))")
                    }
                    NSApp.terminate(nil)
                }
            }
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        devWindow = window
        preview.render(file: file, plugin: plugin)
    }
}
