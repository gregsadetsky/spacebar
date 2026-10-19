import XCTest
@testable import SpacebarKit

final class ManifestTests: XCTestCase {
    let valid = """
    {"id": "geojson", "name": "GeoJSON", "version": "0.1.0",
     "matches": {"extensions": ["GeoJSON", ".json"], "utis": ["public.geojson"]},
     "input": "text", "maxFileSize": 1234, "entry": "index.html", "requiresHost": "0.1.0", "priority": 3}
    """

    func testValidDecodes() throws {
        let m = try Manifest.parse(Data(valid.utf8))
        XCTAssertEqual(m.id, "geojson")
        XCTAssertEqual(m.matches.extensions, ["geojson", "json"], "extensions are lowercased and stripped of dots")
        XCTAssertEqual(m.matches.utis, ["public.geojson"])
        XCTAssertEqual(m.input, .text)
        XCTAssertEqual(m.maxFileSize, 1234)
        XCTAssertEqual(m.priority, 3)
        XCTAssertEqual(m.requiresHost, "0.1.0")
    }

    func testDefaults() throws {
        let m = try Manifest.parse(Data("""
        {"id": "x", "name": "X", "version": "1.2.3", "matches": {"extensions": ["x"]}, "input": "bytes"}
        """.utf8))
        XCTAssertEqual(m.maxFileSize, Manifest.defaultMaxFileSize)
        XCTAssertEqual(m.entry, "index.html")
        XCTAssertEqual(m.priority, 0)
        XCTAssertNil(m.requiresHost)
        XCTAssertEqual(m.matches.utis, [])
    }

    func testMissingFields() {
        for field in ["id", "name", "version", "matches", "input"] {
            var obj = try! JSONSerialization.jsonObject(with: Data(valid.utf8)) as! [String: Any]
            obj.removeValue(forKey: field)
            let data = try! JSONSerialization.data(withJSONObject: obj)
            XCTAssertThrowsError(try Manifest.parse(data), field) { error in
                XCTAssertEqual(error as? ManifestError, .missingField(field))
            }
        }
    }

    func testBadInputValue() {
        let json = valid.replacingOccurrences(of: "\"input\": \"text\"", with: "\"input\": \"yaml\"")
        XCTAssertThrowsError(try Manifest.parse(Data(json.utf8))) { error in
            XCTAssertEqual(error as? ManifestError, .badInput("yaml"))
        }
    }

    func testNonSemverVersion() {
        for v in ["1", "1.0", "v1.0.0", "1.0.0-beta", "a.b.c", ""] {
            let json = valid.replacingOccurrences(of: "\"version\": \"0.1.0\"", with: "\"version\": \"\(v)\"")
            XCTAssertThrowsError(try Manifest.parse(Data(json.utf8)), v) { error in
                XCTAssertEqual(error as? ManifestError, .badVersion(v))
            }
        }
    }

    func testBadID() {
        for id in ["GeoJSON", "geo json", "-x", "geo_json", "", "géo"] {
            let json = valid.replacingOccurrences(of: "\"id\": \"geojson\"", with: "\"id\": \"\(id)\"")
            XCTAssertThrowsError(try Manifest.parse(Data(json.utf8)), id) { error in
                XCTAssertEqual(error as? ManifestError, .badID(id))
            }
        }
    }

    func testNoMatches() {
        let json = valid.replacingOccurrences(of: "\"matches\": {\"extensions\": [\"GeoJSON\", \".json\"], \"utis\": [\"public.geojson\"]}", with: "\"matches\": {\"extensions\": [\".\"]}")
        XCTAssertThrowsError(try Manifest.parse(Data(json.utf8))) { error in
            XCTAssertEqual(error as? ManifestError, .noMatches)
        }
    }

    func testInvalidJSON() {
        XCTAssertThrowsError(try Manifest.parse(Data("{not json".utf8))) { error in
            guard case .invalidJSON = error as? ManifestError else { return XCTFail("\(error)") }
        }
        XCTAssertThrowsError(try Manifest.parse(Data("{\"id\": 5}".utf8))) { error in
            guard case .invalidJSON = error as? ManifestError else { return XCTFail("\(error)") }
        }
    }

    func testLoadFromDirectoryChecksEntry() throws {
        let tmp = TempDir()
        let dir = tmp.plugin("ok")
        XCTAssertEqual(try Manifest.load(fromDirectory: dir).id, "ok")

        let missing = tmp.plugin("noentry")
        try FileManager.default.removeItem(at: missing.appendingPathComponent("index.html"))
        XCTAssertThrowsError(try Manifest.load(fromDirectory: missing)) { error in
            XCTAssertEqual(error as? ManifestError, .entryMissing("index.html"))
        }

        XCTAssertThrowsError(try Manifest.load(fromDirectory: tmp.url.appendingPathComponent("nothing"))) { error in
            guard case .fileMissing = error as? ManifestError else { return XCTFail("\(error)") }
        }
    }

    func testEntryCannotEscapePluginFolder() {
        for entry in ["/etc/passwd", "../index.html", ""] {
            let json = valid.replacingOccurrences(of: "\"entry\": \"index.html\"", with: "\"entry\": \"\(entry)\"")
            XCTAssertThrowsError(try Manifest.parse(Data(json.utf8)), entry) { error in
                XCTAssertEqual(error as? ManifestError, .entryMissing(entry))
            }
        }
    }

    func testVersionCompare() {
        XCTAssertTrue(Manifest.version("0.1.0", isAtLeast: "0.1.0"))
        XCTAssertTrue(Manifest.version("0.2.0", isAtLeast: "0.1.9"))
        XCTAssertTrue(Manifest.version("1.0.0", isAtLeast: "0.9.9"))
        XCTAssertFalse(Manifest.version("0.1.0", isAtLeast: "0.1.1"))
        XCTAssertFalse(Manifest.version("0.0.9", isAtLeast: "0.1.0"))
    }
}
