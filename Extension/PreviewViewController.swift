import AppKit
import QuickLookUI
import os

let log = Logger(subsystem: "io.spacebar", category: "extension")

final class PreviewViewController: NSViewController, QLPreviewingController {
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        log.info("scaffold preview requested for \(url.lastPathComponent, privacy: .public)")
        let label = NSTextField(labelWithString: "Spacebar scaffold: \(url.lastPathComponent)")
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        handler(nil)
    }
}
