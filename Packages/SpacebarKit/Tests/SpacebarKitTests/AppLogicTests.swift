import XCTest
@testable import SpacebarKit

final class AppLogicTests: XCTestCase {
    func testExtensionStatusParse() {
        XCTAssertEqual(ExtensionStatus.parse("+    io.spacebar.app.QuickLook(0.1.0)\tUUID\t2026-10-19 02:00:09 +0000\t/path\n (1 plug-in)\n"), .enabled)
        XCTAssertEqual(ExtensionStatus.parse("-    io.spacebar.app.QuickLook(0.1.0)"), .disabled)
        XCTAssertEqual(ExtensionStatus.parse(""), .notRegistered)
        XCTAssertEqual(ExtensionStatus.parse("  (no matches)\n"), .notRegistered)
        XCTAssertEqual(ExtensionStatus.parse("!    io.spacebar.app.QuickLook"), .unknown("!    io.spacebar.app.QuickLook"))
    }

    func testSetEnabledRoundTrip() throws {
        let tmp = TempDir()
        let file = tmp.url.appendingPathComponent("disabled.json")
        try PluginIndex.setEnabled("geojson", false, disabledFile: file)
        XCTAssertEqual(PluginIndex.readDisabled(from: file), ["geojson"])
        try PluginIndex.setEnabled("sqlite", false, disabledFile: file)
        try PluginIndex.setEnabled("geojson", true, disabledFile: file)
        XCTAssertEqual(PluginIndex.readDisabled(from: file), ["sqlite"])
    }

    func testSyncBundledNeverOverwritesUserPlugin() throws {
        let tmp = TempDir()
        let bundle = tmp.url.appendingPathComponent("bundle")
        let plugins = tmp.url.appendingPathComponent("plugins")
        let b = TempDir(); _ = b
        // bundled geojson 0.2.0
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("geojson"), withIntermediateDirectories: true)
        try "{\"id\":\"geojson\",\"name\":\"G\",\"version\":\"0.2.0\",\"matches\":{\"extensions\":[\"geojson\"]},\"input\":\"text\"}".write(to: bundle.appendingPathComponent("geojson/plugin.json"), atomically: true, encoding: .utf8)
        try "bundled".write(to: bundle.appendingPathComponent("geojson/index.html"), atomically: true, encoding: .utf8)

        // first sync installs it with the bundled marker
        XCTAssertEqual(try PluginInstaller.syncBundled(from: bundle, to: plugins), ["geojson"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: plugins.appendingPathComponent("geojson/.bundled").path))
        let index = PluginIndex.scan(pluginsDir: plugins, disabled: [])
        XCTAssertEqual(index.plugins.first?.source, .bundled)

        // user replaces it with their own copy (no marker): sync must leave it alone
        try FileManager.default.removeItem(at: plugins.appendingPathComponent("geojson"))
        let user = tmp.url.appendingPathComponent("user-geojson")
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        try "{\"id\":\"geojson\",\"name\":\"Mine\",\"version\":\"0.0.1\",\"matches\":{\"extensions\":[\"geojson\"]},\"input\":\"text\"}".write(to: user.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)
        try "mine".write(to: user.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        _ = try PluginInstaller.installUserPlugin(from: user, to: plugins)
        XCTAssertEqual(try PluginInstaller.syncBundled(from: bundle, to: plugins), [])
        XCTAssertEqual(try String(contentsOf: plugins.appendingPathComponent("geojson/index.html"), encoding: .utf8), "mine")
        XCTAssertEqual(PluginIndex.scan(pluginsDir: plugins, disabled: []).plugins.first?.source, .user)

        // installing again under the same id is refused
        XCTAssertThrowsError(try PluginInstaller.installUserPlugin(from: user, to: plugins)) { error in
            guard case .alreadyInstalled("geojson") = error as? PluginInstaller.InstallError else { return XCTFail("\(error)") }
        }
        // an invalid folder is refused with the manifest error
        let bad = tmp.url.appendingPathComponent("bad")
        try FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
        try "{".write(to: bad.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try PluginInstaller.installUserPlugin(from: bad, to: plugins)) { error in
            guard case .invalid = error as? PluginInstaller.InstallError else { return XCTFail("\(error)") }
        }
        // remove
        try PluginInstaller.remove(id: "geojson", from: plugins)
        XCTAssertTrue(PluginIndex.scan(pluginsDir: plugins, disabled: []).plugins.isEmpty)
    }

    func testSyncBundledRefreshesBundledCopy() throws {
        let tmp = TempDir()
        let bundle = tmp.url.appendingPathComponent("bundle")
        let plugins = tmp.url.appendingPathComponent("plugins")
        try FileManager.default.createDirectory(at: bundle.appendingPathComponent("p"), withIntermediateDirectories: true)
        try "{\"id\":\"p\",\"name\":\"P\",\"version\":\"0.1.0\",\"matches\":{\"extensions\":[\"p\"]},\"input\":\"text\"}".write(to: bundle.appendingPathComponent("p/plugin.json"), atomically: true, encoding: .utf8)
        try "v1".write(to: bundle.appendingPathComponent("p/index.html"), atomically: true, encoding: .utf8)
        _ = try PluginInstaller.syncBundled(from: bundle, to: plugins)
        try "v2".write(to: bundle.appendingPathComponent("p/index.html"), atomically: true, encoding: .utf8)
        XCTAssertEqual(try PluginInstaller.syncBundled(from: bundle, to: plugins), ["p"], "same version, still bundled: refreshed")
        XCTAssertEqual(try String(contentsOf: plugins.appendingPathComponent("p/index.html"), encoding: .utf8), "v2")

        // the app stops shipping p: the bundled copy goes away, a user plugin next to it stays
        let user = tmp.url.appendingPathComponent("u")
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        try "{\"id\":\"u\",\"name\":\"U\",\"version\":\"0.1.0\",\"matches\":{\"extensions\":[\"u\"]},\"input\":\"text\"}".write(to: user.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)
        try "u".write(to: user.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        _ = try PluginInstaller.installUserPlugin(from: user, to: plugins)
        try FileManager.default.removeItem(at: bundle.appendingPathComponent("p"))
        XCTAssertEqual(try PluginInstaller.syncBundled(from: bundle, to: plugins), [])
        XCTAssertEqual(PluginIndex.scan(pluginsDir: plugins, disabled: []).plugins.map(\.manifest.id), ["u"])
    }
}
