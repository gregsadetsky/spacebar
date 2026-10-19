import Foundation
import UniformTypeIdentifiers

/// what the host knows about the previewed file; mirrored into `spacebar.file`
public struct FileInfo: Equatable, Sendable {
    public let url: URL
    public let name: String
    public let ext: String
    public let uti: String?
    public let size: Int

    public init(url: URL, name: String, ext: String, uti: String?, size: Int) {
        self.url = url; self.name = name; self.ext = ext; self.uti = uti; self.size = size
    }

    /// resolve name / ext / uti / size from disk
    public init(url: URL) {
        let ext = url.pathExtension.lowercased()
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        let uti = values?.contentType?.identifier ?? UTType(filenameExtension: ext)?.identifier
        self.init(url: url, name: url.lastPathComponent, ext: ext, uti: uti, size: values?.fileSize ?? 0)
    }

    public var jsonObject: [String: Any] {
        ["name": name, "path": url.path, "size": size, "uti": uti as Any, "ext": ext]
    }
}
