import AppKit
import QuickLookUI
import SpacebarKit
import os

let log = Logger(subsystem: Host.logSubsystem, category: "extension")

final class PreviewViewController: NSViewController, QLPreviewingController {
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        log.info("scaffold preview requested for \(url.lastPathComponent, privacy: .public)")
        let marker = Paths.markerFile
        let t0 = Date()
        let text: String
        if let contents = try? String(contentsOf: marker, encoding: .utf8) {
            log.info("container read ok in \(Int(Date().timeIntervalSince(t0) * 1000))ms: \(marker.path, privacy: .public)")
            text = "container ok: \(contents)"
        } else {
            log.error("container read FAILED: \(marker.path, privacy: .public)")
            text = "container read failed: \(marker.path)"
        }
        let label = NSTextField(wrappingLabelWithString: "Spacebar scaffold: \(url.lastPathComponent)\n\(text)")
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -40),
        ])
        handler(nil)
    }
}
