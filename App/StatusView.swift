import SwiftUI
import SpacebarKit

struct StatusView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                switch model.status {
                case .enabled:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Installed and working!").font(.title2.weight(.semibold))
                        Text("Press space on \(extensionsSentence) in Finder.").font(.title3)
                    }
                    .padding(.vertical, 6)
                case .disabled:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("One more step").font(.title2.weight(.semibold))
                        Text("macOS keeps new Quick Look extensions switched off. Turn Spacebar on in System Settings → General → Login Items & Extensions → Quick Look, then come back here and press Refresh.")
                        HStack {
                            Button("Enable Extension") { model.enableExtension() }
                                .help("Tries to switch it on from here; opens System Settings if macOS refuses.")
                            Button("Open System Settings") { NSWorkspace.shared.open(ExtensionStatus.settingsURL) }
                                .help("Opens the Quick Look extensions pane where the Spacebar switch is.")
                            Button("Refresh") { model.refresh() }
                                .help("Checks again whether the extension is switched on.")
                        }
                    }
                    .padding(.vertical, 6)
                case .notRegistered, .unknown:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Not registered with macOS").font(.title2.weight(.semibold))
                        Text("macOS has not picked up the Quick Look extension (\(model.status.label)). This usually fixes itself a few seconds after the app is in /Applications and has been opened once. If it stays this way, reinstall Spacebar.")
                        HStack {
                            Button("Refresh") { model.refresh() }
                                .help("Checks again whether macOS has registered the extension.")
                            Button("Open System Settings") { NSWorkspace.shared.open(ExtensionStatus.settingsURL) }
                                .help("The Quick Look extensions pane; Spacebar should be listed there once registered.")
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Seeing a stale or wrong preview after changing or installing a plugin? Finder caches previews.")
                        .foregroundStyle(.secondary)
                    Text("The button below restarts the Quick Look server and clears that cache; the next space press renders fresh.")
                        .foregroundStyle(.secondary)
                    Button("Reset Quick Look") { model.resetQuickLook() }
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
    }

    /// one representative extension per enabled plugin: ".zip, .epub, … or .srt file"
    var extensionsSentence: String {
        var shown: [String] = []
        for p in model.plugins where p.enabled {
            if let e = p.manifest.matches.extensions.first, !shown.contains("." + e) { shown.append("." + e) }
        }
        guard !shown.isEmpty else { return "a file" }
        let more = shown.count > 9 ? " (and more)" : ""
        let list = Array(shown.prefix(9))
        if list.count == 1 { return "a \(list[0]) file\(more)" }
        return "a " + list.dropLast().joined(separator: ", ") + " or " + list.last! + " file" + more
    }
}
