import Foundation
import CArchive

/// Uses the system libarchive. No extraction APIs, external processes or writes.
final class ArchiveReader {
    let handle: OpaquePointer
    let deadline: Date
    init(_ url: URL, deadline: Date = Date().addingTimeInterval(2)) throws {
        guard let reader = archive_read_new() else { throw InputError.archive("reader unavailable") }
        archive_read_support_filter_gzip(reader)
        archive_read_support_filter_bzip2(reader)
        archive_read_support_filter_xz(reader)
        archive_read_support_format_zip(reader)
        archive_read_support_format_tar(reader)
        archive_read_support_format_7zip(reader)
        archive_read_support_format_rar(reader)
        archive_read_support_format_rar5(reader)
        let result = url.withUnsafeFileSystemRepresentation { archive_read_open_filename(reader, $0, 16_384) }
        if result < ARCHIVE_OK {
            let message = archive_error_string(reader).map { String(cString: $0) } ?? "unrecognized or damaged file"
            archive_read_free(reader)
            throw InputError.archive(message)
        }
        handle = reader
        self.deadline = deadline
    }
    deinit { archive_read_free(handle) }
    var error: String { archive_error_string(handle).map { String(cString: $0) } ?? "damaged or unsupported archive" }
    var format: String { archive_format_name(handle).map { String(cString: $0) } ?? "Archive" }
    func next() throws -> OpaquePointer? {
        guard Date() < deadline else { throw InputError.archive("preview time limit reached") }
        var entry: OpaquePointer?
        let status = archive_read_next_header(handle, &entry)
        if status == ARCHIVE_EOF { return nil }
        guard status >= ARCHIVE_WARN, let entry else { throw InputError.archive(error) }
        return entry
    }
    func bytes(limit: Int) throws -> Data {
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            guard Date() < deadline else { throw InputError.archive("preview time limit reached") }
            let n = archive_read_data(handle, &buffer, buffer.count)
            guard n >= 0 else { throw InputError.archive(error) }
            if n == 0 { return result }
            guard result.count + n <= limit else { throw InputError.archive("expanded entry exceeds preview limit") }
            result.append(contentsOf: buffer.prefix(n))
        }
    }
    static func path(_ entry: OpaquePointer) -> String {
        (archive_entry_pathname_utf8(entry) ?? archive_entry_pathname(entry)).map { String(cString: $0) } ?? "(unnamed)"
    }
    static func regular(_ entry: OpaquePointer) -> Bool {
        archive_entry_filetype(entry) == 0o100000 && archive_entry_hardlink(entry) == nil && archive_entry_symlink(entry) == nil
    }
    /// Container-relative paths only. Never resolves against the filesystem.
    static func safePath(_ path: String) -> String? {
        guard !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0") else { return nil }
        let parts = path.split(separator: "/").filter { $0 != "." }
        guard !parts.contains(".."), !(parts.first?.contains(":") ?? false) else { return nil }
        return parts.joined(separator: "/")
    }
    static func files(_ url: URL, paths: Set<String>, perFile: Int = 2_097_152, total: Int = 16_777_216,
                      deadline: Date) throws -> [String: Data] {
        let reader = try ArchiveReader(url, deadline: deadline)
        var result: [String: Data] = [:]
        var used = 0, count = 0
        while let entry = try reader.next() {
            count += 1
            guard count <= 20_000 else { throw InputError.epub("too many archive entries") }
            guard let path = safePath(path(entry)), paths.contains(path), result[path] == nil, regular(entry) else { continue }
            guard archive_entry_is_encrypted(entry) != 1 else { throw InputError.epub("encrypted book content is not supported") }
            let size = archive_entry_size(entry)
            guard size >= 0 && size <= perFile && size <= total - used else { continue }
            let data = try reader.bytes(limit: min(perFile, total - used))
            result[path] = data; used += data.count
            if result.count == paths.count { break }
        }
        return result
    }
}

public enum ArchiveInput: InputProvider {
    public static func load(url: URL, manifest: Manifest) throws -> InputPayload {
        try InputLoader.checkSize(FileInfo(url: url), manifest: manifest)
        let reader = try ArchiveReader(url)
        var entries: [[String: Any]] = [], warnings: [String] = []
        var truncated = false, pathBytes = 0
        let iso = ISO8601DateFormatter()
        do {
            while let entry = try reader.next() {
                let path = ArchiveReader.path(entry)
                pathBytes += path.utf8.count
                if entries.count >= 10_000 || pathBytes > 2_097_152 {
                    truncated = true; warnings.append("Entry listing reached the preview limit."); break
                }
                let type = archive_entry_filetype(entry)
                let link = archive_entry_symlink(entry) ?? archive_entry_hardlink(entry)
                let kind = link != nil ? "link" : type == 0o040000 ? "directory" : type == 0o100000 ? "file" : "special"
                let size = max(0, archive_entry_size(entry))
                var row: [String: Any] = ["path": String(path.prefix(4096)), "kind": kind,
                    "size": size <= 9_007_199_254_740_991 ? (size as Any) : String(size),
                    "encrypted": archive_entry_is_encrypted(entry) == 1,
                    "unsafePath": ArchiveReader.safePath(path) == nil]
                if let link { row["target"] = String(String(cString: link).prefix(4096)) }
                if archive_entry_mtime_is_set(entry) != 0 {
                    row["modified"] = iso.string(from: Date(timeIntervalSince1970: Double(archive_entry_mtime(entry))))
                }
                entries.append(row)
                // Sequential compressed formats must inflate skipped entries. Stop
                // before a large one rather than expanding gigabytes just to list it.
                if archive_filter_code(reader.handle, 0) != ARCHIVE_FILTER_NONE && size > 64 * 1024 * 1024 {
                    truncated = true; warnings.append("Listing stopped at a large compressed entry."); break
                }
            }
        } catch {
            if entries.isEmpty { throw error }
            truncated = true; warnings.append(String(describing: error))
        }
        return .archive(["format": reader.format, "entries": entries, "truncated": truncated, "warnings": warnings])
    }
}
