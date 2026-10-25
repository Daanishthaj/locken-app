import AppKit
import Foundation

/// Keeps distractions closed while a work session is active: games, social media and YouTube only.
/// Every other app (code, designs, documents, browsers, music) is always left alone; see `DistractionRules`.
///
/// - Apps: distracting apps already running when a session starts are quit, and any opened during the
///   session are quit as they launch or come to the front. Running apps are also re-checked every few
///   seconds, because an app that has only just launched can still report itself as not yet a regular
///   app and would otherwise slip through. A polite `terminate()` comes first; `forceTerminate()` follows
///   if the app is still running 2 seconds later. No permission is needed to quit the user's own apps.
/// - Browser tabs: browsers are never quit. Every few seconds, an AppleScript per running browser walks
///   every window's tabs and closes those on a blocked site (or a subdomain of one). This needs macOS
///   Automation permission for each browser (asked once per browser; `NSAppleEventsUsageDescription` in
///   Info.plist). Nothing here uses Accessibility, so that permission is never required.
///
/// All AppleScript runs on a private serial queue with a 3-second AppleEvent timeout, so a busy or hung
/// browser can't freeze the UI, and browsers that aren't running are skipped (never launched).
@MainActor
final class AppBlockingManager: ObservableObject {
    static let shared = AppBlockingManager()

