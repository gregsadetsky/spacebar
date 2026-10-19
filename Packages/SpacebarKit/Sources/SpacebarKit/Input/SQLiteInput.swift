import Foundation

/// placeholder until step 6; keeps InputLoader exhaustive
public enum SQLiteInput: InputProvider {
    public static func load(url: URL, manifest: Manifest) throws -> InputPayload {
        throw InputError.sqlite("not implemented yet")
    }
}
