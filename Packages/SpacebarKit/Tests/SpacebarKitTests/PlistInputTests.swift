import XCTest
import JavaScriptCore
@testable import SpacebarKit

final class PlistInputTests: XCTestCase {
    func load(_ url: URL) throws -> Any {
        let payload = try InputLoader.load(kind: .plist, url: url, manifest: manifest("plist", input: .plist))
        XCTAssertEqual(payload.kind, .plist)
        guard case .plist(let value) = payload else { throw InputError.invalidPlist("wrong payload kind") }
        return value
    }

    func testXMLAndBinaryValuesAndSourceUnchanged() throws {
        let tmp = TempDir()
        let value: [String: Any] = [
            "name": "héllo 世界 🌟 👩🏽‍💻", "enabled": true, "disabled": false,
            "count": 1, "negative": -42, "ratio": 1.25,
            "nested": ["items": ["a", "b"], "empty": [:] as [String: String]],
            "date": Date(timeIntervalSince1970: 1_700_000_000),
            "data": Data([0, 255, 10]), "emptyData": Data(),
        ]
        for format: PropertyListSerialization.PropertyListFormat in [.xml, .binary] {
            let bytes = try PropertyListSerialization.data(fromPropertyList: value, format: format, options: 0)
            let url = tmp.write("sample.plist", data: bytes)
            let result = try XCTUnwrap(try load(url) as? [String: Any])
            XCTAssertEqual(result["name"] as? String, value["name"] as? String)
            XCTAssertEqual(result["enabled"] as? Bool, true)
            XCTAssertEqual(result["disabled"] as? Bool, false)
            XCTAssertEqual(result["count"] as? Int, 1)
            XCTAssertEqual(result["negative"] as? Int, -42)
            XCTAssertEqual(result["ratio"] as? Double, 1.25)
            XCTAssertEqual(result["date"] as? String, "2023-11-14T22:13:20.000Z")
            XCTAssertEqual((result["data"] as? [String: Any])?["data"] as? String, "AP8K")
            XCTAssertEqual((result["data"] as? [String: Any])?["bytes"] as? Int, 3)
            XCTAssertEqual((result["emptyData"] as? [String: Any])?["bytes"] as? Int, 0)
            XCTAssertEqual((result["nested"] as? [String: Any])?["items"] as? [String], ["a", "b"])
            XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: result))
            XCTAssertEqual(try Data(contentsOf: url), bytes, "preview must never rewrite the input")
        }
    }

    func testOpenStepAndNonDictionaryRoots() throws {
        let tmp = TempDir()
        let old = tmp.write("old.plist", "{ name = \"old style\"; items = (one, two); data = <00ff>; }")
        let value = try XCTUnwrap(try load(old) as? [String: Any])
        XCTAssertEqual(value["name"] as? String, "old style")
        XCTAssertEqual(value["items"] as? [String], ["one", "two"])
        XCTAssertEqual((value["data"] as? [String: Any])?["data"] as? String, "AP8=")
        for root: Any in [["one", "two"], "single 🌟", true, 42, [] as [String], [:] as [String: String]] {
            let bytes = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
            let result = try load(tmp.write("root.plist", data: bytes))
            XCTAssertEqual(try Bridge.jsLiteral(result), try Bridge.jsLiteral(root))
        }
    }

    func testLargeIntegersAndNonFiniteReals() throws {
        let tmp = TempDir()
        let value: [String: Any] = [
            "safe": Int64(9_007_199_254_740_991), "unsafe": Int64(9_007_199_254_740_993),
            "max": UInt64.max, "min": Int64.min,
            "nan": Double.nan, "positiveInfinity": Double.infinity, "negativeInfinity": -Double.infinity,
        ]
        let bytes = try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
        let result = try XCTUnwrap(try load(tmp.write("numbers.plist", data: bytes)) as? [String: Any])
        XCTAssertEqual(result["safe"] as? Int64, 9_007_199_254_740_991)
        XCTAssertEqual(result["unsafe"] as? String, "9007199254740993")
        XCTAssertEqual(result["max"] as? String, "18446744073709551615")
        XCTAssertEqual(result["min"] as? String, "-9223372036854775808")
        XCTAssertEqual(result["nan"] as? String, "NaN")
        XCTAssertEqual(result["positiveInfinity"] as? String, "Infinity")
        XCTAssertEqual(result["negativeInfinity"] as? String, "-Infinity")
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: result))
    }

    func testKeyedArchiveReferencesAreData() throws {
        let tmp = TempDir()
        let bytes = try NSKeyedArchiver.archivedData(withRootObject: ["hello": "world"], requiringSecureCoding: true)
        let result = try XCTUnwrap(try load(tmp.write("archive.plist", data: bytes)) as? [String: Any])
        XCTAssertEqual(result["$archiver"] as? String, "NSKeyedArchiver")
        let top = try XCTUnwrap(result["$top"] as? [String: Any])
        XCTAssertEqual((top["root"] as? [String: Any])?["CF$UID"] as? Int, 1)
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: result))
    }

    func testMalformedAndUnreadableFiles() {
        let tmp = TempDir()
        for text in ["", "<plist><dict>", "bplist00broken"] {
            XCTAssertThrowsError(try load(tmp.write("bad.plist", text))) { error in
                guard case .invalidPlist = error as? InputError else { return XCTFail("\(error)") }
            }
        }
        XCTAssertThrowsError(try load(tmp.url.appendingPathComponent("missing.plist"))) { error in
            guard case .unreadable = error as? InputError else { return XCTFail("\(error)") }
        }
    }

    func testSizeAndExpansionLimits() throws {
        let tmp = TempDir()
        let url = tmp.write("oversize.plist", String(repeating: "x", count: 100))
        var m = manifest("plist", input: .plist)
        m.maxFileSize = 50
        XCTAssertThrowsError(try PlistInput.load(url: url, manifest: m)) { error in
            XCTAssertEqual(error as? InputError, .fileTooLarge(size: 100, limit: 50))
        }
        let values = Array(repeating: "shared", count: 100_001)
        let bytes = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        XCTAssertThrowsError(try load(tmp.write("wide.plist", data: bytes))) { error in
            guard case .invalidPlist(let message) = error as? InputError else { return XCTFail("\(error)") }
            XCTAssertTrue(message.contains("preview limit"))
        }
        var nested: Any = "end"
        for _ in 0..<130 { nested = [nested] }
        let deep = try PropertyListSerialization.data(fromPropertyList: nested, format: .binary, options: 0)
        XCTAssertThrowsError(try load(tmp.write("deep.plist", data: deep)))
    }

    func testBridgePreservesSpecialKeysAndTypes() throws {
        let tmp = TempDir()
        let value: [String: Any] = ["__proto__": ["hello": "world"], "html": "</script><b>🌟</b>", "bool": true, "one": 1]
        let bytes = try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
        let url = tmp.write("bridge.plist", data: bytes)
        let payload = try InputLoader.load(kind: .plist, url: url, manifest: manifest("plist", input: .plist))
        let script = try Bridge.script(file: FileInfo(url: url), manifest: manifest("plist", input: .plist), payload: payload, theme: .light)
        let ctx = JSContext()!
        ctx.evaluateScript("var window = this; var console = {}; window.addEventListener = function () {};")
        ctx.evaluateScript(script)
        XCTAssertNil(ctx.exception)
        XCTAssertEqual(ctx.evaluateScript("spacebar.input")?.toString(), "plist")
        XCTAssertTrue(ctx.evaluateScript("Object.hasOwn(spacebar.data, '__proto__')")!.toBool())
        XCTAssertEqual(ctx.evaluateScript("spacebar.data.__proto__.hello")?.toString(), "world")
        XCTAssertEqual(ctx.evaluateScript("spacebar.data.html")?.toString(), value["html"] as? String)
        XCTAssertEqual(ctx.evaluateScript("typeof spacebar.data.bool")?.toString(), "boolean")
        XCTAssertEqual(ctx.evaluateScript("typeof spacebar.data.one")?.toString(), "number")
    }
}
