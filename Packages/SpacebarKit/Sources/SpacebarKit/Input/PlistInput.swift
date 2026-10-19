import Foundation
import CoreFoundation

/// Read property lists without unarchiving objects or modifying the source file.
/// See PLUGINS.md for the JSON representation of plist-only values.
public enum PlistInput: InputProvider {
    public static func load(url: URL, manifest: Manifest) throws -> InputPayload {
        try InputLoader.checkSize(FileInfo(url: url), manifest: manifest)
        let data = try InputLoader.readData(url)
        do {
            var format = PropertyListSerialization.PropertyListFormat.xml
            let value = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
            // Foundation can reinterpret a broken binary header as an OpenStep string.
            if data.starts(with: Data("bplist".utf8)), format != .binary {
                throw InputError.invalidPlist("invalid binary property list")
            }
            var normalizer = Normalizer()
            return .plist(try normalizer.convert(value))
        } catch let error as InputError {
            throw error
        } catch {
            throw InputError.invalidPlist(error.localizedDescription)
        }
    }

    private struct Normalizer {
        // Binary plists can share objects: a small input can expand dramatically.
        var remainingNodes = 100_000
        var remainingBytes = 32 * 1024 * 1024
        let dateFormatter: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()

        mutating func string(_ value: String) throws -> String {
            remainingBytes -= value.utf8.count
            guard remainingBytes >= 0 else {
                throw InputError.invalidPlist("expanded contents exceed the 32 MB preview limit")
            }
            return value
        }

        mutating func convert(_ value: Any, depth: Int = 0) throws -> Any {
            remainingNodes -= 1
            guard depth <= 128, remainingNodes >= 0 else {
                throw InputError.invalidPlist("contents exceed the preview limit (128 levels or 100,000 values)")
            }
            if let value = value as? String { return try string(value) }
            if let value = value as? Date { return dateFormatter.string(from: value) }
            if let value = value as? Data {
                return ["data": try string(value.base64EncodedString()), "bytes": value.count]
            }
            if let value = value as? NSNumber {
                if CFGetTypeID(value) == CFBooleanGetTypeID() { return value }
                let type = String(cString: value.objCType)
                if type == "f" || type == "d" {
                    if value.doubleValue.isNaN { return "NaN" }
                    if !value.doubleValue.isFinite { return value.doubleValue < 0 ? "-Infinity" : "Infinity" }
                } else if value.compare(NSNumber(value: 9_007_199_254_740_991 as Int64)) == .orderedDescending
                            || value.compare(NSNumber(value: -9_007_199_254_740_991 as Int64)) == .orderedAscending {
                    // Keep all digits when the bridge passes through JavaScript.
                    return value.stringValue
                }
                return value
            }
            if value is NSNull { return NSNull() }
            if let value = value as? [String: Any] {
                var result: [String: Any] = [:]
                for (key, child) in value {
                    result[try string(key)] = try convert(child, depth: depth + 1)
                }
                return result
            }
            if let value = value as? [Any] {
                return try value.map { try convert($0, depth: depth + 1) }
            }

            // Foundation represents NSKeyedArchiver UID references with a private
            // type. Its public XML serializer exposes them as {"CF$UID": n}.
            // Read that representation without private APIs or NSKeyedUnarchiver.
            let xml = try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
            let document = try XMLDocument(data: xml, options: [.nodeLoadExternalEntitiesNever])
            if let uid = try document.nodes(forXPath: "/plist/dict[key='CF$UID']/integer").first?.stringValue,
               let number = UInt64(uid) {
                return ["CF$UID": try convert(NSNumber(value: number), depth: depth + 1)]
            }
            throw InputError.invalidPlist("unsupported property list value")
        }
    }
}
