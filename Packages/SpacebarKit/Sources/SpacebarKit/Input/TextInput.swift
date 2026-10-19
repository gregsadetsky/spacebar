import Foundation

/// utf-8 text; invalid sequences become U+FFFD rather than failing
public enum TextInput: InputProvider {
    public static func load(url: URL, manifest: Manifest) throws -> InputPayload {
        let data = try InputLoader.readData(url)
        return .text(String(decoding: data, as: UTF8.self))
    }
}
