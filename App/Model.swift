import SwiftUI
import SpacebarKit

/// everything the windows show, refreshed from disk on demand
@MainActor
final class AppModel: ObservableObject {
    @Published var plugins: [InstalledPlugin] = []
    @Published var warnings: [String] = []
    @Published var status: ExtensionStatus = .unknown("not checked yet")
    @Published var lastError: String?

    func refresh() {
        let index = PluginIndex.scanDefault()
        plugins = index.plugins
        warnings = index.warnings
        status = ExtensionStatus.query()
    }

    func setEnabled(_ id: String, _ enabled: Bool) {
        do { try PluginIndex.setEnabled(id, enabled, disabledFile: Paths.disabledFile) }
        catch { lastError = "\(error)" }
        refresh()
    }

    func installFromFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a plugin folder (it needs a plugin.json)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { _ = try PluginInstaller.installUserPlugin(from: url, to: Paths.pluginsDir) }
        catch { lastError = "\(error)" }
        refresh()
    }

    func remove(_ id: String) {
        do { try PluginInstaller.remove(id: id, from: Paths.pluginsDir) }
        catch { lastError = "\(error)" }
        refresh()
    }

    func openPluginsFolder() {
        try? Paths.ensureDirectories()
        NSWorkspace.shared.open(Paths.pluginsDir)
    }

    func enableExtension() {
        _ = ExtensionStatus.enable()
        refresh()
        if status != .enabled { NSWorkspace.shared.open(ExtensionStatus.settingsURL) }
    }

    func resetQuickLook() { ExtensionStatus.resetQuickLook() }
}
