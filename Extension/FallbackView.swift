import AppKit
import UniformTypeIdentifiers
import SpacebarKit

/// what the panel shows when no plugin matches. macos 15 does not fall back
/// to its own preview once an extension has claimed a type (it shows the
/// generic icon with our error string), so we draw something useful ourselves:
/// plain text for text-like files, a short note otherwise.
enum FallbackView {
    static let textCap = 2 * 1024 * 1024

    static func make(for file: FileInfo, frame: NSRect) -> (NSView, String) {
        let isText = file.uti.flatMap { UTType($0) }?.conforms(to: .text) ?? false
        if isText, let text = readText(file.url) {
            return (textView(text, frame: frame), "text")
        }
        return (noteView(file, frame: frame), "note")
    }

    private static func readText(_ url: URL) -> String? {
        guard let handle = FileHandle(forReadingAtPath: url.path) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: textCap) else { return nil }
        var s = String(decoding: data, as: UTF8.self)
        if data.count >= textCap { s += "\n\n… (first 2 MB shown)" }
        return s
    }

    private static func textView(_ text: String, frame: NSRect) -> NSView {
        let scroll = NSScrollView(frame: frame)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        let tv = NSTextView(frame: scroll.bounds)
        tv.isEditable = false
        tv.isRichText = false
        tv.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.textContainerInset = NSSize(width: 10, height: 10)
        tv.autoresizingMask = [.width]
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.string = text
        scroll.documentView = tv
        return scroll
    }

    private static func noteView(_ file: FileInfo, frame: NSRect) -> NSView {
        let view = NSView(frame: frame)
        view.autoresizingMask = [.width, .height]
        let title = NSTextField(wrappingLabelWithString: "No Spacebar plugin for .\(file.ext) files")
        title.font = .boldSystemFont(ofSize: 15)
        title.alignment = .center
        let hint = NSTextField(wrappingLabelWithString: "Open Spacebar to install one, or write your own (see PLUGINS.md).")
        hint.textColor = .secondaryLabelColor
        hint.alignment = .center
        let stack = NSStackView(views: [title, hint])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -60),
        ])
        return view
    }
}
