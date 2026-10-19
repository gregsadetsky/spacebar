import Foundation

private final class BookXML: NSObject, XMLParserDelegate {
    final class Node {
        let name: String
        let attributes: [String: String]
        var children: [Node] = []
        var segments: [Any] = []
        init(_ name: String, _ attributes: [String: String]) { self.name = name; self.attributes = attributes }
        var rawContent: String { segments.map { ($0 as? String) ?? ($0 as? Node)?.rawContent ?? "" }.joined() }
        var content: String { rawContent.trimmingCharacters(in: .whitespacesAndNewlines) }
        func all(_ name: String) -> [Node] { (self.name == name ? [self] : []) + children.flatMap { $0.all(name) } }
    }
    var stack: [Node] = [], root: Node?, count = 0
    var failure: String?
    static func read(_ data: Data) throws -> Node {
        let delegate = BookXML(), parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        guard parser.parse(), delegate.failure == nil, let root = delegate.root else {
            throw InputError.epub(delegate.failure ?? "invalid book metadata XML")
        }
        return root
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        count += 1
        guard stack.count < 64, count <= 20_000 else { failure = "metadata is too complex"; parser.abortParsing(); return }
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        let node = Node(name, attributeDict)
        if let parent = stack.last { parent.children.append(node); parent.segments.append(node) } else { root = node }
        stack.append(node)
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.segments.append(string) }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { stack.last?.segments.append(String(decoding: CDATABlock, as: UTF8.self)) }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { if !stack.isEmpty { stack.removeLast() } }
    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) { failure = "XML entities are not supported"; parser.abortParsing() }
    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) { failure = "XML entities are not supported"; parser.abortParsing() }
}

