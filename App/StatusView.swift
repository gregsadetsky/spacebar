import SwiftUI
import SpacebarKit

struct StatusView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section("Quick Look extension") {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle().fill(color).frame(width: 9, height: 9)
                        Text(model.status.label)
                    }
                }
                HStack {
                    if model.status != .enabled {
                        Button("Enable…") { model.enableExtension() }
                    }
                    Button("Open System Settings") { NSWorkspace.shared.open(ExtensionStatus.settingsURL) }
                    Button("Reset Quick Look") { model.resetQuickLook() }
                    Button("Refresh") { model.refresh() }
                }
                Text("If the extension is disabled, turn it on under System Settings → General → Login Items & Extensions → Quick Look. Then press space on a .geojson or .sqlite3 file in Finder.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Troubleshooting") {
                Text("Every preview writes one line to the system log:")
                    .font(.callout).foregroundStyle(.secondary)
                Text("/usr/bin/log show --info --predicate 'subsystem == \"io.spacebar\"' --last 5m")
                    .font(.system(.callout, design: .monospaced)).textSelection(.enabled)
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
