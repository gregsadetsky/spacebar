import XCTest
@testable import SpacebarKit

final class InputTests: XCTestCase {
    func testTextInput() throws {
        let tmp = TempDir()
        let url = tmp.write("a.txt", "héllo\nworld")
        guard case .text(let s) = try InputLoader.load(kind: .text, url: url, manifest: manifest("t")) else { return XCTFail() }
        XCTAssertEqual(s, "héllo\nworld")
    }

    func testTextInputInvalidUTF8DoesNotThrow() throws {
        let tmp = TempDir()
        let url = tmp.write("bad.txt", data: Data([0x61, 0xFF, 0x62]))
        guard case .text(let s) = try InputLoader.load(kind: .text, url: url, manifest: manifest("t")) else { return XCTFail() }
        XCTAssertEqual(s, "a\u{FFFD}b")
    }

    func testUTF16SubtitleText() throws {
        let tmp = TempDir()
        let original = "1\n00:00:01,000 --> 00:00:02,000\nHello 世界 🌊"
        let url = tmp.write("captions.srt", data: original.data(using: .utf16)!)
        guard case .text(let text) = try TextInput.load(url: url, manifest: manifest("subtitles")) else { return XCTFail() }
        XCTAssertEqual(text, original)
    }

    func testBytesInput() throws {
        let tmp = TempDir()
        let url = tmp.write("b.bin", data: Data([0, 1, 2, 255]))
        guard case .bytes(let d) = try InputLoader.load(kind: .bytes, url: url, manifest: manifest("b")) else { return XCTFail() }
        XCTAssertEqual([UInt8](d), [0, 1, 2, 255])
    }

    func testJSONInput() throws {
        let tmp = TempDir()
        let url = tmp.write("c.json", "{\"a\": [1, 2, {\"b\": null}]}")
        guard case .json(let obj) = try InputLoader.load(kind: .json, url: url, manifest: manifest("j")) else { return XCTFail() }
        let dict = obj as? [String: Any]
        XCTAssertEqual((dict?["a"] as? [Any])?.count, 3)
    }

    func testJSONInputInvalidThrowsTyped() {
        let tmp = TempDir()
        let url = tmp.write("bad.json", "{\"a\": ")
        XCTAssertThrowsError(try InputLoader.load(kind: .json, url: url, manifest: manifest("j"))) { error in
            guard case .invalidJSON = error as? InputError else { return XCTFail("\(error)") }
        }
    }

    func testUnreadableFile() {
        XCTAssertThrowsError(try InputLoader.load(kind: .text, url: URL(fileURLWithPath: "/nonexistent/x.txt"), manifest: manifest("t"))) { error in
            guard case .unreadable = error as? InputError else { return XCTFail("\(error)") }
        }
    }

    func testSizeGate() {
        let tmp = TempDir()
        let url = tmp.write("big.txt", String(repeating: "x", count: 1000))
        let file = FileInfo(url: url)
        XCTAssertEqual(file.size, 1000)
        var m = manifest("t"); m.maxFileSize = 999
        XCTAssertThrowsError(try InputLoader.checkSize(file, manifest: m)) { error in
            XCTAssertEqual(error as? InputError, .fileTooLarge(size: 1000, limit: 999))
        }
        m.maxFileSize = 1000
        XCTAssertNoThrow(try InputLoader.checkSize(file, manifest: m))
    }

    func testFileInfoResolvesUTI() {
        let tmp = TempDir()
        let url = tmp.write("cities.geojson", "{}")
        let f = FileInfo(url: url)
        XCTAssertEqual(f.name, "cities.geojson")
        XCTAssertEqual(f.ext, "geojson")
        XCTAssertEqual(f.size, 2)
        XCTAssertNotNil(f.uti)
    }

    func testErrorMessages() {
        XCTAssertEqual(InputError.fileTooLarge(size: 60 * 1_048_576, limit: 50 * 1_048_576).description, "file is 60 MB, plugin limit is 50 MB")
        XCTAssertEqual(InputError.fileTooLarge(size: 1_500_000, limit: 1_000_000).description, "file is 1.4 MB, plugin limit is 1.0 MB")
    }
}
