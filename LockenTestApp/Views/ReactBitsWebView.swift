import SwiftUI
import AppKit
import WebKit
import Collaboration
import QuartzCore

/// Hosts a React Bits component (bundled from `WebComponents/` into `Resources/Web/` by `npm run build`)
/// in a transparent WKWebView, so the component's own code renders unchanged.
/// `props` are handed to the page as `window.__initialProps` and later via `window.updateProps(props)`.
struct ReactBitsWebView: NSViewRepresentable {
    enum Page: String {
        case electricLogo = "electric"
        case ditherVeil = "dither"
        case profileCard = "profile"
        case jellyRadio = "jelly"
        case orb = "orb"
        case codeSlots = "codeslots"
        /// Liquid-glass clock digits for the focus timer (WebComponents/src/fluidglass-entry.jsx).
        case fluidGlassTime = "fluidglass"
        /// The Assistant's hero: React Bits Strands, light strands on a transparent page (WebComponents/src/strands-entry.jsx).
        case strands = "strands"
        /// The collapsed sidebar's buttons: React Bits GlassIcons in one column (WebComponents/src/glassicons-entry.jsx).
        case glassIcons = "glassicons"
        /// Plain HTML (WebComponents/public/papers.html), the transition into the focus timer.
        case papers = "papers"
    }

    let page: Page
    var props: [String: String] = [:]
    /// Receives strings the page posts via `window.webkit.messageHandlers.locken.postMessage(...)`.
    var onMessage: ((String) -> Void)? = nil
    /// For a web view layered behind other views (so real mouse events never reach it): the pointer position
    /// to forward to the page's `window.__lockenPointer`.
    var pointerForwarding: PointerForwarding = .off

    enum PointerForwarding: Equatable {
        case off
        case outside
        case at(CGPoint)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let json = Self.json(props)
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(
            WKUserScript(source: "window.__initialProps = \(json);", injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        context.coordinator.onMessage = onMessage
        configuration.userContentController.add(context.coordinator, name: "locken")

        let webView = ScrollPassthroughWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        context.coordinator.currentJSON = json
        context.coordinator.loadedJSON = json

        // Hidden until the component has painted, then faded in (and counted by the page's load gate).
        webView.alphaValue = 0
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        if let gate = context.environment.assetLoadGate {
            context.coordinator.gate = gate
            context.coordinator.gateID = gate.register()
        }

        if let url = Bundle.main.url(forResource: page.rawValue, withExtension: "html", subdirectory: "Web") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onMessage = onMessage
        if pointerForwarding != context.coordinator.lastPointer {
            context.coordinator.lastPointer = pointerForwarding
            switch pointerForwarding {
            case .off:
                break
            case .outside:
                context.coordinator.cancelPendingPointer()
                webView.evaluateJavaScript("window.__lockenPointer && window.__lockenPointer(0, 0, false)")
            case .at(let point):
                context.coordinator.forward(point, to: webView)
            }
        }
        let json = Self.json(props)
        guard json != context.coordinator.currentJSON else { return }
        context.coordinator.currentJSON = json
        webView.evaluateJavaScript("window.updateProps && window.updateProps(\(json))")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var currentJSON = ""
        /// The props the page was loaded with (`window.__initialProps`).
        var loadedJSON = ""
        var onMessage: ((String) -> Void)?
        var lastPointer: PointerForwarding = .off
        /// The pointer moves faster than a page can draw: the first move goes at once, then at most one more per frame (the
        /// latest position), instead of a message to the page for every mouse event.
        private var lastPointerSend: CFTimeInterval = 0
        private var pendingPointer: CGPoint?
        private var pointerFlushScheduled = false

        func forward(_ point: CGPoint, to webView: WKWebView) {
            let now = CACurrentMediaTime()
            if now - lastPointerSend >= 1.0 / 60 {
                send(point, to: webView, at: now)
                return
            }
            pendingPointer = point
            guard !pointerFlushScheduled else { return }
            pointerFlushScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60) { [weak self, weak webView] in
                guard let self else { return }
                self.pointerFlushScheduled = false
                guard let webView, let point = self.pendingPointer else { return }
                self.send(point, to: webView, at: CACurrentMediaTime())
            }
        }

        func cancelPendingPointer() { pendingPointer = nil }

        private func send(_ point: CGPoint, to webView: WKWebView, at time: CFTimeInterval) {
            lastPointerSend = time
            pendingPointer = nil
            webView.evaluateJavaScript("window.__lockenPointer && window.__lockenPointer(\(point.x), \(point.y), true)")
        }
        weak var webView: WKWebView?
        weak var gate: AssetLoadGate?
        var gateID: UUID?
        private var isShown = false

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let text = message.body as? String else { return }
            // Every page posts "ready" after its first paint (see build.mjs).
            if text == "ready" {
                show()
                return
            }
            onMessage?(text)
        }

