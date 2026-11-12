import Foundation
import UniformTypeIdentifiers

/// the `stream` input kind: the host does not read the file at all. the page
/// gets `spacebar.data` = a url on the host's private scheme that serves the
/// previewed file with http range support, so `<video>`, `<audio>`, images
/// and fetch() can read it in pieces. nothing is base64'd.
public enum StreamInput: InputProvider {
    public static let scheme = "spacebar-file"
    public static let currentFileURL = URL(string: "\(scheme):///current")!

    public static func load(url: URL, manifest: Manifest) throws -> InputPayload {
        guard FileManager.default.isReadableFile(atPath: url.path) else { throw InputError.unreadable(url.path) }
        return .stream(currentFileURL)
    }

    /// mime type for the response, from the file's uti; falls back to octet-stream
    public static func mimeType(for file: FileInfo) -> String {
        if let uti = file.uti, let type = UTType(uti), let mime = type.preferredMIMEType { return mime }
        if let type = UTType(filenameExtension: file.ext), let mime = type.preferredMIMEType { return mime }
        return "application/octet-stream"
    }
}

/// one http byte range, resolved against a known file size (rfc 9110 §14)
public struct ByteRange: Equatable, Sendable {
    public let start: Int
    public let end: Int   // inclusive

    public var length: Int { end - start + 1 }

    /// parses a `Range` header. nil when absent or unusable (the caller then
    /// serves the whole file with 200, which is what browsers expect).
    /// `bytes=0-99`, `bytes=100-` (to end), `bytes=-100` (last 100).
    public static func parse(_ header: String?, size: Int) -> ByteRange? {
        guard size > 0, let header, header.hasPrefix("bytes=") else { return nil }
        let spec = header.dropFirst("bytes=".count)
        guard !spec.contains(","), let dash = spec.firstIndex(of: "-") else { return nil }   // one range only
        let a = spec[..<dash].trimmingCharacters(in: .whitespaces)
        let b = spec[spec.index(after: dash)...].trimmingCharacters(in: .whitespaces)
        if a.isEmpty {
            guard let suffix = Int(b), suffix > 0 else { return nil }
            return ByteRange(start: max(0, size - suffix), end: size - 1)
        }
        guard let start = Int(a), start >= 0, start < size else { return nil }
        let end = b.isEmpty ? size - 1 : min(Int(b) ?? -1, size - 1)
        guard end >= start else { return nil }
        return ByteRange(start: start, end: end)
    }

    public init(start: Int, end: Int) { self.start = start; self.end = end }
}
