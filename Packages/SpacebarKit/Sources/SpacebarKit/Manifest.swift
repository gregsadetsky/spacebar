import Foundation

public enum InputKind: String, Codable, CaseIterable, Sendable {
    case text, bytes, json, plist, sqlite, archive, epub
}

public enum ManifestError: Error, Equatable, CustomStringConvertible {
    case fileMissing(String)
    case invalidJSON(String)
    case missingField(String)
    case badInput(String)
    case badVersion(String)
    case badID(String)
    case noMatches
    case entryMissing(String)

    public var description: String {
        switch self {
        case .fileMissing(let p): return "plugin.json not found at \(p)"
        case .invalidJSON(let m): return "plugin.json is not valid JSON: \(m)"
        case .missingField(let f): return "plugin.json is missing \"\(f)\""
        case .badInput(let v): return "plugin.json \"input\" must be one of \(InputKind.allCases.map(\.rawValue).joined(separator: ", ")), got \"\(v)\""
        case .badVersion(let v): return "plugin.json \"version\" must be semver (x.y.z), got \"\(v)\""
        case .badID(let v): return "plugin.json \"id\" must match [a-z0-9][a-z0-9-]*, got \"\(v)\""
        case .noMatches: return "plugin.json \"matches\" needs at least one extension or uti"
        case .entryMissing(let e): return "entry file \"\(e)\" does not exist in the plugin folder"
        }
    }
}

/// `plugin.json`, validated. see PLUGINS.md for the contract.
public struct Manifest: Codable, Equatable, Sendable {
    public struct Matches: Codable, Equatable, Sendable {
        public var extensions: [String]
        public var utis: [String]

        public init(extensions: [String], utis: [String] = []) {
            self.extensions = extensions
            self.utis = utis
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            extensions = (try c.decodeIfPresent([String].self, forKey: .extensions) ?? [])
                .map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
                .filter { !$0.isEmpty }
            utis = try c.decodeIfPresent([String].self, forKey: .utis) ?? []
        }
    }

    public static let defaultMaxFileSize = 50 * 1024 * 1024

    public var id: String
    public var name: String
    public var version: String
    public var matches: Matches
    public var input: InputKind
    public var maxFileSize: Int
    public var entry: String
    public var requiresHost: String?
    public var priority: Int

    enum CodingKeys: String, CodingKey {
        case id, name, version, matches, input, maxFileSize, entry, requiresHost, priority
    }

    public init(id: String, name: String, version: String, matches: Matches, input: InputKind,
                maxFileSize: Int = Manifest.defaultMaxFileSize, entry: String = "index.html",
                requiresHost: String? = nil, priority: Int = 0) {
        self.id = id; self.name = name; self.version = version; self.matches = matches
        self.input = input; self.maxFileSize = maxFileSize; self.entry = entry
        self.requiresHost = requiresHost; self.priority = priority
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        version = try c.decode(String.self, forKey: .version)
        matches = try c.decode(Matches.self, forKey: .matches)
        let inputRaw = try c.decode(String.self, forKey: .input)
        guard let kind = InputKind(rawValue: inputRaw) else { throw ManifestError.badInput(inputRaw) }
        input = kind
        maxFileSize = try c.decodeIfPresent(Int.self, forKey: .maxFileSize) ?? Manifest.defaultMaxFileSize
        entry = try c.decodeIfPresent(String.self, forKey: .entry) ?? "index.html"
        requiresHost = try c.decodeIfPresent(String.self, forKey: .requiresHost)
        priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 0
    }

    /// parse + validate the json text of a plugin.json
    public static func parse(_ data: Data) throws -> Manifest {
        let manifest: Manifest
        do {
            manifest = try JSONDecoder().decode(Manifest.self, from: data)
        } catch let e as ManifestError {
            throw e
        } catch DecodingError.keyNotFound(let key, _) {
            throw ManifestError.missingField(key.stringValue)
        } catch DecodingError.dataCorrupted(let ctx) {
            throw ManifestError.invalidJSON(ctx.debugDescription)
        } catch DecodingError.typeMismatch(_, let ctx) {
            throw ManifestError.invalidJSON("wrong type at \(ctx.codingPath.map(\.stringValue).joined(separator: ".")): \(ctx.debugDescription)")
        } catch {
            throw ManifestError.invalidJSON(String(describing: error))
        }
        try manifest.validate()
        return manifest
    }

    /// load `<dir>/plugin.json` and check `entry` exists
    public static func load(fromDirectory dir: URL) throws -> Manifest {
        let file = dir.appendingPathComponent("plugin.json")
        guard let data = FileManager.default.contents(atPath: file.path) else {
            throw ManifestError.fileMissing(file.path)
        }
        let m = try parse(data)
        guard FileManager.default.fileExists(atPath: dir.appendingPathComponent(m.entry).path) else {
            throw ManifestError.entryMissing(m.entry)
        }
        return m
    }

    public func validate() throws {
        guard Manifest.isValidID(id) else { throw ManifestError.badID(id) }
        guard Manifest.isSemver(version) else { throw ManifestError.badVersion(version) }
        if let r = requiresHost, !Manifest.isSemver(r) { throw ManifestError.badVersion(r) }
        guard !matches.extensions.isEmpty || !matches.utis.isEmpty else { throw ManifestError.noMatches }
        guard !entry.isEmpty, !entry.hasPrefix("/"), !entry.contains("..") else { throw ManifestError.entryMissing(entry) }
    }

    public static func isSemver(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 3 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }

    public static func isValidID(_ s: String) -> Bool {
        guard let first = s.first, first.isLowercase || first.isNumber, first.isASCII else { return false }
        return s.allSatisfy { ($0.isASCII && ($0.isLowercase || $0.isNumber)) || $0 == "-" }
    }

    /// semver compare: returns true when `a >= b`
    public static func version(_ a: String, isAtLeast b: String) -> Bool {
        let pa = a.split(separator: ".").compactMap { Int($0) }
        let pb = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<3 {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return true
    }
}