        /// The app's bundled web pages folder; the only place these views may load.
        private static let webRoot = Bundle.main.url(forResource: "Web", withExtension: nil)?.standardizedFileURL.path

        /// Pages can't be navigated (by a link, a script or a redirect) to anything but the app's own bundled files.
        @MainActor
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .cancel }
            if url.absoluteString == "about:blank" { return .allow }
            guard url.isFileURL, let root = Self.webRoot, url.standardizedFileURL.path.hasPrefix(root) else { return .cancel }
            return .allow
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Fallback if a page never posts "ready".
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.show() }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { show() }

        private func show() {
            guard !isShown else { return }
            isShown = true
            // Props that changed while the page was still loading were sent before `updateProps` existed and
            // were lost, which left pickers showing a stale choice; send the latest ones now.
            if currentJSON != loadedJSON {
                webView?.evaluateJavaScript("window.updateProps && window.updateProps(\(currentJSON))")
            }
            if let webView {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.35
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    webView.animator().alphaValue = 1
                }
            }
            if let gateID {
                MainActor.assumeIsolated { gate?.markReady(gateID) }
            }
        }
    }

    private static func json(_ props: [String: String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: props, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// The pages never scroll themselves; wheel events go to the scroll view under the pointer so the surrounding
/// SwiftUI ScrollView keeps scrolling — including when the web view is layered above that ScrollView rather than inside it.
private final class ScrollPassthroughWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        if let scrollView = enclosingScrollView ?? scrollViewUnderPointer(event) {
            scrollView.scrollWheel(with: event)
        } else {
            nextResponder?.scrollWheel(with: event)
        }
    }

    private func scrollViewUnderPointer(_ event: NSEvent) -> NSScrollView? {
        guard let root = window?.contentView else { return nil }
        var found: NSScrollView?
        func search(_ view: NSView) {
            for subview in view.subviews where subview !== self && !subview.isHidden {
                guard subview.bounds.contains(subview.convert(event.locationInWindow, from: nil)) else { continue }
                if let scrollView = subview as? NSScrollView { found = scrollView }
                search(subview)
            }
        }
        search(root)
        return found
    }
}

/// Renders an SF Symbol as a white-on-transparent PNG data URL — ElectricLogo traces its silhouette.
@MainActor
enum SymbolLogo {
    private static var cache: [String: String] = [:]

    static func dataURL(systemName: String) -> String? {
        if let cached = cache[systemName] { return cached }
        let configuration = NSImage.SymbolConfiguration(pointSize: 256, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        guard let symbol = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration),
              let url = pngDataURL(symbol) else { return nil }
        cache[systemName] = url
        return url
    }
}

/// The silhouette ElectricLogo traces for a workspace app.
enum WorkspaceAppLogo {
    case brand(String)  // SVG file name in Resources/Web/logos
    case symbol(String) // SF Symbol name
    case appIcon(String) // path to an installed .app, for apps the student added

    @MainActor
    var dataURL: String? {
        switch self {
        case .brand(let name): return BrandLogo.dataURL(named: name)
        case .symbol(let name): return SymbolLogo.dataURL(systemName: name)
        case .appIcon(let path): return AppIconLogo.dataURL(path: path)
        }
    }
}

/// An installed app's own icon (from Finder), for apps the student added to their lineup.
@MainActor
enum AppIconLogo {
    private static var cache: [String: String] = [:]

    static func dataURL(path: String) -> String? {
        if let cached = cache[path] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 256, height: 256)
        guard let url = pngDataURL(icon) else { return nil }
        cache[path] = url
        return url
    }
}

