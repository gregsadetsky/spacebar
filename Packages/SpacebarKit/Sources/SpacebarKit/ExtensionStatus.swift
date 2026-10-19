import Foundation

/// is the quick look extension registered with pluginkit, and enabled?
public enum ExtensionStatus: Equatable, Sendable {
    case enabled
    case disabled
    case notRegistered
    case unknown(String)

    public var label: String {
        switch self {
        case .enabled: return "Registered and enabled"
        case .disabled: return "Registered but switched off"
        case .notRegistered: return "Not registered"
        case .unknown(let m): return "Unknown (\(m))"
        }
    }

    /// parses `pluginkit -m -i <id>` output. each line starts with an election
    /// tag: "+" the user switched it on, "-" switched off, "!" on for debugging,
    /// "=" superseded by another copy, "?" unknown. no tag at all (the line
    /// starts with spaces) means no election yet, which on macos 15 runs the
    /// extension just fine, so it counts as enabled. empty = not registered.
    public static func parse(_ output: String) -> ExtensionStatus {
        guard let raw = output.split(separator: "\n").first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return .notRegistered }
        let line = String(raw)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("(no matches)") { return .notRegistered }
        if line.hasPrefix(" ") || line.hasPrefix("\t") { return .enabled }   // no election tag
        switch trimmed.first {
        case "+", "!": return .enabled
        case "-": return .disabled
        case "=": return .unknown("superseded by another copy of the extension")
        default: return .unknown(trimmed)
        }
    }

    public static func query(bundleID: String = Host.extensionBundleID) -> ExtensionStatus {
        parse(Shell.run("/usr/bin/pluginkit", ["-m", "-i", bundleID]).output)
    }

    @discardableResult
    public static func enable(bundleID: String = Host.extensionBundleID) -> Bool {
        Shell.run("/usr/bin/pluginkit", ["-e", "use", "-i", bundleID]).status == 0
    }

    public static func resetQuickLook() {
        _ = Shell.run("/usr/bin/qlmanage", ["-r"])
        _ = Shell.run("/usr/bin/qlmanage", ["-r", "cache"])
    }

    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.quicklook.preview")!
}

public enum Shell {
    public struct Result { public let status: Int32; public let output: String }

    public static func run(_ path: String, _ args: [String]) -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return Result(status: -1, output: "\(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return Result(status: p.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}