    enum BlockerError: LocalizedError, Equatable {
        case automationDenied(browser: String)
        case scriptFailed(browser: String, code: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .automationDenied(let browser):
                return "Locken isn't allowed to control \(browser). Turn it on in System Settings › Privacy & Security › Automation."
            case .scriptFailed(let browser, let code, let message):
                return "Couldn't check \(browser)'s tabs (\(code)): \(message)"
            }
        }
    }

    /// Safari and the Chromium family (Chrome, Arc, Brave, Edge, Comet) all expose `windows`, `tabs`,
    /// `URL` and `close`, so one script works for each.
    struct Browser: Hashable {
        let bundleID: String
        let name: String
    }

    nonisolated static let browsers: [Browser] = [
        Browser(bundleID: "com.apple.Safari", name: "Safari"),
        Browser(bundleID: "com.google.Chrome", name: "Google Chrome"),
        Browser(bundleID: "company.thebrowser.Browser", name: "Arc"),
        Browser(bundleID: "com.brave.Browser", name: "Brave"),
        Browser(bundleID: "com.microsoft.edgemac", name: "Microsoft Edge"),
        Browser(bundleID: "ai.perplexity.comet", name: "Comet"),
    ]

    @Published private(set) var isEnforcing = false
    @Published private(set) var quitAppNames: [String] = []
    @Published private(set) var closedTabCount = 0
    /// Browsers that refused Automation; they're skipped until `start()` is called again.
    @Published private(set) var deniedBrowsers: Set<String> = []
    @Published private(set) var lastError: BlockerError?
    /// Told how many things were just closed (an app, or a sweep's tabs), for the distraction stats.
    var onBlock: (@MainActor (Int) -> Void)?
    /// Told the address of a YouTube tab that was just closed, so the video check overlay can offer to allow it.
    var onYouTubeBlocked: (@MainActor (String) -> Void)?

    /// YouTube videos the student needs for this session (11-character video IDs). Tabs playing one of these stay
    /// open; the rest of YouTube still closes. Set before or during a session, cleared when the session ends.
    @Published var allowedVideoIDs: [String] = []

    /// Finds YouTube video IDs in pasted links or an assignment's description: watch, youtu.be, shorts, embed, live.
    nonisolated static func youTubeVideoIDs(in text: String) -> [String] {
        let pattern = #"(?:youtube(?:-nocookie)?\.com/(?:watch\?(?:[^\s"'<>]*?&(?:amp;)?)?v=|shorts/|embed/|live/)|youtu\.be/)([A-Za-z0-9_-]{11})"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var ids: [String] = []
        for match in regex.matches(in: text, range: range) {
            guard let r = Range(match.range(at: 1), in: text) else { continue }
            let id = String(text[r])
            if !ids.contains(id) { ids.append(id) }
        }
        return ids
    }

    func allowVideos(from text: String) -> Int {
        let found = Self.youTubeVideoIDs(in: text).filter { !allowedVideoIDs.contains($0) }
        allowedVideoIDs.append(contentsOf: found.prefix(max(0, 50 - allowedVideoIDs.count)))
        return found.count
    }

    func removeAllowedVideo(_ id: String) { allowedVideoIDs.removeAll { $0 == id } }

    // MARK: The student's own choices (per account)

    /// Apps the student added to the block list themselves, by bundle ID, with the name to show.
    @Published private(set) var userBlockedApps: [String: String] = [:]
    /// Apps Locken would block on its own (games, social media) that the student chose to keep open.
    @Published private(set) var userAllowedApps: Set<String> = []

    private enum DefaultsKey {
        static let blockedBase = "blocker.userBlocked"
        static let allowedBase = "blocker.userAllowed"
        @MainActor static var blocked: String { blockedBase + AccountScope.suffix }
        @MainActor static var allowed: String { allowedBase + AccountScope.suffix }
    }

    /// Apps that can never be on the block list: Locken itself, Finder and browsers (their tabs are checked instead).
    nonisolated static func canBeBlocked(bundleID: String) -> Bool {
        bundleID != Bundle.main.bundleIdentifier && bundleID != "com.apple.finder"
            && !browsers.contains { $0.bundleID == bundleID } && bundleID != "org.mozilla.firefox"
    }

    func activateAccount() {
        userBlockedApps = UserDefaults.standard.dictionary(forKey: DefaultsKey.blocked) as? [String: String] ?? [:]
        userAllowedApps = Set(UserDefaults.standard.stringArray(forKey: DefaultsKey.allowed) ?? [])
        decisionCache = [:]
    }

    /// Whether this app is closed during sessions, after the student's own choices.
    func isBlocked(bundleID: String, builtIn: Bool) -> Bool {
        if userAllowedApps.contains(bundleID) { return false }
        if userBlockedApps[bundleID] != nil { return true }
        return builtIn
    }

    /// Adds an app to, or takes it off, the block list. `builtIn` is whether Locken would block it on its own.
    func setBlocked(_ blocked: Bool, bundleID: String, name: String, builtIn: Bool) {
        guard Self.canBeBlocked(bundleID: bundleID) else { return }
        if blocked {
            userAllowedApps.remove(bundleID)
            if !builtIn { userBlockedApps[bundleID] = String(name.prefix(80)) }
        } else {
            userBlockedApps[bundleID] = nil
            if builtIn { userAllowedApps.insert(bundleID) }
        }
        UserDefaults.standard.set(userBlockedApps, forKey: DefaultsKey.blocked)
        UserDefaults.standard.set(Array(userAllowedApps).sorted(), forKey: DefaultsKey.allowed)
        decisionCache = [:]
        // During a session, a newly blocked app that's already open closes right away.
        if blocked { sweepRunningApps() }
    }

    private let tabSweepInterval: TimeInterval = 3
    private var launchObserver: NSObjectProtocol?
    private var activateObserver: NSObjectProtocol?
    /// Apps already asked to quit, so each sweep doesn't ask again (or list them twice).
    private var quitting: Set<pid_t> = []
    private var tabTimer: Timer?
    private var sweepInFlight = false
    private var decisionCache: [String: Bool] = [:]
    private let scriptQueue = DispatchQueue(label: "com.locken.LockenTestApp.app-blocking", qos: .userInitiated)

    private init() {}

    // MARK: Session hooks

    func start() {
        guard !isEnforcing else { return }
        isEnforcing = true
        deniedBrowsers = []
        lastError = nil
        quitAppNames = []
        quitting = []

        // Apps already open when the session begins.
        sweepRunningApps()

        // Opened or switched to during the session.
        let center = NSWorkspace.shared.notificationCenter
        let handler: @Sendable (Notification) -> Void = { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let self, self.isEnforcing, let app else { return }
                self.quitIfBlocked(app)
            }
        }
        launchObserver = center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main, using: handler)
        activateObserver = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main, using: handler)

        let timer = Timer(timeInterval: tabSweepInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sweepRunningApps()
                self?.sweepBrowserTabs()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tabTimer = timer
        sweepBrowserTabs()
    }

    func stop() {
        guard isEnforcing else { return }
        isEnforcing = false
        for observer in [launchObserver, activateObserver].compactMap({ $0 }) {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        launchObserver = nil
        activateObserver = nil
        tabTimer?.invalidate()
        tabTimer = nil
    }

    // MARK: Apps

    private func isDistraction(_ app: NSRunningApplication) -> Bool {
        // Only ordinary windowed apps; menu-bar agents and background helpers are never touched.
        guard let bundleID = app.bundleIdentifier, app.activationPolicy == .regular,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return false }
        let key = bundleID + "|" + (app.bundleURL?.path ?? "")
        if let cached = decisionCache[key] { return cached }
        let category = app.bundleURL.flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String }
        let builtIn = DistractionRules.isDistraction(
            bundleID: bundleID,
            name: app.localizedName,
            bundlePath: app.bundleURL?.path,
            category: category
        )
        let decision = Self.canBeBlocked(bundleID: bundleID) && isBlocked(bundleID: bundleID, builtIn: builtIn)
        decisionCache[key] = decision
        return decision
    }

    private func sweepRunningApps() {
        guard isEnforcing else { return }
        let running = NSWorkspace.shared.runningApplications
        quitting.formIntersection(running.filter { !$0.isTerminated }.map(\.processIdentifier))
        running.forEach(quitIfBlocked)
    }

    private func quitIfBlocked(_ app: NSRunningApplication) {
        guard !app.isTerminated, !quitting.contains(app.processIdentifier), isDistraction(app) else { return }
        quitting.insert(app.processIdentifier)
        let name = app.localizedName ?? app.bundleIdentifier ?? "App"
        if !app.terminate() {
            app.forceTerminate()
        } else {
            // Apps may show a "save changes?" sheet or ignore the quit request; don't wait on them.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if !app.isTerminated { app.forceTerminate() }
            }
        }
        if !quitAppNames.contains(name) { quitAppNames.append(name) }
        onBlock?(1)
    }

    // MARK: Browser tabs

    private func sweepBrowserTabs() {
        guard isEnforcing, !sweepInFlight else { return }
        let running = Self.browsers.filter { browser in
            !deniedBrowsers.contains(browser.name)
                && !NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).isEmpty
        }
        guard !running.isEmpty else { return }

        sweepInFlight = true
        let allowedVideos = allowedVideoIDs
        scriptQueue.async {
            // NSAppleScript waits synchronously for each browser's reply, so it only ever runs here, one at a time.
            let results = running.map { ($0, Self.closeBlockedTabs(in: $0, allowedVideos: allowedVideos)) }
            Task { @MainActor in
                self.sweepInFlight = false
                for (browser, result) in results {
                    switch result {
                    case .success(let swept):
                        self.closedTabCount += swept.closed
                        if swept.closed > 0 { self.onBlock?(swept.closed) }
                        // A YouTube video was closed: offer to check it instead of just leaving the student stuck.
                        if let url = swept.youTubeURLs.first { self.onYouTubeBlocked?(url) }
                    case .failure(let error):
                        if case .automationDenied = error { self.deniedBrowsers.insert(browser.name) }
                        self.lastError = error
                    }
                }
            }
        }
    }

    /// Runs one sweep of `browser` on the calling (background) thread. Returns how many tabs were closed.
    struct Sweep { let closed: Int; let youTubeURLs: [String] }

    nonisolated private static func closeBlockedTabs(in browser: Browser, allowedVideos: [String]) -> Result<Sweep, BlockerError> {
        var error: NSDictionary?
        let result = NSAppleScript(source: script(for: browser, allowedVideos: allowedVideos))?.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            switch code {
            case -1743: // errAEEventNotPermitted: Automation is off for this browser.
                return .failure(.automationDenied(browser: browser.name))
            case -600, -609: // Browser quit between the check and the script.
                return .success(Sweep(closed: 0, youTubeURLs: []))
            default:
                return .failure(.scriptFailed(browser: browser.name, code: code, message: message))
            }
        }
        // The script returns the count on the first line, then the YouTube addresses it closed, one per line.
        let lines = (result?.stringValue ?? "0").components(separatedBy: .newlines)
        let closed = Int(lines.first?.trimmingCharacters(in: .whitespaces) ?? "") ?? 0
        let urls = lines.dropFirst().map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("http") }
        return .success(Sweep(closed: closed, youTubeURLs: Array(urls)))
    }

    /// The AppleScript for one sweep. Tabs are walked from last to first so closing one doesn't shift the
    /// index of those still to check; hosts are parsed properly (so "x.com" never matches "x.company.com"),
    /// and allowed sites (YouTube Music, YouTube Studio) are checked before blocked ones.
    nonisolated static func script(for browser: Browser, allowedVideos: [String] = []) -> String {
        func list(_ domains: [String]) -> String {
            domains
                .map { "\"" + $0.replacingOccurrences(of: "\\", with: "").replacingOccurrences(of: "\"", with: "") + "\"" }
                .joined(separator: ", ")
        }
        return """
        property blockedDomains : {\(list(DistractionRules.blockedDomains))}
        property allowedDomains : {\(list(DistractionRules.allowedDomains))}
        property allowedVideos : {\(list(allowedVideos.filter { $0.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil }))}

        -- The 11-character video ID in a YouTube link (watch?v=, youtu.be/, shorts/, embed/, live/), or "".
        on videoIdOf(u)
            set savedDelimiters to AppleScript's text item delimiters
            set vid to ""
            try
                set marker to ""
                repeat with m in {"?v=", "&v=", "youtu.be/", "/shorts/", "/embed/", "/live/"}
                    if u contains (contents of m) then
                        set marker to contents of m
                        exit repeat
                    end if
                end repeat
                if marker is not "" then
                    set AppleScript's text item delimiters to marker
                    set afterMarker to text item 2 of u
                    if (length of afterMarker) is greater than or equal to 11 then set vid to text 1 thru 11 of afterMarker
                end if
            end try
            set AppleScript's text item delimiters to savedDelimiters
            return vid
        end videoIdOf

        on hostOf(u)
            set savedDelimiters to AppleScript's text item delimiters
            try
                set AppleScript's text item delimiters to "://"
                if (count of text items of u) < 2 then error "no scheme"
                set afterScheme to text item 2 of u
                set AppleScript's text item delimiters to "/"
                set h to text item 1 of afterScheme
                set AppleScript's text item delimiters to "@"
                set h to last text item of h
                set AppleScript's text item delimiters to ":"
                set h to text item 1 of h
                set AppleScript's text item delimiters to savedDelimiters
                return h
            on error
                set AppleScript's text item delimiters to savedDelimiters
                return ""
            end try
        end hostOf

        on matchesAny(h, domainList)
            repeat with d in domainList
                set d to contents of d
                if h is d or h ends with ("." & d) then return true
            end repeat
            return false
        end matchesAny

        on isBlocked(u)
            set h to my hostOf(u)
            if h is "" then return false
            if my matchesAny(h, allowedDomains) then return false
            if (count of allowedVideos) > 0 and my matchesAny(h, {"youtube.com", "youtu.be"}) then
                set vid to my videoIdOf(u)
                if vid is not "" and allowedVideos contains vid then return false
            end if
            return my matchesAny(h, blockedDomains)
        end isBlocked

        with timeout of 3 seconds
            tell application id "\(browser.bundleID)"
                set closedCount to 0
                set ytURLs to {}
                repeat with w in windows
                    set tabCount to count of tabs of w
                    repeat with i from tabCount to 1 by -1
                        try
                            set t to tab i of w
                            set u to URL of t
                            if u is not missing value and my isBlocked(u) then
                                if my matchesAny(my hostOf(u), {"youtube.com", "youtu.be"}) then set end of ytURLs to u
                                close t
                                set closedCount to closedCount + 1
                            end if
                        end try
                    end repeat
                end repeat
                set savedDelimiters to AppleScript's text item delimiters
                set AppleScript's text item delimiters to linefeed
                set report to (closedCount as text) & linefeed & (ytURLs as text)
                set AppleScript's text item delimiters to savedDelimiters
                return report
            end tell
        end timeout
        """
    }
}

