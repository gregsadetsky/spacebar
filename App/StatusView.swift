import SwiftUI
import SpacebarKit

struct StatusView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                LabeledContent("Quick Look extension") {
                    HStack(spacing: 6) {
                        Circle().fill(color).frame(width: 9, height: 9)
                        Text(model.status.label)
                    }
                }
                if model.status == .enabled {
                    Text("Press space on a .plist, .geojson or .sqlite3 file in Finder.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Text("macOS keeps third-party Quick Look extensions off until you turn them on once: System Settings → General → Login Items & Extensions → Quick Look → Spacebar.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                HStack {
                    if model.status != .enabled {
                        Button("Enable Extension") { model.enableExtension() }
                            .help("Tries to enable it from here; if macOS refuses, opens the System Settings pane where you can flip the switch.")
                    }
                    Button("Open System Settings") { NSWorkspace.shared.open(ExtensionStatus.settingsURL) }
                        .help("The Quick Look extensions pane, where the Spacebar switch lives.")
                    Button("Refresh") { model.refresh() }
                        .help("Re-reads the extension state and the plugins folder. Use it after flipping the switch in System Settings.")
                }
            }
            Section {
                Button("Reset Quick Look") { model.resetQuickLook() }
                    .help("Restarts the Quick Look server and clears its thumbnail cache (qlmanage -r). Only needed if Finder keeps showing an old preview after you changed a plugin.")
                Text("Only needed if Finder keeps showing a stale preview after you changed or installed a plugin.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    var color: Color {
        switch model.status {
        case .enabled: return .green
        case .disabled: return .orange
        case .notRegistered, .unknown: return .red
        }
    }
}
