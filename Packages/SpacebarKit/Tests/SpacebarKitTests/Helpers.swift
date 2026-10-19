import Foundation
import XCTest
@testable import SpacebarKit

/// a throwaway directory per test, removed on teardown
final class TempDir {
    let url: URL
    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacebar-tests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }

    @discardableResult
    func write(_ relative: String, _ contents: String) -> URL {
        let file = url.appendingPathComponent(relative)
        try! FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! contents.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    @discardableResult
    func write(_ relative: String, data: Data) -> URL {
        let file = url.appendingPathComponent(relative)
        try! FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! data.write(to: file)
        return file
    }

    /// writes a minimal valid plugin folder and returns its directory
    @discardableResult
    func plugin(_ id: String, extensions: [String] = ["geojson"], utis: [String] = [], priority: Int? = nil, entry: String = "index.html", extraJSON: String = "") -> URL {
        var json = """
        {"id": "\(id)", "name": "\(id)", "version": "1.0.0",
         "matches": {"extensions": \(jsonArray(extensions)), "utis": \(jsonArray(utis))},
         "input": "text", "entry": "\(entry)"
        """
        if let p = priority { json += ", \"priority\": \(p)" }
        json += extraJSON + "}"
        write("\(id)/plugin.json", json)
        write("\(id)/\(entry)", "<html></html>")
        return url.appendingPathComponent(id, isDirectory: true)
    }

    private func jsonArray(_ a: [String]) -> String {
        "[" + a.map { "\"\($0)\"" }.joined(separator: ",") + "]"
    }
}

func manifest(_ id: String, extensions: [String] = [], utis: [String] = [], priority: Int = 0, input: InputKind = .text) -> Manifest {
    Manifest(id: id, name: id, version: "1.0.0", matches: .init(extensions: extensions, utis: utis), input: input, priority: priority)
}

func installed(_ id: String, extensions: [String] = [], utis: [String] = [], priority: Int = 0, enabled: Bool = true) -> InstalledPlugin {
    InstalledPlugin(manifest: manifest(id, extensions: extensions, utis: utis, priority: priority),
                    directory: URL(fileURLWithPath: "/plugins/\(id)"), source: .user, enabled: enabled)
}
