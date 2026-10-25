import AppKit
import Foundation
import CoreGraphics
import ServiceManagement

/// Measures how long each app (and, with permission, each website) is in use on this Mac.
///
/// Apple's Screen Time API (FamilyControls / DeviceActivity) is marked unavailable on macOS, and its
/// on-disk store needs Full Disk Access, so Locken measures usage itself with public APIs only:
/// app activation notifications decide which app is in front, idle time and screen lock/sleep decide
/// whether anyone is actually using it, and the current tab's address (read over Apple Events once the
/// user opts in) lets time on social media sites in a browser count as social media.
@MainActor
final class ScreenUsageTracker: ObservableObject {
    static let shared = ScreenUsageTracker()

    enum Category: String, Codable, CaseIterable, Identifiable {
        case social, entertainment, productivity, development, web, other
        var id: String { rawValue }

        var title: String {
            switch self {
            case .social: return "Social Media"
            case .entertainment: return "Entertainment"
            case .productivity: return "Productivity"
            case .development: return "Development"
            case .web: return "Other Websites"
            case .other: return "Other"
            }
        }
    }

    struct AppUsage: Codable {
        var name: String
        var seconds: Double
    }

    /// One calendar day of usage. Only website domains are stored, never full addresses.
    struct DayUsage: Codable {
        var apps: [String: AppUsage] = [:]          // bundle ID → usage
        var sites: [String: Double] = [:]           // domain → seconds
        var categories: [String: Double] = [:]      // Category.rawValue → seconds
        var hourly: [Double] = Array(repeating: 0, count: 24)
        var hourlySocial: [Double] = Array(repeating: 0, count: 24)

        var total: Double { hourly.reduce(0, +) }
        func seconds(in category: Category) -> Double { categories[category.rawValue] ?? 0 }
    }

    @Published private(set) var days: [String: DayUsage] = [:]
    /// True while the screen is locked or asleep, the user switched away, or nobody has touched the Mac for a while.
    @Published private(set) var isPaused = false
    @Published private(set) var tracksWebsites: Bool
    /// Browsers whose tab address macOS refused to share (Automation turned off for Locken).
    @Published private(set) var blockedBrowsers: Set<String> = []

    /// Input idle longer than this stops the clock (counted up to the last input plus this grace period).
    private let idleLimit: TimeInterval = 5 * 60
    /// Time is split exactly at app switches; the 1-second tick only keeps the page's numbers live.
    private let tickInterval: TimeInterval = 1
    /// A gap longer than this means the Mac was asleep without telling us, so it isn't counted.
    private let maxGap: TimeInterval = 15
    /// Browser tab addresses are read every few ticks, not every second.
    private let domainRefreshTicks = 5
    private var ticksSinceDomainRefresh = 0
    private static let keepDays = 35

    private var started = false
    private var screenLocked = false
    private var screenAsleep = false
    private var sessionInactive = false
    private var lastFlush = Date()
    private var lastSave = Date()
    private var frontBundleID: String?
    private var frontName = ""
    private var frontDomain: String?
    private var timer: Timer?
    private var activity: NSObjectProtocol?
    private var categoryCache: [String: Category] = [:]
    private var listableCache: [String: Bool] = [:]
    private let scriptQueue = DispatchQueue(label: "com.locken.LockenTestApp.usage-scripts")
    private let tracksWebsitesKey = "usageTracksWebsites"

    private init() {
        tracksWebsites = UserDefaults.standard.bool(forKey: tracksWebsitesKey)
    }

    /// Forgets the loaded account (after it's deleted), so its usage isn't written again.
    func deactivateAccount() {
        loadedSuffix = nil
        days = [:]
    }

    /// Deletes this account's recorded screen usage on this Mac (Settings → Data on This Mac).
    func clearHistory() {
        days = [:]
        if let url = storeURL { try? FileManager.default.removeItem(at: url) }
    }

