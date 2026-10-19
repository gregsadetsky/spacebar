// spacebar-cli: tiny helper for plugin authors and the browser harness.
//   spacebar-cli dump <file> [text|bytes|json|plist|sqlite|archive|epub]
//   spacebar-cli match <file>                            which installed plugin would preview this file
import Foundation
import SpacebarKit

func usage() -> Never {
    FileHandle.standardError.write(Data("usage: spacebar-cli dump <file> [text|bytes|json|plist|sqlite|archive|epub]\n       spacebar-cli match <file>\n".utf8))
    exit(2)
}

let args = CommandLine.arguments.dropFirst()
guard let command = args.first, let path = args.dropFirst().first else { usage() }
let url = URL(fileURLWithPath: path)
let file = FileInfo(url: url)

do {
    switch command {
    case "dump":
        let kind: InputKind
        if let raw = args.dropFirst(2).first {
            guard let k = InputKind(rawValue: raw) else { usage() }
            kind = k
        } else {
            switch file.ext {
            case "sqlite", "sqlite3", "db": kind = .sqlite
            case "plist": kind = .plist
            case "json": kind = .json
            case "epub": kind = .epub
            case "zip", "tar", "tgz", "gz", "bz2", "tbz", "tbz2", "xz", "txz", "7z", "rar": kind = .archive
            default: kind = .text
            }
        }
        let manifest = Manifest(id: "cli", name: "cli", version: "0.0.0", matches: .init(extensions: [file.ext]), input: kind, maxFileSize: .max)
        let payload = try InputLoader.load(kind: kind, url: url, manifest: manifest)
        let value: Any
        switch payload {
        case .text(let s): value = s
        case .bytes(let d): value = d.base64EncodedString()
        case .json(let o): value = o
        case .plist(let o): value = o
        case .sqlite(let o): value = o
        case .archive(let o), .epub(let o): value = o
        }
        let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    case "match":
        let index = PluginIndex.scanDefault()
        for w in index.warnings { print("warning: \(w)") }
        let r = index.pick(ext: file.ext, uti: file.uti)
        if let w = r.warning { print("warning: \(w)") }
        if let p = r.plugin { print("\(p.manifest.id) \(p.manifest.version) (\(p.source.rawValue)) \(p.directory.path)") }
        else { print("no plugin for .\(file.ext) / \(file.uti ?? "no uti") among \(index.plugins.count) installed"); exit(1) }
    default:
        usage()
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