// MARK: - Distraction rules

/// What counts as a distraction: games, social media and YouTube, nothing else.
///
/// An app is quit only if it's a game, a social-media app, or a web app of a blocked site, and never if it's
/// on the protected list of work apps, whatever else it matches. Anything unrecognised is left running:
/// the rules err on the side of never closing someone's code, designs or documents.
enum DistractionRules {
    /// Social media, chat and game-launcher apps.
    static let socialAndGameBundleIDs: Set<String> = [
        // Social media and chat
        "com.hnc.Discord", "com.apple.MobileSMS", "net.whatsapp.WhatsApp", "desktop.WhatsApp",
        "ru.keepcoder.Telegram", "org.telegram.desktop", "com.facebook.archon", "com.atebits.Tweetie2",
        "com.twitter.twitter-mac", "com.burbn.instagram", "com.zhiliaoapp.musically", "com.reddit.Reddit",
        "com.toyopagroup.picaboo", "com.google.ios.youtube",
        // Games and game launchers
        "com.valvesoftware.steam", "com.epicgames.EpicGamesLauncher", "net.battle.app",
        "com.riotgames.RiotGames.RiotClient", "com.mojang.minecraftlauncher", "com.roblox.RobloxPlayer",
        "com.gog.galaxy",
    ]

    /// Sites whose apps (installed from Safari, Chrome, Edge or Brave as "web apps") and tabs are closed.
    /// Subdomains match too (m.youtube.com, old.reddit.com).
    static let blockedDomains: [String] = [
        "youtube.com", "youtu.be",
        "twitter.com", "x.com", "reddit.com", "instagram.com", "facebook.com", "tiktok.com", "snapchat.com",
        "threads.net", "threads.com", "pinterest.com", "tumblr.com", "twitch.tv",
    ]

