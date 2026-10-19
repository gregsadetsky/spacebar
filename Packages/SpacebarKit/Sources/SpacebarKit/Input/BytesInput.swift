import Foundation

public enum BytesInput: InputProvider {
    public static func load(url: URL, manifest: Manifest) throws -> InputPayload {
        .bytes(try InputLoader.readData(url))
    }
}