public enum EPUBInput: InputProvider {
    /// Resolve EPUB hrefs inside their ZIP container, including parent references.
    static func resolve(_ href: String, relativeTo file: String) -> String? {
        guard let decoded = href.components(separatedBy: "#")[0].components(separatedBy: "?")[0].removingPercentEncoding,
              !decoded.isEmpty, !decoded.hasPrefix("/"), !decoded.contains(":"), !decoded.contains("\\"), !decoded.contains("\0") else { return nil }
        var parts = file.split(separator: "/").dropLast().map(String.init)
        for part in decoded.split(separator: "/") {
            if part == ".." { guard !parts.isEmpty else { return nil }; parts.removeLast() }
            else if part != "." { parts.append(String(part)) }
        }
        return parts.joined(separator: "/")
    }
    public static func load(url: URL, manifest: Manifest) throws -> InputPayload {
        try InputLoader.checkSize(FileInfo(url: url), manifest: manifest)
        let deadline = Date().addingTimeInterval(4)
        let containerPath = "META-INF/container.xml"
        let first = try ArchiveReader.files(url, paths: [containerPath], deadline: deadline)
        guard let data = first[containerPath] else { throw InputError.epub("missing META-INF/container.xml") }
        let container = try BookXML.read(data)
        guard let declared = container.all("rootfile").first?.attributes["full-path"]?.removingPercentEncoding, let packagePath = ArchiveReader.safePath(declared) else {
            throw InputError.epub("missing package document")
        }
        let packages = try ArchiveReader.files(url, paths: [packagePath], deadline: deadline)
        guard let packageData = packages[packagePath] else { throw InputError.epub("package document is missing or too large") }
        let package = try BookXML.read(packageData)
        guard package.name == "package" else { throw InputError.epub("invalid package document") }
        let metadata = package.all("metadata").first
        let title = metadata?.all("title").first?.content ?? url.deletingPathExtension().lastPathComponent
        let authors = metadata?.all("creator").map(\.content) ?? []
        let language = metadata?.all("language").first?.content ?? ""
        var items: [String: BookXML.Node] = [:], paths: [String: String] = [:]
        for item in package.all("manifest").first?.children ?? [] {
            guard item.name == "item", let id = item.attributes["id"], let href = item.attributes["href"], let path = resolve(href, relativeTo: packagePath) else { continue }
            items[id] = item; paths[id] = path
        }
        let spineNode = package.all("spine").first
        let spine = (spineNode?.children ?? []).filter { $0.name == "itemref" && $0.attributes["linear"] != "no" }.compactMap { $0.attributes["idref"] }.filter { id in
            ["application/xhtml+xml", "text/html"].contains(items[id]?.attributes["media-type"] ?? "")
        }
        guard !spine.isEmpty else { throw InputError.epub("book has no readable HTML chapters") }
        let excerpt = Array(spine.prefix(12))
        let navID = items.keys.sorted().first { (items[$0]?.attributes["properties"] ?? "").split(separator: " ").contains("nav") }
        let ncxID = spineNode?.attributes["toc"]
        let coverID = items.keys.sorted().first { (items[$0]?.attributes["properties"] ?? "").split(separator: " ").contains("cover-image") }
            ?? metadata?.all("meta").first(where: { $0.attributes["name"] == "cover" })?.attributes["content"]
        var requested = Set(excerpt.compactMap { paths[$0] })
        for id in [navID, ncxID].compactMap({ $0 }) { if let path = paths[id] { requested.insert(path) } }
        let documents = try ArchiveReader.files(url, paths: requested, perFile: 1_048_576, total: 6_291_456, deadline: deadline)
        var toc: [[String: Any]] = []
        if let id = navID, let path = paths[id], let data = documents[path], let nav = try? BookXML.read(data) {
            let navigation = nav.all("nav").first { ($0.attributes["epub:type"] ?? "").split(separator: " ").contains("toc") } ?? nav.all("nav").first
            for link in navigation?.all("a") ?? [] {
                if let href = link.attributes["href"], let target = resolve(href, relativeTo: path) { toc.append(["title": String(link.content.prefix(300)), "path": target]) }
                if toc.count >= 1000 { break }
            }
        }
        if toc.isEmpty, let id = ncxID, let path = paths[id], let data = documents[path], let ncx = try? BookXML.read(data) {
            for point in ncx.all("navPoint").prefix(1000) {
                if let src = point.children.first(where: { $0.name == "content" })?.attributes["src"], let target = resolve(src, relativeTo: path) {
                    toc.append(["title": String((point.children.first(where: { $0.name == "navLabel" })?.content ?? "Chapter").prefix(300)), "path": target])
                }
            }
        }
        var chapters: [[String: Any]] = [], imagePaths = Set<String>()
        for (index, id) in excerpt.enumerated() {
            guard let path = paths[id], let data = documents[path] else { continue }
            // XMLParser honors the encoding declaration. XHTML bodies are retained
            // as source here and sanitized by the plugin before entering the DOM.
            let source = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? ""
            if source.isEmpty { continue }
            let name = toc.first { $0["path"] as? String == path }?["title"] as? String ?? "Chapter \(index + 1)"
            chapters.append(["title": name, "path": path, "html": source])
            if let xml = try? BookXML.read(data) {
                for image in xml.all("img") {
                    if let src = image.attributes["src"], let target = resolve(src, relativeTo: path) { imagePaths.insert(target) }
                }
            }
        }
        guard !chapters.isEmpty else { throw InputError.epub("chapters are encrypted, missing, or exceed the preview limit") }
        if let id = coverID, let path = paths[id] { imagePaths.insert(path) }
        let imageTypes = ["image/jpeg", "image/png", "image/gif", "image/webp"]
        var allowedImages: [String: String] = [:]
        for id in items.keys.sorted() {
            if let path = paths[id], imagePaths.contains(path), let mime = items[id]?.attributes["media-type"], imageTypes.contains(mime) { allowedImages[path] = mime }
        }
        // Prefer the cover when selecting a bounded set of illustrations.
        let coverPath = coverID.flatMap { paths[$0] }
        let selectedImages = Set(allowedImages.keys.sorted { a, b in
            if a == b { return false }
            if a == coverPath { return true }; if b == coverPath { return false }; return a < b
        }.prefix(64))
        let imageData = selectedImages.isEmpty ? [:] : try ArchiveReader.files(url, paths: selectedImages, perFile: 2_097_152, total: 8_388_608, deadline: deadline)
        var resources: [String: String] = [:]
        for (path, bytes) in imageData { resources[path] = "data:\(allowedImages[path]!);base64,\(bytes.base64EncodedString())" }
        let cover = coverID.flatMap { paths[$0] }.flatMap { resources[$0] } ?? ""
        if toc.isEmpty { toc = spine.prefix(1000).enumerated().compactMap { index, id in paths[id].map { ["title": "Chapter \(index + 1)", "path": $0] } } }
        return .epub(["title": title, "authors": authors, "language": language, "cover": cover, "toc": toc,
                      "chapters": chapters, "resources": resources, "totalChapters": spine.count,
                      "truncated": chapters.count < spine.count || imageData.count < allowedImages.count])
    }
}