    /// Checked first, so these stay open: YouTube Music (focus music) and YouTube Studio (creators' work).
    static let allowedDomains: [String] = ["music.youtube.com", "studio.youtube.com"]

    /// Names of blocked sites' web apps ("Add to Dock" in Safari, "Install app" in Chrome/Edge/Brave).
    static let blockedWebAppNames: Set<String> = [
        "youtube", "instagram", "facebook", "x", "twitter", "reddit", "tiktok", "threads", "snapchat",
        "pinterest", "tumblr", "twitch", "discord", "messenger", "whatsapp", "telegram",
    ]

    private static let webAppBundleIDPrefixes = [
        "com.apple.Safari.WebApp.", "com.google.Chrome.app.", "com.microsoft.edgemac.app.", "com.brave.Browser.app.",
    ]

    /// Work apps that are never quit: code editors and terminals, design, video and 3D tools (including ones
    /// sold through Steam), office and note apps, browsers (only their tabs are checked) and music players.
    static let protectedBundleIDs: Set<String> = [
        "com.apple.dt.Xcode", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.apple.Terminal",
        "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.sublimetext.4", "com.github.GitHubClient",
        "com.canva.CanvaDesktop", "com.figma.Desktop", "com.bohemiancoding.sketch3", "com.seriflabs.affinitydesigner2",
        "com.seriflabs.affinityphoto2", "org.blenderfoundation.blender", "org.godotengine.godot",
        "com.epicgames.UnrealEditor", "com.igarastudio.aseprite", "com.apple.FinalCut", "com.apple.iMovieApp",
        "com.apple.logic10", "com.apple.garageband10", "com.apple.iWork.Pages", "com.apple.iWork.Keynote",
        "com.apple.iWork.Numbers", "com.apple.Notes", "com.apple.finder", "notion.id", "md.obsidian",
        "com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "com.brave.Browser",
        "com.microsoft.edgemac", "ai.perplexity.comet", "org.mozilla.firefox", "com.spotify.client", "com.apple.Music",
    ]

