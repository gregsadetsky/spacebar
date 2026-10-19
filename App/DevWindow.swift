import SwiftUI
import SpacebarKit

/// pick a plugin and a file, render with the real PreviewWebView, read the
/// plugin's console output. how plugin authors iterate without finder.
struct DevWindow: View {
    @EnvironmentObject var model: AppModel
    @State private var pluginID: String = ""
    @State private var fileURL: URL?
    @State private var renderID = 0
    @State private var logLines: [String] = []
    @State private var outcome = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Plugin", selection: $pluginID) {
                    Text("auto").tag("")
                    ForEach(model.plugins) { Text("\($0.manifest.name) (\($0.manifest.id))").tag($0.manifest.id) }
                }.frame(maxWidth: 260)
                Button("Choose File…") { chooseFile() }
                Text(fileURL?.lastPathComponent ?? "no file").foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Text(outcome).font(.callout).foregroundStyle(outcome.hasPrefix("done") ? .green : .orange)
                Button("Reload") { reload() }.keyboardShortcut("r").disabled(fileURL == nil)
            }
            .padding(8)
            Divider()
            HSplitView {
                PreviewHost(file: fileURL, pluginID: pluginID, renderID: renderID, plugins: model.plugins,
                            onLog: { logLines.append($0) },
                            onFinish: { outcome = $0 })
                    .frame(minWidth: 300)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(logLines.enumerated()), id: \.offset) { Text($0.element) }
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .textSelection(.enabled)
                }
                .frame(minWidth: 180, idealWidth: 260)
            }
        }
        .frame(minWidth: 700, minHeight: 400)
        .onAppear { model.refresh() }
    }

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        fileURL = url
        reload()
    }

    func reload() {
        logLines = []
        outcome = "…"
        model.refresh()
        renderID += 1
    }
}

struct PreviewHost: NSViewRepresentable {
    let file: URL?
    let pluginID: String
    let renderID: Int
    let plugins: [InstalledPlugin]
    let onLog: (String) -> Void
    let onFinish: (String) -> Void

    func makeNSView(context: Context) -> PreviewWebView {
        let v = PreviewWebView(frame: .zero)
        v.onLog = { message in DispatchQueue.main.async { onLog(message) } }
        v.onFinish = { outcome in DispatchQueue.main.async { onFinish(outcome.label) } }
        return v
    }

    func updateNSView(_ view: PreviewWebView, context: Context) {
        guard context.coordinator.lastRender != renderID, let file else { return }
        context.coordinator.lastRender = renderID
        let info = FileInfo(url: file)
        let plugin = pluginID.isEmpty
            ? Matcher.pick(from: plugins, ext: info.ext, uti: info.uti).plugin
            : plugins.first { $0.manifest.id == pluginID }
        guard let plugin else { onFinish("no plugin matches \(info.name)"); return }
        onLog("rendering \(info.name) with \(plugin.manifest.id) \(plugin.manifest.version) (\(plugin.source.rawValue))")
        view.onLog = { message in DispatchQueue.main.async { onLog(message) } }
        view.onFinish = { outcome in DispatchQueue.main.async { onFinish(outcome.label) } }
        view.render(file: info, plugin: plugin)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var lastRender = -1 }
}
