import Foundation
import XCTest
import CArchive
@testable import SpacebarKit

final class ArchiveInputTests: XCTestCase {
    @discardableResult
    func archive(_ tmp: TempDir, _ name: String, files: [(String, Data)], format: String = "zip") throws -> URL {
        let url = tmp.url.appendingPathComponent(name)
        let writer = try XCTUnwrap(archive_write_new())
        defer { archive_write_free(writer) }
        switch format {
        case "7z": XCTAssertEqual(archive_write_set_format_7zip(writer), ARCHIVE_OK)
        case "tar", "tgz", "tbz", "txz":
            XCTAssertEqual(archive_write_set_format_pax_restricted(writer), ARCHIVE_OK)
            if format == "tgz" { XCTAssertEqual(archive_write_add_filter_gzip(writer), ARCHIVE_OK) }
            if format == "tbz" { XCTAssertEqual(archive_write_add_filter_bzip2(writer), ARCHIVE_OK) }
            if format == "txz" { XCTAssertEqual(archive_write_add_filter_xz(writer), ARCHIVE_OK) }
        default: XCTAssertEqual(archive_write_set_format_zip(writer), ARCHIVE_OK)
        }
        XCTAssertEqual(url.withUnsafeFileSystemRepresentation { archive_write_open_filename(writer, $0) }, ARCHIVE_OK)
        for (path, data) in files {
            let entry = try XCTUnwrap(archive_entry_new())
            defer { archive_entry_free(entry) }
            archive_entry_set_pathname_utf8(entry, path)
            archive_entry_set_filetype(entry, path.hasSuffix("/") ? 0o040000 : 0o100000)
            archive_entry_set_perm(entry, 0o644)
            archive_entry_set_size(entry, Int64(data.count))
            archive_entry_set_mtime(entry, 1_767_268_800, 0)
            XCTAssertEqual(archive_write_header(writer, entry), ARCHIVE_OK)
            if !data.isEmpty { XCTAssertEqual(data.withUnsafeBytes { archive_write_data(writer, $0.baseAddress, data.count) }, data.count) }
        }
        XCTAssertEqual(archive_write_close(writer), ARCHIVE_OK)
        return url
    }
    func testListsZIPTARCompressedTARAnd7Zip() throws {
        let tmp = TempDir()
        for format in ["zip", "tar", "tgz", "tbz", "txz", "7z"] {
            let url = try archive(tmp, "sample.\(format)", files: [("folder/hello.txt", Data("hello".utf8)), ("empty/", Data())], format: format)
            guard case .archive(let payload) = try ArchiveInput.load(url: url, manifest: manifest("archive", input: .archive)) else { return XCTFail() }
            let rows = try XCTUnwrap(payload["entries"] as? [[String: Any]])
            XCTAssertEqual(rows.count, 2)
            let file = try XCTUnwrap(rows.first { $0["path"] as? String == "folder/hello.txt" })
            XCTAssertEqual(file["size"] as? Int64, 5)
            XCTAssertEqual(file["kind"] as? String, "file")
            XCTAssertEqual(payload["truncated"] as? Bool, false)
            XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.url.appendingPathComponent("folder/hello.txt").path))
        }
    }
    func testEmptyInvalidAndLiteralPaths() throws {
        let tmp = TempDir()
        let empty = try archive(tmp, "empty.zip", files: [])
        guard case .archive(let result) = try ArchiveInput.load(url: empty, manifest: manifest("archive")) else { return XCTFail() }
        XCTAssertEqual((result["entries"] as? [[String: Any]])?.count, 0)
        XCTAssertThrowsError(try ArchiveInput.load(url: tmp.write("bad.zip", "not an archive"), manifest: manifest("archive")))
        let unusual = try archive(tmp, "paths.zip", files: [("../outside.txt", Data()), ("<script>.txt", Data())])
        guard case .archive(let listing) = try ArchiveInput.load(url: unusual, manifest: manifest("archive")) else { return XCTFail() }
        let rows = try XCTUnwrap(listing["entries"] as? [[String: Any]])
        XCTAssertEqual(rows[0]["unsafePath"] as? Bool, true)
        XCTAssertEqual(rows[1]["path"] as? String, "<script>.txt")
        let resources = try ArchiveReader.files(unusual, paths: ["../outside.txt"], deadline: Date().addingTimeInterval(2))
        XCTAssertTrue(resources.isEmpty)
    }
    func testReadLimitsAndContainerPaths() throws {
        let tmp = TempDir()
        let file = try archive(tmp, "limits.zip", files: [("large.txt", Data(repeating: 65, count: 100)), ("small.txt", Data("ok".utf8))])
        let result = try ArchiveReader.files(file, paths: ["large.txt", "small.txt"], perFile: 10, total: 10, deadline: Date().addingTimeInterval(2))
        XCTAssertNil(result["large.txt"])
        XCTAssertEqual(result["small.txt"], Data("ok".utf8))
        XCTAssertNil(ArchiveReader.safePath("/etc/passwd"))
        XCTAssertNil(ArchiveReader.safePath("../outside"))
        XCTAssertEqual(ArchiveReader.safePath("./Book/chapter.xhtml"), "Book/chapter.xhtml")
        XCTAssertEqual(EPUBInput.resolve("../images/a%20b.png", relativeTo: "Book/text/ch1.xhtml"), "Book/images/a b.png")
        XCTAssertNil(EPUBInput.resolve("../../../outside", relativeTo: "Book/text/ch1.xhtml"))
        XCTAssertNil(EPUBInput.resolve("https://example.com/book", relativeTo: "Book/text/ch1.xhtml"))
    }
    func bookFiles() -> [(String, Data)] {
        let strings = [
            ("META-INF/container.xml", "<container><rootfiles><rootfile full-path=\"Book/package.opf\"/></rootfiles></container>"),
            ("Book/package.opf", "<package><metadata xmlns:dc=\"urn:dc\"><dc:title>Example &amp; Book</dc:title><dc:creator>A. Writer</dc:creator><dc:language>en</dc:language></metadata><manifest><item id=\"a\" href=\"text/a.xhtml\" media-type=\"application/xhtml+xml\"/><item id=\"b\" href=\"text/b.xhtml\" media-type=\"application/xhtml+xml\"/><item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/><item id=\"cover\" href=\"cover.png\" media-type=\"image/png\" properties=\"cover-image\"/></manifest><spine><itemref idref=\"a\"/><itemref idref=\"b\"/></spine></package>"),
            ("Book/nav.xhtml", "<html xmlns:epub=\"urn:epub\"><body><nav epub:type=\"toc\"><a href=\"text/a.xhtml\">First <span>chapter</span></a><a href=\"text/b.xhtml\">Second chapter</a></nav></body></html>"),
            ("Book/text/a.xhtml", "<html><body><h1>Hello</h1><img src=\"../cover.png\"/></body></html>"),
            ("Book/text/b.xhtml", "<html><body><h1>Second</h1></body></html>")
        ]
        return strings.map { ($0.0, Data($0.1.utf8)) } + [("Book/cover.png", Data([137, 80, 78, 71]))]
    }
    func testEPUBMetadataSpineContentsAndImages() throws {
        let tmp = TempDir()
        let url = try archive(tmp, "book.epub", files: bookFiles())
        guard case .epub(let result) = try EPUBInput.load(url: url, manifest: manifest("epub")) else { return XCTFail() }
        XCTAssertEqual(result["title"] as? String, "Example & Book")
        XCTAssertEqual(result["authors"] as? [String], ["A. Writer"])
        let chapters = try XCTUnwrap(result["chapters"] as? [[String: Any]])
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters[0]["title"] as? String, "First chapter")
        XCTAssertEqual(chapters[1]["path"] as? String, "Book/text/b.xhtml")
        XCTAssertTrue((result["cover"] as? String)?.hasPrefix("data:image/png;base64,") == true)
        XCTAssertEqual(result["truncated"] as? Bool, false)
    }
    func testEPUB2NCXAndOversizedChapter() throws {
        let tmp = TempDir()
        var files = bookFiles().map { path, bytes -> (String, Data) in
            if path == "Book/package.opf" {
                let xml = String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: "<spine>", with: "<spine toc=\"nav\">")
                    .replacingOccurrences(of: "href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"", with: "href=\"toc.ncx\" media-type=\"application/x-dtbncx+xml\"")
                return (path, Data(xml.utf8))
            }
            return (path, bytes)
        }
        files.append(("Book/toc.ncx", Data("<ncx><navMap><navPoint><navLabel><text>Old contents</text></navLabel><content src=\"text/a.xhtml\"/></navPoint></navMap></ncx>".utf8)))
        let url = try archive(tmp, "old.epub", files: files)
        guard case .epub(let result) = try EPUBInput.load(url: url, manifest: manifest("epub")) else { return XCTFail() }
        XCTAssertEqual((result["chapters"] as? [[String: Any]])?.first?["title"] as? String, "Old contents")
        files = bookFiles().map { $0.0 == "Book/text/a.xhtml" ? ($0.0, Data(repeating: 65, count: 1_048_577)) : $0 }
        let big = try archive(tmp, "big.epub", files: files)
        guard case .epub(let limited) = try EPUBInput.load(url: big, manifest: manifest("epub")) else { return XCTFail() }
        XCTAssertEqual(limited["truncated"] as? Bool, true)
        XCTAssertEqual((limited["chapters"] as? [[String: Any]])?.count, 1)
    }
    func testEPUBRejectsMissingMetadataAndEntities() throws {
        let tmp = TempDir()
        let invalid = try archive(tmp, "invalid.epub", files: [("hello", Data())])
        XCTAssertThrowsError(try EPUBInput.load(url: invalid, manifest: manifest("epub")))
        let files = bookFiles().map { path, bytes in
            (path, path == "Book/package.opf" ? Data("<!DOCTYPE package [<!ENTITY local SYSTEM 'file:///etc/passwd'>]><package>&local;</package>".utf8) : bytes)
        }
        let hostile = try archive(tmp, "hostile.epub", files: files)
        XCTAssertThrowsError(try EPUBInput.load(url: hostile, manifest: manifest("epub")))
    }
}
