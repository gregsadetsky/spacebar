import Foundation

public enum PluginSource: String, Codable, Sendable { case bundled, user }

public struct InstalledPlugin: Equatable, Sendable {
    public let manifest: Manifest
    public let directory: URL
    public let source: PluginSource
    public var enabled: Bool

    public init(manifest: Manifest, directory: URL, source: PluginSource, enabled: Bool) {
        self.manifest = manifest; self.directory = directory; self.source = source; self.enabled = enabled
    }

    public var entryURL: URL { directory.appendingPathComponent(manifest.entry) }
}

/// the set of plugins found in a plugins directory. built by scanning
/// `<pluginsDir>/<id>/plugin.json`; disabled ids come from `disabled.json`
/// next to it (`["id", ...]`). broken plugins land in `warnings`, never throw.
public struct PluginIndex: Sendable {
    public let plugins: [InstalledPlugin]
    public let warnings: [String]

    public init(plugins: [InstalledPlugin], warnings: [String] = []) {
        self.plugins = plugins; self.warnings = warnings
    }

    public static func scan(pluginsDir: URL, disabled: Set<String>) -> PluginIndex {
        var plugins: [InstalledPlugin] = []
        var warnings: [String] = []
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: pluginsDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return PluginIndex(plugins: [], warnings: ["plugins directory not readable: \(pluginsDir.path)"])
        }
        for dir in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            do {
                let m = try Manifest.load(fromDirectory: dir)
                if m.id != dir.lastPathComponent {
                    warnings.append("\(dir.lastPathComponent): folder name does not match id \"\(m.id)\", skipped")
                    continue
                }
                let source: PluginSource = fm.fileExists(atPath: dir.appendingPathComponent(".bundled").path) ? .bundled : .user
                plugins.append(InstalledPlugin(manifest: m, directory: dir, source: source, enabled: !disabled.contains(m.id)))
            } catch {
                warnings.append("\(dir.lastPathComponent): \(error)")
            }
        }
        return PluginIndex(plugins: plugins, warnings: warnings)
    }

    /// scan the standard location (Paths.pluginsDir + Paths.disabledFile)
    public static func scanDefault() -> PluginIndex {
        scan(pluginsDir: Paths.pluginsDir, disabled: readDisabled(from: Paths.disabledFile))
    }

    public static func readDisabled(from url: URL) -> Set<String> {
        guard let data = FileManager.default.contents(atPath: url.path),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(ids)
    }

    public static func writeDisabled(_ ids: Set<String>, to url: URL) throws {
        let data = try JSONEncoder().encode(ids.sorted())
        try data.write(to: url, options: .atomic)
    }

    public func pick(ext: String, uti: String?) -> Matcher.Result {
        Matcher.pick(from: plugins, ext: ext, uti: uti)
    }
}
