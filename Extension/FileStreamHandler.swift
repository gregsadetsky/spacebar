import Foundation
import WebKit
import SpacebarKit
import os

/// serves the previewed file to the plugin page as `spacebar-file:///current`
/// with http range support, so media elements can seek and nothing has to be
/// base64'd into the page. one instance per preview; reads happen off the
/// main thread, WKURLSchemeTask calls happen on it.
final class FileStreamHandler: NSObject, WKURLSchemeHandler {
    private let fileURL: URL
    private let size: Int
    private let mimeType: String
    private let chunk = 512 * 1024
    private let lock = NSLock()
    private var stopped = Set<ObjectIdentifier>()
    private let log = Logger(subsystem: Host.logSubsystem, category: "stream")

    init(file: FileInfo) {
        fileURL = file.url
        size = file.size
        mimeType = StreamInput.mimeType(for: file)
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, url.path == StreamInput.currentFileURL.path else {
            task.didFailWithError(NSError(domain: Host.logSubsystem, code: 404, userInfo: [NSLocalizedDescriptionKey: "not found"]))
            return
        }
        let range = ByteRange.parse(task.request.value(forHTTPHeaderField: "Range"), size: size)
        let start = range?.start ?? 0
        let end = range?.end ?? max(size - 1, 0)
        let length = size == 0 ? 0 : end - start + 1
        var headers = [
            "Content-Type": mimeType,
            "Accept-Ranges": "bytes",
            "Content-Length": String(length),
            "Cache-Control": "no-store",
            // the page's origin is file://, this url is another scheme: media
            // elements don't care but fetch() needs cors headers to read it
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Expose-Headers": "Content-Length, Content-Range, Accept-Ranges",
        ]
        if range != nil { headers["Content-Range"] = "bytes \(start)-\(end)/\(size)" }
        guard let response = HTTPURLResponse(url: url, statusCode: range != nil ? 206 : 200, httpVersion: "HTTP/1.1", headerFields: headers) else { return }
        task.didReceive(response)
        if length == 0 { task.didFinish(); return }

        let id = ObjectIdentifier(task)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let handle = try FileHandle(forReadingFrom: self.fileURL)
                defer { try? handle.close() }
                try handle.seek(toOffset: UInt64(start))
                var remaining = length
                while remaining > 0 {
                    if self.isStopped(id) { return }
                    let data = try handle.read(upToCount: min(self.chunk, remaining)) ?? Data()
                    if data.isEmpty { break }
                    remaining -= data.count
                    DispatchQueue.main.sync { if !self.isStopped(id) { task.didReceive(data) } }
                }
                DispatchQueue.main.sync { if !self.isStopped(id) { task.didFinish() } }
            } catch {
                self.log.error("stream read failed: \(error.localizedDescription, privacy: .public)")
                DispatchQueue.main.sync { if !self.isStopped(id) { task.didFailWithError(error) } }
            }
            self.forget(id)
        }
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        lock.lock(); stopped.insert(ObjectIdentifier(task)); lock.unlock()
    }

    private func isStopped(_ id: ObjectIdentifier) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped.contains(id)
    }

    private func forget(_ id: ObjectIdentifier) {
        lock.lock(); stopped.remove(id); lock.unlock()
    }
}
