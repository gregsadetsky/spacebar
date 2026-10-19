import Foundation

/// builds the javascript injected into the plugin's page at document start.
/// everything the plugin sees lives on `window.spacebar`; messages back to the
/// host go through `webkit.messageHandlers.host` as `{type, message}`.
public enum Bridge {
    public static let messageHandlerName = "host"

    public enum Theme: String, Sendable { case light, dark }

    public static func script(file: FileInfo, manifest: Manifest, payload: InputPayload, theme: Theme) throws -> String {
        let data: String
        switch payload {
        case .text(let s): data = try jsLiteral(s)
        case .bytes(let d): data = try jsLiteral(d.base64EncodedString())
        // JSON.parse preserves literal dictionary keys such as __proto__.
        case .json(let obj), .plist(let obj): data = "JSON.parse(\(try jsLiteral(jsLiteral(obj))))"
        case .sqlite(let obj): data = try jsLiteral(obj)
        case .archive(let obj), .epub(let obj): data = "JSON.parse(\(try jsLiteral(jsLiteral(obj))))"
        }
        return """
        (function () {
          var handler = (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.host) || null;
          function send(type, message) {
            if (!handler) return;
            try { handler.postMessage({ type: type, message: message == null ? null : String(message) }); } catch (e) {}
          }
          window.spacebar = {
            host: { version: \(try jsLiteral(Host.version)) },
            plugin: { id: \(try jsLiteral(manifest.id)), name: \(try jsLiteral(manifest.name)), version: \(try jsLiteral(manifest.version)) },
            file: \(try jsLiteral(file.jsonObject)),
            input: \(try jsLiteral(manifest.input.rawValue)),
            data: \(data),
            theme: \(try jsLiteral(theme.rawValue)),
            done: function () { send("done"); },
            fail: function (message) { send("fail", message); },
            log: function (message) { send("log", message); }
          };
          window.addEventListener("error", function (e) {
            send("fail", "uncaught error: " + (e && e.message ? e.message : e));
          });
          window.addEventListener("unhandledrejection", function (e) {
            send("fail", "unhandled rejection: " + (e && e.reason ? e.reason : e));
          });
          ["log", "warn", "error", "info"].forEach(function (level) {
            var original = console[level];
            console[level] = function () {
              send("log", "[" + level + "] " + Array.prototype.map.call(arguments, function (a) {
                try { return typeof a === "string" ? a : JSON.stringify(a); } catch (e) { return String(a); }
              }).join(" "));
              if (original) { try { original.apply(console, arguments); } catch (e) {} }
            };
          });
        })();
        """
    }

    /// JSON-serialize any JSONSerialization-compatible value into a javascript
    /// expression that is safe to paste into a script: `</` and the U+2028 /
    /// U+2029 line terminators are escaped.
    public static func jsLiteral(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys])
        var s = String(decoding: data, as: UTF8.self)
        s = s.replacingOccurrences(of: "</", with: "<\\/")
        s = s.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
        s = s.replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return s
    }
}
