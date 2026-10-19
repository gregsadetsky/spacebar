import Foundation

/// Where plugins live.
///
/// v0.1 uses the quick look extension's own sandbox container. the main app is
/// not sandboxed, so it writes straight into that container; the extension
/// reads its own home. measured on macos 15.7: a first read from an app group
/// container costs 1.0 to 1.5 s in every fresh extension process, a read from
/// the extension's own container costs 0 ms. see NOTES.md.
///
/// `strategy` is the one-line switch back to an app group container.
public enum Paths {
    public enum Strategy { case extensionContainer, appGroup }
    public static let strategy: Strategy = .extensionContainer

    public static var root: URL {
        switch strategy {
        case .extensionContainer:
            return extensionContainerData.appendingPathComponent("Library/Application Support/Spacebar", isDirectory: true)
        case .appGroup:
            if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Host.appGroup) {
                return group
            }
            return realHome.appendingPathComponent("Library/Group Containers/\(Host.appGroup)", isDirectory: true)
        }
    }

    public static var pluginsDir: URL { root.appendingPathComponent("Plugins", isDirectory: true) }
    public static var indexFile: URL { root.appendingPathComponent("plugins-index.json") }
    public static var disabledFile: URL { root.appendingPathComponent("disabled.json") }
    public static var markerFile: URL { root.appendingPathComponent("marker.txt") }

    /// true when running inside an app sandbox (NSHomeDirectory points into a container)
    public static var isSandboxed: Bool {
        NSHomeDirectory().contains("/Library/Containers/")
    }

    /// the user's actual home, even from inside a sandbox
    public static var realHome: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    /// `~/Library/Containers/<extension id>/Data`, from either process
    public static var extensionContainerData: URL {
        if isSandboxed {
            return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        }
        return realHome.appendingPathComponent("Library/Containers/\(Host.extensionBundleID)/Data", isDirectory: true)
    }

    @discardableResult
    public static func ensureDirectories() throws -> URL {
        try FileManager.default.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
        return root
    }
}
