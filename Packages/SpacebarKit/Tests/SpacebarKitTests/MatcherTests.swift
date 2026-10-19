import XCTest
@testable import SpacebarKit

final class MatcherTests: XCTestCase {
    func testExactUTIBeatsExtension() {
        let byExt = installed("by-ext", extensions: ["geojson"], priority: 100)
        let byUTI = installed("by-uti", utis: ["public.geojson"], priority: 0)
        let r = Matcher.pick(from: [byExt, byUTI], ext: "geojson", uti: "public.geojson")
        XCTAssertEqual(r.plugin?.manifest.id, "by-uti", "uti tier wins even against a higher-priority extension match")
        XCTAssertNil(r.warning)
    }

    func testExtensionFallbackWhenNoUTIMatch() {
        let byExt = installed("by-ext", extensions: ["geojson"])
        let other = installed("other", utis: ["public.json"])
        let r = Matcher.pick(from: [other, byExt], ext: "geojson", uti: "public.geojson")
        XCTAssertEqual(r.plugin?.manifest.id, "by-ext")
    }

    func testExtensionMatchIsCaseInsensitive() {
        let p = installed("p", extensions: ["geojson"])
        XCTAssertEqual(Matcher.pick(from: [p], ext: "GEOJSON", uti: nil).plugin?.manifest.id, "p")
    }

    func testPriorityWins() {
        let low = installed("aaa", extensions: ["x"], priority: 1)
        let high = installed("zzz", extensions: ["x"], priority: 5)
        let r = Matcher.pick(from: [low, high], ext: "x", uti: nil)
        XCTAssertEqual(r.plugin?.manifest.id, "zzz")
        XCTAssertNil(r.warning)
    }

    func testTieGoesAlphabeticalWithWarning() {
        let b = installed("bbb", extensions: ["x"])
        let a = installed("aaa", extensions: ["x"])
        let r = Matcher.pick(from: [b, a], ext: "x", uti: nil)
        XCTAssertEqual(r.plugin?.manifest.id, "aaa")
        XCTAssertNotNil(r.warning)
        XCTAssertTrue(r.warning!.contains("aaa"))
        XCTAssertTrue(r.warning!.contains("bbb"))
    }

    func testDisabledPluginSkipped() {
        let disabled = installed("disabled", extensions: ["x"], priority: 10, enabled: false)
        let enabled = installed("enabled", extensions: ["x"])
        XCTAssertEqual(Matcher.pick(from: [disabled, enabled], ext: "x", uti: nil).plugin?.manifest.id, "enabled")
        XCTAssertNil(Matcher.pick(from: [disabled], ext: "x", uti: nil).plugin)
    }

    func testUnknownFileIsNil() {
        let p = installed("p", extensions: ["geojson"], utis: ["public.geojson"])
        let r = Matcher.pick(from: [p], ext: "csv", uti: "public.comma-separated-values-text")
        XCTAssertNil(r.plugin)
        XCTAssertNil(r.warning)
        XCTAssertNil(Matcher.pick(from: [p], ext: "", uti: nil).plugin)
        XCTAssertNil(Matcher.pick(from: [], ext: "geojson", uti: "public.geojson").plugin)
    }

    func testIndexScanAndDisabled() throws {
        let tmp = TempDir()
        tmp.plugin("geojson", extensions: ["geojson"])
        tmp.plugin("broken", extraJSON: ", \"version\": \"nope\"")
        tmp.plugin("renamed")
        try FileManager.default.moveItem(at: tmp.url.appendingPathComponent("renamed"), to: tmp.url.appendingPathComponent("other-name"))
        tmp.write("not-a-dir.txt", "x")
        try "[\"geojson\"]".write(to: tmp.url.appendingPathComponent("disabled.json"), atomically: true, encoding: .utf8)

        let index = PluginIndex.scan(pluginsDir: tmp.url, disabled: PluginIndex.readDisabled(from: tmp.url.appendingPathComponent("disabled.json")))
        XCTAssertEqual(index.plugins.map(\.manifest.id), ["geojson"])
        XCTAssertEqual(index.plugins[0].enabled, false)
        XCTAssertEqual(index.warnings.count, 2, "\(index.warnings)")
        XCTAssertTrue(index.warnings.contains { $0.hasPrefix("broken:") })
        XCTAssertTrue(index.warnings.contains { $0.hasPrefix("other-name:") })
        XCTAssertNil(index.pick(ext: "geojson", uti: nil).plugin, "disabled plugin must not be picked")
    }

    func testIndexMissingDirectory() {
        let index = PluginIndex.scan(pluginsDir: URL(fileURLWithPath: "/nonexistent/spacebar"), disabled: [])
        XCTAssertTrue(index.plugins.isEmpty)
        XCTAssertEqual(index.warnings.count, 1)
    }

    func testDisabledRoundTrip() throws {
        let tmp = TempDir()
        let file = tmp.url.appendingPathComponent("disabled.json")
        XCTAssertEqual(PluginIndex.readDisabled(from: file), [])
        try PluginIndex.writeDisabled(["b", "a"], to: file)
        XCTAssertEqual(PluginIndex.readDisabled(from: file), ["a", "b"])
        tmp.write("disabled.json", "garbage")
        XCTAssertEqual(PluginIndex.readDisabled(from: file), [])
    }
}
