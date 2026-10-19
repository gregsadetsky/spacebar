import Foundation

public enum InputError: Error, Equatable, CustomStringConvertible {
    case fileTooLarge(size: Int, limit: Int)
    case unreadable(String)
    case invalidJSON(String)
    case invalidPlist(String)
    case notSQLite
    case sqlite(String)
    case archive(String)
    case epub(String)

    public var description: String {
        switch self {
        case .fileTooLarge(let size, let limit):
            return "file is \(InputError.mb(size)) MB, plugin limit is \(InputError.mb(limit)) MB"
        case .unreadable(let m): return "could not read file: \(m)"
        case .invalidJSON(let m): return "not valid JSON: \(m)"
        case .invalidPlist(let m): return "could not preview property list: \(m)"
        case .notSQLite: return "not a SQLite database (bad header)"
        case .sqlite(let m): return "sqlite: \(m)"
        case .archive(let m): return "could not preview archive: \(m)"
        case .epub(let m): return "could not preview EPUB: \(m)"
        }
    }

    static func mb(_ bytes: Int) -> String {
        let v = Double(bytes) / 1_048_576
        return v < 10 ? String(format: "%.1f", v) : String(Int(v.rounded()))
    }
}

/// what gets injected as `spacebar.data`. `.json`, `.plist` and `.sqlite` carry a
/// JSONSerialization-compatible object graph.
public enum InputPayload {
    case text(String)
    case bytes(Data)
    case json(Any)
    case plist(Any)
    case sqlite([String: Any])
    case archive([String: Any])
    case epub([String: Any])

    public var kind: InputKind {
        switch self {
        case .text: return .text
        case .bytes: return .bytes
        case .json: return .json
        case .plist: return .plist
        case .sqlite: return .sqlite
        case .archive: return .archive
        case .epub: return .epub
        }
    }
}

public protocol InputProvider {
    static func load(url: URL, manifest: Manifest) throws -> InputPayload
}

public enum InputLoader {
    /// size gate shared by every provider; the host calls this before loading
    public static func checkSize(_ file: FileInfo, manifest: Manifest) throws {
        if file.size > manifest.maxFileSize {
            throw InputError.fileTooLarge(size: file.size, limit: manifest.maxFileSize)
        }
    }

    public static func load(kind: InputKind, url: URL, manifest: Manifest) throws -> InputPayload {
        switch kind {
        case .text: return try TextInput.load(url: url, manifest: manifest)
        case .bytes: return try BytesInput.load(url: url, manifest: manifest)
        case .json: return try JSONInput.load(url: url, manifest: manifest)
        case .plist: return try PlistInput.load(url: url, manifest: manifest)
        case .sqlite: return try SQLiteInput.load(url: url, manifest: manifest)
        case .archive: return try ArchiveInput.load(url: url, manifest: manifest)
        case .epub: return try EPUBInput.load(url: url, manifest: manifest)
        }
    }

    static func readData(_ url: URL) throws -> Data {
        do { return try Data(contentsOf: url, options: [.mappedIfSafe]) }
        catch { throw InputError.unreadable(error.localizedDescription) }
    }
}