    /// Switches to the signed-in account's usage file (saving the previous account's first).
    func activateAccount() {
        if storeURL != nil, loadedSuffix != AccountScope.suffix, loadedSuffix != nil { save() }
        AccountScope.adoptLegacyFile(named: "screen-usage.json", as: "screen-usage\(AccountScope.suffix).json")
        days = [:]
        loadedSuffix = AccountScope.suffix
        load()
    }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true
        lastFlush = Date()
        // Without this, App Nap throttles the timer while Locken is in the background and time goes uncounted.
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Measuring app usage")
        adoptFrontApp(NSWorkspace.shared.frontmostApplication)

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let self else { return }
                self.flush()
                self.adoptFrontApp(app)
            }
        }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.screenAsleep = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.screenAsleep = false }
        observe(workspace, NSWorkspace.willSleepNotification) { $0.screenAsleep = true }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.screenAsleep = false }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.sessionInactive = true }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionInactive = false }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.screenLocked = true }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.screenLocked = false }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.flush()
                self?.save()
            }
        }

        let timer = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Flushes elapsed time before a lock/sleep/session state change so time is split at the exact moment.
    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ change: @escaping (ScreenUsageTracker) -> Void) {
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.flush()
                change(self)
                self.lastFlush = Date()
                self.updatePaused()
            }
        }
    }

    private func tick() {
        flush()
        ticksSinceDomainRefresh += 1
        if ticksSinceDomainRefresh >= domainRefreshTicks {
            ticksSinceDomainRefresh = 0
            refreshDomain()
        }
        if Date().timeIntervalSince(lastSave) > 60 { save() }
    }

    private func adoptFrontApp(_ app: NSRunningApplication?) {
        // Permission prompts, Spotlight and other background helpers briefly take focus; keep counting the app underneath.
        guard let app, app.activationPolicy == .regular else { return }
        frontBundleID = app.bundleIdentifier
        frontName = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
        frontDomain = nil
        refreshDomain()
    }

    private func updatePaused() {
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        let paused = screenLocked || screenAsleep || sessionInactive || idle > idleLimit
        if paused != isPaused { isPaused = paused }
    }

    // MARK: - Accounting

    /// Attributes the time since the last flush to the app (and site) currently in front.
    private func flush() {
        let now = Date()
        defer { lastFlush = now }
        updatePaused()
        guard !(screenLocked || screenAsleep || sessionInactive), let bundleID = frontBundleID else { return }

        // Stop counting `idleLimit` after the last keyboard/mouse input.
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        let end = min(now, now.addingTimeInterval(-idle + idleLimit))
        // A gap much longer than a tick means the Mac was asleep without telling us; don't count it.
        let start = max(lastFlush, end.addingTimeInterval(-maxGap))
        guard end > start else { return }

        let domain = Self.isBrowser(bundleID) ? frontDomain : nil
        let category = domain.flatMap(Self.category(forDomain:))
            ?? (Self.isBrowser(bundleID) ? .web : appCategory(bundleID))
        record(from: start, to: end, bundleID: bundleID, name: frontName, domain: domain, category: category)
    }

    /// Adds an interval, split at hour boundaries so it lands in the right hour and day.
    private func record(from start: Date, to end: Date, bundleID: String, name: String, domain: String?, category: Category) {
        let calendar = Calendar.current
        var cursor = start
        while cursor < end {
            let hourStart = calendar.dateInterval(of: .hour, for: cursor)!
            let chunkEnd = min(end, hourStart.end)
            let seconds = chunkEnd.timeIntervalSince(cursor)
            let key = Self.dayKey(cursor)
            let hour = calendar.component(.hour, from: cursor)

            var day = days[key] ?? DayUsage()
            day.apps[bundleID, default: AppUsage(name: name, seconds: 0)].seconds += seconds
            day.apps[bundleID]?.name = name
            if let domain { day.sites[domain, default: 0] += seconds }
            day.categories[category.rawValue, default: 0] += seconds
            day.hourly[hour] += seconds
            if category == .social { day.hourlySocial[hour] += seconds }
            days[key] = day

            cursor = chunkEnd
        }
    }

    // MARK: - Websites

    /// Asks macOS for permission to read browser tab addresses; the prompt appears for each browser the first time.
    func enableWebsiteTracking() {
        tracksWebsites = true
        blockedBrowsers = []
        UserDefaults.standard.set(true, forKey: tracksWebsitesKey)
        refreshDomain()
    }

    func disableWebsiteTracking() {
        tracksWebsites = false
        frontDomain = nil
        UserDefaults.standard.set(false, forKey: tracksWebsitesKey)
    }

    private static let browsers: [String: (name: String, tabProperty: String)] = [
        "com.apple.Safari": ("Safari", "current tab"),
        "com.google.Chrome": ("Google Chrome", "active tab"),
        "ai.perplexity.comet": ("Comet", "active tab"),
        "company.thebrowser.Browser": ("Arc", "active tab"),
        "com.brave.Browser": ("Brave", "active tab"),
        "com.microsoft.edgemac": ("Microsoft Edge", "active tab"),
    ]

    static func isBrowser(_ bundleID: String) -> Bool { browsers[bundleID] != nil }

    private func refreshDomain() {
        guard tracksWebsites, let bundleID = frontBundleID, let browser = Self.browsers[bundleID],
              !blockedBrowsers.contains(browser.name) else { return }
        let source = """
        with timeout of 2 seconds
            tell application id "\(bundleID)"
                if (count of windows) is 0 then return ""
                return URL of \(browser.tabProperty) of front window
            end tell
        end timeout
        """
        // NSAppleScript waits on the browser, so it runs off the main thread; the serial queue keeps one script at a time.
        scriptQueue.async { [weak self] in
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            let url = result?.stringValue
            let code = error?[NSAppleScript.errorNumber] as? Int
            Task { @MainActor in
                guard let self, self.frontBundleID == bundleID else { return }
                if code == -1743 { // errAEEventNotPermitted: Automation is off for this browser.
                    self.blockedBrowsers.insert(browser.name)
                    return
                }
                let domain = url.flatMap { URL(string: $0)?.host?.lowercased() }
                    .map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
                if domain != self.frontDomain {
                    self.flush()
                    self.frontDomain = domain
                }
            }
        }
    }

    // MARK: - Categories

    private func appCategory(_ bundleID: String) -> Category {
        if let cached = categoryCache[bundleID] { return cached }
        let category = Self.appOverrides[bundleID] ?? {
            guard bundleID != Bundle.main.bundleIdentifier else { return .productivity }
            let type = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
                .flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String }
            return Self.category(forAppStoreType: type)
        }()
        categoryCache[bundleID] = category
        return category
    }

    /// Apps whose Info.plist has no category (or a misleading one), placed the way Screen Time would.
    private static let appOverrides: [String: Category] = [
        "com.apple.MobileSMS": .social, "com.apple.FaceTime": .social, "com.hnc.Discord": .social,
        "net.whatsapp.WhatsApp": .social, "desktop.WhatsApp": .social, "ru.keepcoder.Telegram": .social,
        "org.telegram.desktop": .social, "com.facebook.archon": .social,
        "com.apple.Music": .entertainment, "com.spotify.client": .entertainment, "com.apple.TV": .entertainment,
        "com.apple.podcasts": .entertainment,
        "com.apple.dt.Xcode": .development, "com.microsoft.VSCode": .development,
        "com.todesktop.230313mzl4w4u92": .development, "com.apple.Terminal": .development,
        "com.googlecode.iterm2": .development, "dev.warp.Warp-Stable": .development,
        "com.tinyspeck.slackmacgap": .productivity, "com.apple.mail": .productivity, "com.apple.iCal": .productivity,
        "com.apple.Notes": .productivity, "com.apple.reminders": .productivity, "notion.id": .productivity,
    ]

    private static func category(forAppStoreType type: String?) -> Category {
        guard let type = type?.replacingOccurrences(of: "public.app-category.", with: "") else { return .other }
        switch type {
        case "social-networking":
            return .social
        case "entertainment", "games", "video", "music", "sports":
            return .entertainment
        case _ where type.hasSuffix("-games"):
            return .entertainment
        case "developer-tools":
            return .development
        case "productivity", "business", "education", "reference", "finance", "graphics-design", "photography":
            return .productivity
        default:
            return .other
        }
    }

    private static let domainCategories: [(String, Category)] = [
        ("instagram.com", .social), ("facebook.com", .social), ("x.com", .social), ("twitter.com", .social),
        ("tiktok.com", .social), ("reddit.com", .social), ("snapchat.com", .social), ("linkedin.com", .social),
        ("threads.net", .social), ("threads.com", .social), ("pinterest.com", .social), ("tumblr.com", .social),
        ("bsky.app", .social), ("discord.com", .social), ("messenger.com", .social), ("web.whatsapp.com", .social),
        ("web.telegram.org", .social), ("mastodon.social", .social),
        ("youtube.com", .entertainment), ("netflix.com", .entertainment), ("twitch.tv", .entertainment),
        ("hulu.com", .entertainment), ("disneyplus.com", .entertainment), ("primevideo.com", .entertainment),
        ("max.com", .entertainment), ("spotify.com", .entertainment),
        ("github.com", .development), ("stackoverflow.com", .development), ("developer.apple.com", .development),
        ("gitlab.com", .development),
        ("docs.google.com", .productivity), ("drive.google.com", .productivity), ("mail.google.com", .productivity),
        ("calendar.google.com", .productivity), ("notion.so", .productivity), ("instructure.com", .productivity),
        ("claude.ai", .productivity), ("chatgpt.com", .productivity), ("perplexity.ai", .productivity),
        ("figma.com", .productivity),
    ]

    static func category(forDomain domain: String) -> Category? {
        domainCategories.first { domain == $0.0 || domain.hasSuffix("." + $0.0) }?.1
    }

    /// False for background helpers (LSUIElement / LSBackgroundOnly), which older data may still contain.
    func isListable(_ bundleID: String) -> Bool {
        if let cached = listableCache[bundleID] { return cached }
        let info = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).flatMap { Bundle(url: $0)?.infoDictionary }
        let flag: (String) -> Bool = { key in
            (info?[key] as? Bool) ?? ((info?[key] as? String).map { $0 == "1" || $0.lowercased() == "yes" } ?? false)
        }
        let listable = !(flag("LSUIElement") || flag("LSBackgroundOnly"))
        listableCache[bundleID] = listable
        return listable
    }

    func category(forApp bundleID: String) -> Category {
        Self.isBrowser(bundleID) ? .web : appCategory(bundleID)
    }

    // MARK: - Queries

    static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    func usage(daysBack: Int) -> DayUsage {
        let date = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date())!
        return days[Self.dayKey(date)] ?? DayUsage()
    }

    // MARK: - Storage (Application Support, this Mac only)

    /// The suffix of the account whose usage is loaded; nil before anyone signs in (nothing is saved then).
    private var loadedSuffix: String?

    private var storeURL: URL? {
        guard let loadedSuffix, !loadedSuffix.isEmpty else { return nil }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LockenTestApp", isDirectory: true)
            .appendingPathComponent("screen-usage\(loadedSuffix).json")
    }

    private func load() {
        guard let url = storeURL, let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode([String: DayUsage].self, from: data) else { return }
        days = stored
    }

    private func save() {
        lastSave = Date()
        guard let url = storeURL else { return }
        let cutoff = Self.dayKey(Calendar.current.date(byAdding: .day, value: -Self.keepDays, to: Date())!)
        days = days.filter { $0.key >= cutoff }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(days).write(to: url, options: .atomic)
        } catch {
            print("ScreenUsageTracker: couldn't save usage: \(error)")
        }
    }
}

/// "Open at login": macOS starts Locken when the student logs in, with its window hidden, so Analytics keeps measuring
/// after a restart. Off until the student turns it on; macOS lists it in System Settings › General › Login Items, where
/// it can also be removed. Quitting Locken still stops the measuring until it opens again.
@MainActor
final class LaunchAtLogin: ObservableObject {
    static let shared = LaunchAtLogin()

    @Published private(set) var status = SMAppService.mainApp.status

    var isOn: Bool { status == .enabled || status == .requiresApproval }
    /// Turned on, but macOS wants the student to allow it in Login Items first.
    var needsApproval: Bool { status == .requiresApproval }

    /// The student can change it in System Settings too, so the card reads it again when it appears.
    func refresh() { status = SMAppService.mainApp.status }

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            print("LaunchAtLogin: couldn't turn \(on ? "on" : "off"): \(error)")
        }
        refresh()
    }

    func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }

    /// True when macOS opened Locken because the student logged in, not because the student opened it. Only valid
    /// while the launch event is being handled, so read it in `applicationDidFinishLaunching`.
    static func openedAtLogin() -> Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        return event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == AEKeyword(keyAELaunchedAsLogInItem)
    }
}