/// Brand logo SVGs bundled in `Resources/Web/logos` (from Simple Icons), as data URLs so the page never
/// makes a cross-origin file:// image request.
@MainActor
enum BrandLogo {
    private static var cache: [String: String] = [:]

    static func dataURL(named name: String) -> String? {
        if let cached = cache[name] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "Web/logos"),
              let data = try? Data(contentsOf: url) else { return nil }
        let dataURL = "data:image/svg+xml;base64," + data.base64EncodedString()
        cache[name] = dataURL
        return dataURL
    }
}

/// The profile photo for ProfileCard: the Mac account picture, or the existing "M" monogram if there is none.
@MainActor
enum ProfileAvatar {
    static let dataURL: String? = accountPicture() ?? monogram()

    private static func accountPicture() -> String? {
        guard let identity = CBUserIdentity(posixUID: getuid(), authority: .default()),
              let image = identity.image else { return nil }
        return pngDataURL(image)
    }

    private static func monogram() -> String? {
        let view = ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [SquircleTokens.amberDashboard, SquircleTokens.obsidianCard],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            Text("M")
                .font(.appFont(size: 220, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: 512, height: 512)
        guard let image = ImageRenderer(content: view).nsImage else { return nil }
        return pngDataURL(image)
    }
}

private func pngDataURL(_ image: NSImage) -> String? {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
    return "data:image/png;base64," + png.base64EncodedString()
}

/// React Bits JellyRadio as a single-choice picker; the app owns the selection, and the frame hugs the component.
struct JellyRadioPicker: View {
    let items: [String]
    @Binding var selection: String
    var label: String = "Options"
    /// The page whose accent tints the selected pill; nil follows the open tab. The sign-in screen passes "focus",
    /// so it's always Locken violet (otherwise it took the last open tab's color, like Settings' slate blue).
    var accentTab: String? = nil

    @State private var size = CGSize(width: 900, height: 48)
    @ObservedObject private var state = TestAppStateManager.shared

    var body: some View {
        let itemsJSON = (try? JSONSerialization.data(withJSONObject: items))
            .map { String(decoding: $0, as: UTF8.self) } ?? "[]"
        ReactBitsWebView(
            page: .jellyRadio,
            props: [
                "items": itemsJSON,
                "value": selection,
                "label": label,
                // Selected pill: a very light version of the current tab's accent instead of plain white.
                "activeColor": SquircleTokens.accentColor(for: accentTab ?? state.selectedTab).lightened(0.55).hexRGB,
            ],
            onMessage: { message in
                if message.hasPrefix("change:") {
                    selection = String(message.dropFirst("change:".count))
                } else if message.hasPrefix("size:") {
                    let parts = message.dropFirst("size:".count).split(separator: "x").compactMap { Double($0) }
                    if parts.count == 2, parts[0] > 0, parts[1] > 0 {
                        // Whole, even points: centred in its row it lands on whole pixels, so the text stays sharp.
                        size = CGSize(width: (parts[0] / 2).rounded(.up) * 2, height: (parts[1] / 2).rounded(.up) * 2)
                    }
                }
            }
        )
        // As wide as the pills want, but no wider than the space there is: in a narrower row the pills wrap onto a
        // second line (the page reports the taller height) instead of being cut off at the edge.
        .frame(maxWidth: size.width)
        .frame(height: size.height)
    }
}

/// React Bits CodeSlots: six animated digit slots for a verification code. `onComplete` gets the code;
/// set `status` to .success / .error after checking it (typing again resets it to idle).
struct CodeSlotsField: View {
    enum Status: String { case idle, success, error }

    @Binding var status: Status
    var accent: Color = .white
    let onComplete: (String) -> Void
    @State private var resetKey = 0

    var body: some View {
        ReactBitsWebView(
            page: .codeSlots,
            props: ["status": status.rawValue, "accentColor": accent.hexRGB, "resetKey": String(resetKey)],
            onMessage: { message in
                if message.hasPrefix("complete:") {
                    onComplete(String(message.dropFirst("complete:".count)))
                } else if message == "change", status != .idle {
                    status = .idle
                }
            }
        )
        .frame(width: 320, height: 64)
        .accessibilityLabel("Six-digit verification code")
    }
}

