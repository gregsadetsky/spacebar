import AppKit
import QuickLookUI
import SpacebarKit
import os

let log = Logger(subsystem: Host.logSubsystem, category: "extension")

final class PreviewViewController: NSViewController, QLPreviewingController {
    private var preview: PreviewWebView?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    }

    /// the app copies bundled plugins into the container on launch, but the
    /// app may never have been launched (brew installs can't open it). so the
    /// extension does the same copy from its own bundle when needed. the
    /// plugins ship inside the appex because a sandboxed extension cannot read
    /// the parent app's resources.
    private static let bundledSync: Void = {
        guard let bundled = Bundle.main.resourceURL?.appendingPathComponent("Plugins", isDirectory: true) else { return }
        do {
            try Paths.ensureDirectories()
            let synced = try PluginInstaller.syncBundled(from: bundled, to: Paths.pluginsDir)
            if !synced.isEmpty { log.info("synced bundled plugins from the extension bundle: \(synced.joined(separator: ","), privacy: .public)") }
        } catch {
            log.error("bundled plugin sync failed: \(String(describing: error), privacy: .public)")
        }
    }()

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        let started = Date()
        _ = PreviewViewController.bundledSync
        let file = FileInfo(url: url)
        let index = PluginIndex.scanDefault()
        for w in index.warnings { log.warning("\(w, privacy: .public)") }
        let pick = index.pick(ext: file.ext, uti: file.uti)
        if let w = pick.warning { log.warning("\(w, privacy: .public)") }
        guard let plugin = pick.plugin else {
            let (fallback, kind) = FallbackView.make(for: file, frame: view.bounds)
            view.addSubview(fallback)
            log.info("no plugin for \(file.name, privacy: .public) (uti \(file.uti ?? "nil", privacy: .public)), \(index.plugins.count) plugins installed; built-in \(kind, privacy: .public) fallback")
            handler(nil)
            return
        }

        let preview = PreviewWebView(frame: view.bounds)
        preview.autoresizingMask = [.width, .height]
        view.addSubview(preview)
        self.preview = preview
        preview.onLog = { message in log.info("[\(plugin.manifest.id, privacy: .public)] \(message, privacy: .public)") }
        preview.onFinish = { outcome in
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            let line = "rendered plugin=\(plugin.manifest.id) ext=\(file.ext) size=\(file.size) elapsed=\(ms)ms outcome=\(outcome.label)"
            if outcome.isSuccess { log.info("\(line, privacy: .public)") } else { log.error("\(line, privacy: .public)") }
            handler(nil)
        }
        preview.render(file: file, plugin: plugin)
    }
}
