import XCTest
@testable import SpacebarKit

final class StreamInputTests: XCTestCase {
    func testRangeParsing() {
        XCTAssertEqual(ByteRange.parse("bytes=0-99", size: 1000), ByteRange(start: 0, end: 99))
        XCTAssertEqual(ByteRange.parse("bytes=100-", size: 1000), ByteRange(start: 100, end: 999))
        XCTAssertEqual(ByteRange.parse("bytes=-100", size: 1000), ByteRange(start: 900, end: 999))
        XCTAssertEqual(ByteRange.parse("bytes=990-5000", size: 1000), ByteRange(start: 990, end: 999), "end is clamped to the file")
        XCTAssertEqual(ByteRange.parse("bytes=-5000", size: 1000), ByteRange(start: 0, end: 999), "suffix bigger than the file")
        XCTAssertEqual(ByteRange.parse("bytes=0-0", size: 1000)?.length, 1)
    }

    func testRangeRejects() {
        XCTAssertNil(ByteRange.parse(nil, size: 1000))
        XCTAssertNil(ByteRange.parse("", size: 1000))
        XCTAssertNil(ByteRange.parse("items=0-9", size: 1000))
        XCTAssertNil(ByteRange.parse("bytes=1000-", size: 1000), "start past the end")
        XCTAssertNil(ByteRange.parse("bytes=50-10", size: 1000), "end before start")
        XCTAssertNil(ByteRange.parse("bytes=0-9,20-29", size: 1000), "multi-range is not served")
        XCTAssertNil(ByteRange.parse("bytes=-0", size: 1000))
        XCTAssertNil(ByteRange.parse("bytes=abc-", size: 1000))
        XCTAssertNil(ByteRange.parse("bytes=0-9", size: 0), "empty file")
    }

    func testStreamPayload() throws {
        let tmp = TempDir()
        let url = tmp.write("clip.webm", "not really a video")
        let m = Manifest(id: "video", name: "Video", version: "0.1.0", matches: .init(extensions: ["webm"]), input: .stream)
        guard case .stream(let u) = try InputLoader.load(kind: .stream, url: url, manifest: m) else { return XCTFail() }
        XCTAssertEqual(u.absoluteString, "spacebar-file:///current")
        XCTAssertThrowsError(try InputLoader.load(kind: .stream, url: URL(fileURLWithPath: "/nonexistent/x.webm"), manifest: m)) { error in
            guard case .unreadable = error as? InputError else { return XCTFail("\(error)") }
        }
    }

    func testStreamBridgeAndMime() throws {
        let tmp = TempDir()
        let url = tmp.write("clip.webm", "x")
        let file = FileInfo(url: url)
        let m = Manifest(id: "video", name: "Video", version: "0.1.0", matches: .init(extensions: ["webm"]), input: .stream)
        let script = try Bridge.script(file: file, manifest: m, payload: .stream(StreamInput.currentFileURL), theme: .light)
        XCTAssertTrue(script.contains("data: \"spacebar-file:///current\""))
        XCTAssertEqual(StreamInput.mimeType(for: file), "video/webm")
        XCTAssertEqual(StreamInput.mimeType(for: FileInfo(url: tmp.write("x.unknownext", "x"))), "application/octet-stream")
    }

    func testManifestAcceptsStream() throws {
        let m = try Manifest.parse(Data("""
        {"id": "video", "name": "V", "version": "0.1.0", "matches": {"extensions": ["webm"]}, "input": "stream"}
        """.utf8))
        XCTAssertEqual(m.input, .stream)
    }
}
