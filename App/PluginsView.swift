import SwiftUI
import SpacebarKit

struct PluginsView: View {
    @EnvironmentObject var model: AppModel
    @State private var selection: String?

    var body: some View {
        VStack(spacing: 0) {
            Table(model.plugins, selection: $selection) {
                TableColumn("On") { p in
                    Toggle("", isOn: Binding(get: { p.enabled }, set: { model.setEnabled(p.manifest.id, $0) }))
                        .labelsHidden()
                }.width(36)
                TableColumn("Name") { p in Text(p.manifest.name) }
                TableColumn("Id", value: \.manifest.id)
                TableColumn("Version", value: \.manifest.version).width(60)
                TableColumn("Extensions") { p in Text(p.manifest.matches.extensions.map { "." + $0 }.joined(separator: " ")) }
                TableColumn("Source") { p in Text(p.source.rawValue).foregroundStyle(.secondary) }.width(60)
            }
            if !model.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.warnings, id: \.self) { Text($0).font(.callout).foregroundStyle(.orange) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            HStack {
                Button("Install from Folder…") { model.installFromFolder() }
                Button("Open Plugins Folder") { model.openPluginsFolder() }
                Spacer()
                Button("Remove", role: .destructive) { if let id = selection { model.remove(id) } }
                    .disabled(selectedRemovable == nil)
                    .help("Bundled plugins come back on the next launch; disable them instead.")
            }
            .padding(10)
        }
        .onAppear { model.refresh() }
        .alert("Spacebar", isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })) {
            Button("OK") { model.lastError = nil }
        } message: { Text(model.lastError ?? "") }
    }

    var selectedRemovable: InstalledPlugin? {
        model.plugins.first { $0.manifest.id == selection && $0.source == .user }
    }
}

extension InstalledPlugin: Identifiable {
    public var id: String { manifest.id }
}
