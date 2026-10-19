import Foundation

/// copies plugin folders into the plugins directory.
public enum PluginInstaller {
    public enum InstallError: Error, CustomStringConvertible {
        case invalid(ManifestError)
        case alreadyInstalled(String)
        case copyFailed(String)

        public var description: String {
            switch self {
            case .invalid(let e): return e.description
            case .alreadyInstalled(let id): return "a plugin with id \"\(id)\" is already installed"
            case .copyFailed(let m): return "copy failed: \(m)"
            }
        }
    }

    /// name of the marker file inside a plugin folder that says "shipped with the app"
    public static let bundledMarker = ".bundled"

    /// sync every plugin under `bundleDir` (the app's Resources/Plugins) into
    /// `pluginsDir`. a bundled plugin overwrites the installed copy when its
    /// version is newer or when the installed copy is also bundled; a
    /// user-installed plugin with the same id is never touched.
    /// returns the ids that were (re)installed.
    @discardableResult
    public static func syncBundled(from bundleDir: URL, to pluginsDir: URL) throws -> [String] {
        let fm = FileManager.default
        try fm.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
        var installed: [String] = []
        let sources = (try? fm.contentsOfDirectory(at: bundleDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        for src in sources.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let manifest = try? Manifest.load(fromDirectory: src), manifest.id == src.lastPathComponent else { continue }
            let dest = pluginsDir.appendingPathComponent(manifest.id, isDirectory: true)
            if fm.fileExists(atPath: dest.path) {
                let existingIsBundled = fm.fileExists(atPath: dest.appendingPathComponent(bundledMarker).path)
                let existing = try? Manifest.load(fromDirectory: dest)
                let newer = existing.map { !Manifest.version($0.version, isAtLeast: manifest.version) } ?? true
                guard existingIsBundled && (newer || existing == nil || existing?.version == manifest.version) else { continue }
                // same version + bundled: still refresh so edits to the shipped plugin land (dev loop)
                try fm.removeItem(at: dest)
            }
            do { try fm.copyItem(at: src, to: dest) } catch { throw InstallError.copyFailed(error.localizedDescription) }
            fm.createFile(atPath: dest.appendingPathComponent(bundledMarker).path, contents: Data())
            installed.append(manifest.id)
        }
        return installed
    }

    /// install a user-chosen folder. validates first; refuses to replace an existing id.
    @discardableResult
    public static func installUserPlugin(from src: URL, to pluginsDir: URL) throws -> Manifest {
        let manifest: Manifest
        do { manifest = try Manifest.load(fromDirectory: src) } catch let e as ManifestError { throw InstallError.invalid(e) }
        let fm = FileManager.default
        try fm.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
        let dest = pluginsDir.appendingPathComponent(manifest.id, isDirectory: true)
        if fm.fileExists(atPath: dest.path) { throw InstallError.alreadyInstalled(manifest.id) }
        do { try fm.copyItem(at: src, to: dest) } catch { throw InstallError.copyFailed(error.localizedDescription) }
        try? fm.removeItem(at: dest.appendingPathComponent(bundledMarker))
        return manifest
    }

    public static func remove(id: String, from pluginsDir: URL) throws {
        try FileManager.default.removeItem(at: pluginsDir.appendingPathComponent(id, isDirectory: true))
    }
}
