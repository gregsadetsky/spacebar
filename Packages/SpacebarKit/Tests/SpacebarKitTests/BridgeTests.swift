import XCTest
import JavaScriptCore
@testable import SpacebarKit

final class BridgeTests: XCTestCase {
    let file = FileInfo(url: URL(fileURLWithPath: "/tmp/cities.geojson"), name: "cities.geojson", ext: "geojson", uti: "public.geojson", size: 12345)

    /// runs the injected script in a bare JSContext with a fake `window` and
    /// a recording `webkit.messageHandlers.host`, returns (window.spacebar, messages)
    func run(_ script: String) throws -> (JSValue, [[String: Any]]) {
        let ctx = JSContext()!
        var exceptions: [String] = []
        ctx.exceptionHandler = { _, e in exceptions.append(e?.toString() ?? "?") }
        ctx.evaluateScript("""
        var window = this; var console = { log: null, warn: null, error: null, info: null };
        var __messages = [];
        window.addEventListener = function () {};
        window.webkit = { messageHandlers: { host: { postMessage: function (m) { __messages.push(m); } } } };
        """)
        ctx.evaluateScript(script)
        XCTAssertEqual(exceptions, [], "script threw")
        let spacebar = ctx.objectForKeyedSubscript("spacebar")!
        let messages = ctx.objectForKeyedSubscript("__messages")!.toArray() as? [[String: Any]] ?? []
        return (spacebar, messages)
    }

    func testTextPayloadRoundTrips() throws {
        let text = "line1\nline2 \"quoted\" </script> \u{2028} \u{2029} \\ end"
        let script = try Bridge.script(file: file, manifest: manifest("geojson", extensions: ["geojson"]), payload: .text(text), theme: .dark)
        let (sb, _) = try run(script)
        XCTAssertEqual(sb.forProperty("data").toString(), text)
        XCTAssertEqual(sb.forProperty("input").toString(), "text")
        XCTAssertEqual(sb.forProperty("theme").toString(), "dark")
        XCTAssertEqual(sb.forProperty("file").forProperty("name").toString(), "cities.geojson")
        XCTAssertEqual(sb.forProperty("file").forProperty("size").toInt32(), 12345)
        XCTAssertEqual(sb.forProperty("file").forProperty("uti").toString(), "public.geojson")
        XCTAssertEqual(sb.forProperty("host").forProperty("version").toString(), Host.version)
        XCTAssertEqual(sb.forProperty("plugin").forProperty("id").toString(), "geojson")
    }

    func testJSONPayloadIsAnObject() throws {
        let obj: [String: Any] = ["type": "FeatureCollection", "features": [["type": "Feature", "n": 1.5]], "nil": NSNull()]
        let script = try Bridge.script(file: file, manifest: manifest("j", input: .json), payload: .json(obj), theme: .light)
        let (sb, _) = try run(script)
        XCTAssertEqual(sb.forProperty("data").forProperty("type").toString(), "FeatureCollection")
        XCTAssertEqual(sb.forProperty("data").forProperty("features").toArray().count, 1)
        XCTAssertTrue(sb.forProperty("data").forProperty("nil").isNull)
    }

    func testBytesPayloadIsBase64() throws {
        let script = try Bridge.script(file: file, manifest: manifest("b", input: .bytes), payload: .bytes(Data([0, 255, 10])), theme: .light)
        let (sb, _) = try run(script)
        XCTAssertEqual(sb.forProperty("data").toString(), Data([0, 255, 10]).base64EncodedString())
    }

    func testJSONPreservesPrototypeNamedKeys() throws {
        let obj: [String: Any] = ["__proto__": ["inherited": true], "constructor": "literal", "source": "</script>\u{2028}"]
        let script = try Bridge.script(file: file, manifest: manifest("notebook", input: .json), payload: .json(obj), theme: .light)
        let (sb, _) = try run(script)
        XCTAssertTrue(sb.context.evaluateScript("Object.prototype.hasOwnProperty.call(spacebar.data, '__proto__')")!.toBool())
        XCTAssertTrue(sb.forProperty("data").forProperty("inherited").isUndefined)
        XCTAssertEqual(sb.forProperty("data").forProperty("constructor").toString(), "literal")
        XCTAssertEqual(sb.forProperty("data").forProperty("source").toString(), "</script>\u{2028}")
    }

    func testDoneFailLogPostMessages() throws {
        let script = try Bridge.script(file: file, manifest: manifest("t"), payload: .text("x"), theme: .light)
        let (sb, _) = try run(script)
        sb.invokeMethod("done", withArguments: [])
        sb.invokeMethod("fail", withArguments: ["boom"])
        sb.invokeMethod("log", withArguments: ["hi"])
        let messages = sb.context.objectForKeyedSubscript("__messages")!.toArray() as! [[String: Any]]
        XCTAssertEqual(messages.map { $0["type"] as? String }, ["done", "fail", "log"])
        XCTAssertEqual(messages[1]["message"] as? String, "boom")
        XCTAssertTrue(messages[0]["message"] is NSNull)
    }

    func testConsoleLogForwarded() throws {
        let script = try Bridge.script(file: file, manifest: manifest("t"), payload: .text("x"), theme: .light)
        let (sb, _) = try run(script)
        sb.context.evaluateScript("console.log('a', {b: 1}); console.error('bad')")
        let messages = sb.context.objectForKeyedSubscript("__messages")!.toArray() as! [[String: Any]]
        XCTAssertEqual(messages.map { $0["message"] as? String }, ["[log] a {\"b\":1}", "[error] bad"])
    }

    func testLiteralEscaping() throws {
        XCTAssertEqual(try Bridge.jsLiteral("</script>"), "\"<\\/script>\"")
        XCTAssertEqual(try Bridge.jsLiteral("a\u{2028}b\u{2029}c"), "\"a\\u2028b\\u2029c\"")
        XCTAssertEqual(try Bridge.jsLiteral(["b": 1, "a": [true, NSNull()]]), "{\"a\":[true,null],\"b\":1}")
        XCTAssertFalse(try Bridge.jsLiteral("x\u{2028}").contains("\u{2028}"))
    }

    func testScriptIsSyntacticallyValidWithoutWebkit() throws {
        let script = try Bridge.script(file: file, manifest: manifest("t"), payload: .text("x"), theme: .light)
        let ctx = JSContext()!
        var exceptions: [String] = []
        ctx.exceptionHandler = { _, e in exceptions.append(e?.toString() ?? "?") }
        ctx.evaluateScript("var window = this; var console = {}; window.addEventListener = function(){};")
        ctx.evaluateScript(script)
        ctx.evaluateScript("spacebar.done(); spacebar.fail('x')")
        XCTAssertEqual(exceptions, [], "must not throw when there is no message handler (browser harness case)")
    }
}
