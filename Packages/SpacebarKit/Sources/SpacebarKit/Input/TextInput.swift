import Foundation

/// UTF-8, or UTF-16 with a BOM (common in subtitle exports).
public enum TextInput: InputProvider {
    public static func load(url: URL, manifest: Manifest) throws -> InputPayload {
        let data = try InputLoader.readData(url)
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let text = String(data: data, encoding: .utf16) { return .text(text) }
        return .text(String(decoding: data, as: UTF8.self))
    }
}
