import Foundation

/// picks the plugin for a file. exact uti match beats extension match; within
/// a tier the enabled plugin with the highest priority wins; ties go to the
/// first id alphabetically and produce a warning.
public enum Matcher {
    public struct Result: Equatable, Sendable {
        public let plugin: InstalledPlugin?
        public let warning: String?
    }

    public static func pick(from plugins: [InstalledPlugin], ext: String, uti: String?) -> Result {
        let ext = ext.lowercased()
        let enabled = plugins.filter(\.enabled)
        let byUTI = uti.map { u in enabled.filter { $0.manifest.matches.utis.contains(u) } } ?? []
        let byExt = enabled.filter { !ext.isEmpty && $0.manifest.matches.extensions.contains(ext) }
        let tier = byUTI.isEmpty ? byExt : byUTI
        guard !tier.isEmpty else { return Result(plugin: nil, warning: nil) }
        let sorted = tier.sorted {
            if $0.manifest.priority != $1.manifest.priority { return $0.manifest.priority > $1.manifest.priority }
            return $0.manifest.id < $1.manifest.id
        }
        let winner = sorted[0]
        var warning: String?
        if sorted.count > 1, sorted[1].manifest.priority == winner.manifest.priority {
            let ids = sorted.filter { $0.manifest.priority == winner.manifest.priority }.map(\.manifest.id)
            warning = "plugins \(ids.joined(separator: ", ")) all match .\(ext) with priority \(winner.manifest.priority); using \(winner.manifest.id)"
        }
        return Result(plugin: winner, warning: warning)
    }
}
