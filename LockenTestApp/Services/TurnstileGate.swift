import AppKit
import SwiftUI
import WebKit

/// Cloudflare Turnstile, the bot check in front of sign-in. Supabase verifies its token on sign-up, sign-in, email
/// codes and password reset (once CAPTCHA protection is switched on in the Supabase dashboard).
///
/// Off until a site key is set (`LockenTurnstileSiteKey` in Info.plist); with no key, `token()` returns nil and
/// nothing changes. The widget runs in its own web view, loaded with the site's address so Turnstile accepts it,
/// limited to Cloudflare's challenge pages. Most people pass without seeing anything; a suspicious request gets a
/// small puzzle in the sign-in card. Each token is used once, so every protected request asks for a fresh one.
@MainActor
final class TurnstileGate: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate {
    static let shared = TurnstileGate()

    /// True while Turnstile needs the person to click its checkbox (the sign-in card shows the widget).
    @Published private(set) var needsInteraction = false

    private static let pageOrigin = URL(string: "https://locken-app.vercel.app/")!
    private var webView: WKWebView?
    private var isReady = false
    private var readyWaiters: [CheckedContinuation<Void, Never>] = []
    private var pending: CheckedContinuation<String, Error>?

    enum GateError: LocalizedError {
        case failed
        var errorDescription: String? { "Couldn't confirm you're a person. Check your internet connection and try again." }
    }

    /// The public site key, or nil when the bot check is off.
    static var siteKey: String? {
        #if DEBUG
        // Testing only: `-turnstileSiteKey <key>` (for example Cloudflare's always-pass test key).
        if let key = UserDefaults.standard.string(forKey: "turnstileSiteKey"), !key.isEmpty { return key }
        #endif
        let key = (Bundle.main.object(forInfoDictionaryKey: "LockenTurnstileSiteKey") as? String)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return key.isEmpty ? nil : key
    }

    static var isEnabled: Bool { siteKey != nil }

    /// The web view the sign-in card shows (made on first use).
    var view: WKWebView {
        if let webView { return webView }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(WeakHandler(self), name: "turnstile")
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 300, height: 70), configuration: config)
        view.navigationDelegate = self
        view.setValue(false, forKey: "drawsBackground")
        webView = view
        load()
        return view
    }

    /// A fresh single-use token, or nil when the bot check is off. Waits for the person if Turnstile asks them to
    /// click (up to two minutes), otherwise usually a second or two.
    func token() async throws -> String? {
        guard Self.isEnabled else { return nil }
        _ = view
        if !isReady { await withCheckedContinuation { readyWaiters.append($0) } }
        pending?.resume(throwing: GateError.failed)
        return try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            webView?.evaluateJavaScript("lockenGetToken()")
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(120))
                guard let self, self.pending != nil else { return }
                self.finish(.failure(GateError.failed))
            }
        }
    }

    private func load() {
        guard let siteKey = Self.siteKey,
              let keyJSON = String(data: (try? JSONSerialization.data(withJSONObject: [siteKey])) ?? Data(), encoding: .utf8)
        else { return }
        let html = """
        <!doctype html><html><head><meta charset="utf-8">
        <style>html,body{margin:0;background:transparent;overflow:hidden}</style>
        <script src="https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit&onload=lockenReady" async defer></script>
        </head><body><div id="w"></div><script>
        var id = null;
        function post(m) { window.webkit.messageHandlers.turnstile.postMessage(m); }
        function lockenReady() {
          id = turnstile.render('#w', {
            sitekey: \(keyJSON)[0], execution: 'execute', appearance: 'interaction-only', theme: 'dark',
            callback: function (t) { post({ token: t }); },
            'error-callback': function () { post({ error: true }); return true; },
            'before-interactive-callback': function () { post({ show: true }); },
            'after-interactive-callback': function () { post({ show: false }); }
          });
          post({ ready: true });
        }
        function lockenGetToken() { turnstile.reset(id); turnstile.execute(id); }
        </script></body></html>
        """
        webView?.loadHTMLString(html, baseURL: Self.pageOrigin)
    }

    private func finish(_ result: Result<String, Error>) {
        needsInteraction = false
        let continuation = pending
        pending = nil
        continuation?.resume(with: result)
    }

    // MARK: WKScriptMessageHandler

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "turnstile", let body = message.body as? [String: Any] else { return }
        if body["ready"] as? Bool == true {
            isReady = true
            readyWaiters.forEach { $0.resume() }
            readyWaiters.removeAll()
        } else if let show = body["show"] as? Bool {
            needsInteraction = show
        } else if let token = body["token"] as? String, !token.isEmpty, token.count <= 4096 {
            finish(.success(token))
        } else if body["error"] != nil {
            finish(.failure(GateError.failed))
        }
    }

    // MARK: WKNavigationDelegate

    /// Only the widget page itself and Cloudflare's challenge frames load; any other link is blocked.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        let host = action.request.url?.host
        let isMainPage = action.targetFrame?.isMainFrame == true && action.request.url == Self.pageOrigin
        let isChallenge = action.targetFrame?.isMainFrame == false && host == "challenges.cloudflare.com"
        return isMainPage || isChallenge || action.request.url?.scheme == "about" ? .allow : .cancel
    }
}

/// Keeps the script handler from retaining the gate (WKUserContentController holds handlers strongly).
private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

/// The Turnstile widget in the sign-in card: invisible unless Turnstile asks the person to click.
struct TurnstileWidget: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { TurnstileGate.shared.view }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
