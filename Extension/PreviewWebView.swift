import AppKit
import WebKit
import SpacebarKit
import os

/// the view that actually runs a plugin: builds the payload, injects the
/// bridge, loads the plugin's entry page in an offline WKWebView, and swaps
/// to an error view on fail / timeout. shared by the extension and the app's
/// dev window.
final class PreviewWebView: NSView {
    enum Outcome: Equatable {
        case done
        case failed(String)
        case timedOut
        case hostError(String)

        var isSuccess: Bool { self == .done }
        var label: String {
            switch self {
            case .done: return "done"
            case .failed(let m): return "failed: \(m)"
            case .timedOut: return "timed out"
            case .hostError(let m): return "host error: \(m)"
            }
        }
    }

    var timeout: TimeInterval = 3
    var onLog: ((String) -> Void)?
    /// called exactly once per render
    var onFinish: ((Outcome) -> Void)?

    private(set) var webView: WKWebView?
    private var timeoutWork: DispatchWorkItem?
    private var finished = false
    private var pluginName = "plugin"
    private let errorBox = NSStackView()
    private let errorTitle = NSTextField(wrappingLabelWithString: "")
    private let errorMessage = NSTextField(wrappingLabelWithString: "")
    private let errorHint = NSTextField(wrappingLabelWithString: "Open Spacebar to manage plugins.")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        errorBox.orientation = .vertical
        errorBox.alignment = .centerX
        errorBox.spacing = 8
        errorBox.translatesAutoresizingMaskIntoConstraints = false
        errorTitle.font = .boldSystemFont(ofSize: 15)
        errorTitle.alignment = .center
        errorMessage.alignment = .center
        errorHint.textColor = .secondaryLabelColor
        errorHint.alignment = .center
        [errorTitle, errorMessage, errorHint].forEach { errorBox.addArrangedSubview($0) }
        addSubview(errorBox)
        NSLayoutConstraint.activate([
            errorBox.centerXAnchor.constraint(equalTo: centerXAnchor),
            errorBox.centerYAnchor.constraint(equalTo: centerYAnchor),
            errorBox.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -60),
        ])
        errorBox.isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    var theme: Bridge.Theme {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }

    func render(file: FileInfo, plugin: InstalledPlugin) {
        reset()
        pluginName = plugin.manifest.name
        do {
            try InputLoader.checkSize(file, manifest: plugin.manifest)
            let payload = try InputLoader.load(kind: plugin.manifest.input, url: file.url, manifest: plugin.manifest)
            let script = try Bridge.script(file: file, manifest: plugin.manifest, payload: payload, theme: theme)
            load(script: script, plugin: plugin)
        } catch let e as InputError {
            finish(.hostError(e.description), title: "\(plugin.manifest.name) can't preview this file", message: e.description)
        } catch {
            finish(.hostError("\(error)"), title: "\(plugin.manifest.name) can't preview this file", message: "\(error)")
        }
    }

    private func load(script: String, plugin: InstalledPlugin) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        controller.add(WeakMessageHandler(self), name: Bridge.messageHandlerName)
        config.userContentController = controller
        let web = WKWebView(frame: bounds, configuration: config)
        web.autoresizingMask = [.width, .height]
        web.navigationDelegate = self
        web.setValue(false, forKey: "drawsBackground")
        web.isHidden = true
        addSubview(web, positioned: .below, relativeTo: errorBox)
        webView = web

        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.finished else { return }
            self.finish(.timedOut, title: "\(self.pluginName) timed out", message: "The plugin did not call spacebar.done() within \(Int(self.timeout)) seconds.")
        }
        timeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
        web.loadFileURL(plugin.entryURL, allowingReadAccessTo: plugin.directory)
    }

    private func reset() {
        finished = false
        timeoutWork?.cancel()
        timeoutWork = nil
        webView?.removeFromSuperview()
        webView = nil
        errorBox.isHidden = true
    }

    private func finish(_ outcome: Outcome, title: String? = nil, message: String? = nil) {
        guard !finished else { return }
        finished = true
        timeoutWork?.cancel()
        timeoutWork = nil
        if outcome.isSuccess {
            webView?.isHidden = false
        } else {
            webView?.isHidden = true
            webView?.stopLoading()
            errorTitle.stringValue = title ?? "\(pluginName) failed"
            errorMessage.stringValue = message ?? outcome.label
            errorBox.isHidden = false
        }
        onFinish?(outcome)
    }

    fileprivate func handle(type: String, message: String?) {
        switch type {
        case "done": finish(.done)
        case "fail":
            let m = message ?? "spacebar.fail() called without a message"
            finish(.failed(m), title: "\(pluginName) failed", message: m)
        case "log": onLog?(message ?? "")
        default: onLog?("unknown message type \(type)")
        }
    }
}

extension PreviewWebView: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.hostError(error.localizedDescription), title: "\(pluginName) failed to load", message: error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.hostError(error.localizedDescription), title: "\(pluginName) failed to load", message: error.localizedDescription)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // plugins are offline: only file: urls inside the plugin folder load
        decisionHandler(navigationAction.request.url?.isFileURL == true ? .allow : .cancel)
    }
}

/// WKUserContentController retains its handlers strongly; break the cycle.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: PreviewWebView?
    init(_ target: PreviewWebView) { self.target = target }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        target?.handle(type: type, message: body["message"] as? String)
    }
}