    /// Whole publishers of work software.
    static let protectedBundleIDPrefixes = ["com.adobe.", "com.microsoft.", "com.jetbrains.", "com.unity3d.", "com.autodesk."]

    /// Folders games are installed into by their stores.
    private static let gameLibraryPathMarkers = ["/steamapps/common/", "/Epic Games/"]

    static func isProtected(bundleID: String) -> Bool {
        protectedBundleIDs.contains(bundleID) || protectedBundleIDPrefixes.contains { bundleID.hasPrefix($0) }
    }

    static func isGame(category: String?, bundlePath: String?) -> Bool {
        if let category, category == "public.app-category.games" || category.hasSuffix("-games") { return true }
        // Many store games declare no category. A work app sold through Steam (Blender, Aseprite…) declares a
        // work category, so only uncategorised or entertainment apps in a game library count as games.
        guard let bundlePath, gameLibraryPathMarkers.contains(where: { bundlePath.contains($0) }) else { return false }
        return category == nil || category == "public.app-category.entertainment"
    }

    static func isBlockedWebApp(bundleID: String, name: String?) -> Bool {
        guard webAppBundleIDPrefixes.contains(where: { bundleID.hasPrefix($0) }), let name else { return false }
        return blockedWebAppNames.contains(name.trimmingCharacters(in: .whitespaces).lowercased())
    }

    /// The decision for one app. Order matters: a blocked site's web app is a distraction even though it's
    /// hosted by a protected browser; after that, protected work apps always win.
    static func isDistraction(bundleID: String, name: String?, bundlePath: String?, category: String?) -> Bool {
        if isBlockedWebApp(bundleID: bundleID, name: name) { return true }
        if isProtected(bundleID: bundleID) { return false }
        if socialAndGameBundleIDs.contains(bundleID) { return true }
        return isGame(category: category, bundlePath: bundlePath)
    }
}
