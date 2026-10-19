import Foundation

public enum JSONInput: InputProvider {
    public static func load(url: URL, manifest: Manifest) throws -> InputPayload {
        let data = try InputLoader.readData(url)
        do {
            return .json(try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
        } catch {
            let ns = error as NSError
            let detail = (ns.userInfo[NSDebugDescriptionErrorKey] as? String) ?? ns.localizedDescription
            throw InputError.invalidJSON(detail)
        }
    }
}
