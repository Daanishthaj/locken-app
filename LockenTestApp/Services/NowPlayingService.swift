import AppKit
import Foundation

/// The song playing in Spotify or Apple Music (or music and video playing in a browser tab: YouTube, YouTube Music,
/// Spotify's web player, SoundCloud), and how long each song has played. It can also turn other media down while
/// Locken talks (`duck`).
///
/// macOS has no public now-playing API for third-party apps (MediaRemote is private and locked down since
/// macOS 15.4), so this asks the players themselves over Apple Events. It only talks to a player that is
/// already running, so it never launches one, and it asks for Automation permission only when the user
/// presses Connect in the sidebar music widget.
@MainActor
final class NowPlayingService: ObservableObject {
    static let shared = NowPlayingService()

    enum Player: String, CaseIterable {
        case spotify = "com.spotify.client"
        case music = "com.apple.Music"
        // Browsers: Safari and the Chromium family answer the same tab commands (see `AppBlockingManager.browsers`).
        case safari = "com.apple.Safari"
        case chrome = "com.google.Chrome"
        case arc = "company.thebrowser.Browser"
        case brave = "com.brave.Browser"
        case edge = "com.microsoft.edgemac"
        case comet = "ai.perplexity.comet"

        var name: String {
            switch self {
            case .spotify: return "Spotify"
            case .music: return "Music"
            case .safari: return "Safari"
            case .chrome: return "Chrome"
            case .arc: return "Arc"
            case .brave: return "Brave"
            case .edge: return "Edge"
            case .comet: return "Comet"
            }
        }
        var isBrowser: Bool { self != .spotify && self != .music }
        var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: rawValue).isEmpty }
    }

    struct Track: Equatable {
        let title: String
        let artist: String
        let player: Player
        let isPlaying: Bool
        /// Album art as an https URL (Spotify) or a PNG data URL (Music).
        var artworkURL: String?

        /// Songs are counted by title and artist.
        var key: String { artist.isEmpty ? title : "\(title) — \(artist)" }
    }

    enum Access: Equatable {
        case granted, needsConsent, denied, notRunning
    }

    @Published private(set) var track: Track?
    @Published private(set) var access: [Player: Access] = [:]
    /// Seconds each song has played, and the part of that during focus sessions. Kept on this Mac.
    // Not @Published: they grow on every poll while music plays, and nothing on screen shows them, so announcing each change
    // re-rendered the sidebar every 2 seconds. They are announced when they're saved (every 30 s).
    private(set) var listenSeconds: [String: Double] = [:]
    private(set) var focusListenSeconds: [String: Double] = [:]

    /// Spotify and Music only: the sidebar card's prompts are about them, not about every browser that happens to be open.
    var runningPlayers: [Player] { Player.allCases.filter { !$0.isBrowser && $0.isRunning } }
    var runningBrowsers: [Player] { Player.allCases.filter { $0.isBrowser && $0.isRunning } }
    var needsConsent: Bool { access.contains { !$0.key.isBrowser && $0.value == .needsConsent } }
    var deniedPlayers: [Player] { access.filter { !$0.key.isBrowser && $0.value == .denied }.map(\.key) }
    /// Browsers that allowed Automation but have "Allow JavaScript from Apple Events" off, so their tabs can't be read.
    @Published private(set) var javaScriptOff: Set<Player> = []
    /// What's playing in browser tabs, read every few seconds.
    private var browserTracks: [Track] = []
    private var pollCount = 0
    private var pollInFlight = false

    var mostFocusedSong: String? { focusListenSeconds.max { $0.value < $1.value }?.key }
    var mostPlayedSong: String? { listenSeconds.max { $0.value < $1.value }?.key }

    /// Music's artwork comes as image data, so it's read once per song and kept here.
    private var musicArtwork: (key: String, url: String?)?
    private let pollInterval: TimeInterval = 2
    private var lastPoll = Date()
    private var lastSave = Date()
    private var timer: Timer?
    private let queue = DispatchQueue(label: "com.locken.LockenTestApp.now-playing")
    private static let listenKeyBase = "nowPlayingListenSeconds"
    private static let focusListenKeyBase = "nowPlayingFocusListenSeconds"
    /// Per account, so two accounts on one Mac don't share music stats.
    private var listenKey: String { Self.listenKeyBase + AccountScope.suffix }
    private var focusListenKey: String { Self.focusListenKeyBase + AccountScope.suffix }

    private init() {}

    /// Loads the signed-in account's listening stats.
    func activateAccount() {
        AccountScope.adoptLegacyDefault(Self.listenKeyBase)
        AccountScope.adoptLegacyDefault(Self.focusListenKeyBase)
        listenSeconds = UserDefaults.standard.dictionary(forKey: listenKey) as? [String: Double] ?? [:]
        focusListenSeconds = UserDefaults.standard.dictionary(forKey: focusListenKey) as? [String: Double] ?? [:]
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        restoreLeftovers()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.save()
                self?.unduck(wait: true)
            }
        }
        poll()
    }

    /// Shows the macOS Automation prompt for each running player that hasn't been asked yet.
    func connect() {
        let players = runningPlayers
        queue.async {
            let results = players.map { ($0, Self.permission(for: $0, ask: true)) }
            Task { @MainActor in
                for (player, access) in results { self.access[player] = access }
                self.poll()
            }
        }
    }

    /// Shows the macOS Automation prompt for each running browser that hasn't been asked yet.
    func connectBrowsers() {
        let browsers = runningBrowsers
        queue.async {
            let results = browsers.map { ($0, Self.permission(for: $0, ask: true)) }
            Task { @MainActor in
                for (browser, access) in results { self.access[browser] = access }
                self.pollCount = 0
                self.poll()
            }
        }
    }

    // MARK: Controls

    func playPause() { send("playpause") }
    func nextTrack() { send("next track") }
    func previousTrack() { send("previous track") }

    private func send(_ command: String) {
        guard let player = track?.player ?? runningPlayers.first(where: { access[$0] == .granted }) else { return }
        if player.isBrowser {
            // A browser tab can be paused; skipping songs isn't something a page lets another app do.
            guard command == "playpause" else { return }
            queue.async {
                _ = Self.runInMediaTabs(player, js: "document.querySelectorAll('video,audio').forEach(function(e){if(!e.paused)e.pause()})")
                Task { @MainActor in self.poll() }
            }
            return
        }
        let source = "with timeout of 2 seconds\ntell application id \"\(player.rawValue)\" to \(command)\nend timeout"
        queue.async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            Task { @MainActor in self.poll() }
        }
    }

    // MARK: Polling

    private func poll() {
        // A slow poll (many browser tabs) isn't stacked on: the next timer tick tries again.
        guard !pollInFlight else { return }
        pollInFlight = true
        let players = Player.allCases.filter(\.isRunning)
        pollCount += 1
        // Browsers are read every third poll (about 6 s).
        let readBrowsers = pollCount % 3 == 1
        queue.async {
            var accessResults: [Player: Access] = [:]
            var found: [Track] = []
            var browserFound: [Track]? = readBrowsers ? [] : nil
            var scriptOff = Set<Player>()
            for player in Player.allCases {
                guard players.contains(player) else {
                    accessResults[player] = .notRunning
                    continue
                }
                let access = Self.permission(for: player, ask: false)
                accessResults[player] = access
                guard access == .granted else { continue }
                if player.isBrowser {
                    guard readBrowsers else { continue }
                    let result = Self.readBrowser(player)
                    browserFound?.append(contentsOf: result.tracks)
                    if result.javaScriptOff { scriptOff.insert(player) }
                } else if let track = Self.readTrack(from: player) {
                    found.append(track)
                }
            }
            Task { @MainActor in
                self.pollInFlight = false
                if self.access != accessResults { self.access = accessResults }
                if let browserFound {
                    self.browserTracks = browserFound
                    if self.javaScriptOff != scriptOff { self.javaScriptOff = scriptOff }
                }
                // A playing player wins over a paused one; Spotify and Music come before browser tabs.
                let all = found + self.browserTracks
                self.update(self.withMusicArtwork(all.first(where: \.isPlaying) ?? all.first))
            }
        }
    }

    private func withMusicArtwork(_ track: Track?) -> Track? {
        guard var track, track.player == .music else { return track }
        if let cached = musicArtwork, cached.key == track.key {
            track.artworkURL = cached.url
            return track
        }
        let key = track.key
        musicArtwork = (key, nil)
        queue.async {
            let url = Self.readMusicArtwork()
            Task { @MainActor in
                guard self.musicArtwork?.key == key else { return }
                self.musicArtwork = (key, url)
                if let current = self.track, current.key == key {
                    var updated = current
                    updated.artworkURL = url
                    self.track = updated
                }
            }
        }
        return track
    }

    private func update(_ current: Track?) {
        let now = Date()
        // Count the time since the last poll toward the song that was playing (a longer gap means the Mac slept).
        let elapsed = min(now.timeIntervalSince(lastPoll), pollInterval * 3)
        lastPoll = now
        // Only music apps are counted: what a browser plays (lectures, videos) isn't kept as listening history.
        if let playing = track, playing.isPlaying, !playing.player.isBrowser {
            listenSeconds[playing.key, default: 0] += elapsed
            if TestAppStateManager.shared.isTimerActive {
                focusListenSeconds[playing.key, default: 0] += elapsed
            }
        }
        if current != track { track = current }
        if now.timeIntervalSince(lastSave) > 30 { save() }
    }

    private static func topSongs(_ songs: [String: Double], keep: Int = 200) -> [String: Double] {
        guard songs.count > keep else { return songs }
        return Dictionary(uniqueKeysWithValues: songs.sorted { $0.value > $1.value }.prefix(keep).map { ($0.key, $0.value) })
    }

    private func save() {
        lastSave = Date()
        // Keep only the 200 most-listened songs, so this never grows into a full listening history.
        objectWillChange.send()
        listenSeconds = Self.topSongs(listenSeconds)
        focusListenSeconds = Self.topSongs(focusListenSeconds)
        UserDefaults.standard.set(listenSeconds, forKey: listenKey)
        UserDefaults.standard.set(focusListenSeconds, forKey: focusListenKey)
    }

    // MARK: Apple Events (run on `queue`)

    nonisolated private static func permission(for player: Player, ask: Bool) -> Access {
        let target = NSAppleEventDescriptor(bundleIdentifier: player.rawValue)
        guard let desc = target.aeDesc else { return .notRunning }
        let status = AEDeterminePermissionToAutomateTarget(desc, AEEventClass(kCoreEventClass), AEEventID(kAEGetData), ask)
        switch Int(status) {
        case Int(noErr): return .granted
        case -1744: return .needsConsent // errAEEventWouldRequireUserConsent
        case -600: return .notRunning   // procNotFound
        default: return .denied          // errAEEventNotPermitted and anything else
        }
    }

    nonisolated private static func readTrack(from player: Player) -> Track? {
        let source = """
        with timeout of 2 seconds
            tell application id "\(player.rawValue)"
                set playerState to player state as string
                if playerState is "stopped" then return "stopped"
                return playerState & linefeed & (name of current track) & linefeed & (artist of current track)\(player == .spotify ? " & linefeed & (artwork url of current track)" : "")
            end tell
        end timeout
        """
        var error: NSDictionary?
        guard let output = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue else { return nil }
        let parts = output.components(separatedBy: "\n")
        guard parts.count >= 3, !parts[1].isEmpty else { return nil }
        let artwork = parts.count >= 4 && parts[3].hasPrefix("https://") ? parts[3] : nil
        return Track(title: parts[1], artist: parts[2], player: player, isPlaying: parts[0] == "playing", artworkURL: artwork)
    }

    /// Music's current artwork, scaled to 160pt and returned as a PNG data URL.
    nonisolated private static func readMusicArtwork() -> String? {
        let source = """
        with timeout of 2 seconds
            tell application id "\(Player.music.rawValue)"
                if (count of artworks of current track) is 0 then return missing value
                return data of artwork 1 of current track
            end tell
        end timeout
        """
        var error: NSDictionary?
        guard let data = NSAppleScript(source: source)?.executeAndReturnError(&error).data,
              let image = NSImage(data: data) else { return nil }
        let side: CGFloat = 160
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side), bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)
        guard let bitmap else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        return "data:image/png;base64," + png.base64EncodedString()
    }

    // MARK: Browser media (Apple Events + a fixed line of JavaScript, run on `queue`)

    /// Only tabs on these sites are asked anything.
    nonisolated private static let mediaSites = ["music.youtube.com", "youtube.com/watch", "youtu.be/", "open.spotify.com", "soundcloud.com"]

    /// Runs `js` in every open tab on a media site and returns what each one answered. `javaScriptOff` means the browser
    /// refused because "Allow JavaScript from Apple Events" is off (Chromium: View › Developer; Safari: Develop menu).
    /// `js` must contain no double quotes or backslashes: it's placed inside an AppleScript string.
    nonisolated private static func runInMediaTabs(_ player: Player, js: String) -> (lines: [String], javaScriptOff: Bool) {
        let run = player == .safari ? "do JavaScript \"\(js)\" in t" : "execute t javascript \"\(js)\""
        let sites = mediaSites.map { "u contains \"\($0)\"" }.joined(separator: " or ")
        let source = """
        with timeout of 4 seconds
            tell application id "\(player.rawValue)"
                set found to {}
                set jsOff to false
                repeat with w in windows
                    try
                        -- One request for all of a window's addresses, not one per tab.
                        set urls to URL of tabs of w
                        repeat with i from 1 to count of urls
                            set u to item i of urls
                            if u is not missing value and (\(sites)) then
                                try
                                    set t to tab i of w
                                    set end of found to (\(run))
                                on error errText
                                    if errText contains "JavaScript" then set jsOff to true
                                end try
                            end if
                        end repeat
                    end try
                end repeat
                if jsOff and (count of found) is 0 then return "!js-off"
                set savedDelimiters to AppleScript's text item delimiters
                set AppleScript's text item delimiters to linefeed
                set report to found as text
                set AppleScript's text item delimiters to savedDelimiters
                return report
            end tell
        end timeout
        """
        var error: NSDictionary?
        guard let output = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue else { return ([], false) }
        if output == "!js-off" { return ([], true) }
        return (output.components(separatedBy: "\n").filter { !$0.isEmpty }, false)
    }

    /// Music or video playing in a browser tab, from the page's own media session (title, artist, artwork) or, failing
    /// that, its tab title. Only tabs that are playing are returned. The page's answer is untrusted: it's cut to a
    /// length and the artwork must be an https address.
    nonisolated private static func readBrowser(_ player: Player) -> (tracks: [Track], javaScriptOff: Bool) {
        let js = "(function(){var s=navigator.mediaSession,m=s&&s.metadata,e=document.querySelector('video,audio'),a=m&&m.artwork&&m.artwork.length?m.artwork[m.artwork.length-1].src:'';return JSON.stringify({t:String(m&&m.title||document.title),a:String(m&&m.artist||''),p:!!((s&&s.playbackState==='playing')||(e&&!e.paused&&!e.ended)),i:String(a)})})()"
        let result = runInMediaTabs(player, js: js)
        let tracks = result.lines.compactMap { line -> Track? in
            guard let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  object["p"] as? Bool == true,
                  let title = (object["t"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
            let artwork = (object["i"] as? String).flatMap { $0.hasPrefix("https://") && $0.count < 500 ? $0 : nil }
            return Track(title: String(title.prefix(120)), artist: String(((object["a"] as? String) ?? "").prefix(120)),
                         player: player, isPlaying: true, artworkURL: artwork)
        }
        return (tracks, result.javaScriptOff)
    }

    // MARK: Lowering other media while Locken talks

    /// What was turned down and from what, so it can be put back. Only touched on `queue`. It is also kept in UserDefaults
    /// while something is turned down, so a crash or force-quit while Locken talks doesn't leave the music quiet: the next
    /// launch puts it back.
    private final class DuckLedger: @unchecked Sendable {
        var volumes: [Player: Int] = [:]
        var browsers: Set<Player> = []

        func save() {
            guard !volumes.isEmpty || !browsers.isEmpty else {
                UserDefaults.standard.removeObject(forKey: NowPlayingService.duckedKey)
                return
            }
            UserDefaults.standard.set(
                ["volumes": Dictionary(uniqueKeysWithValues: volumes.map { ($0.key.rawValue, $0.value) }), "browsers": browsers.map(\.rawValue)],
                forKey: NowPlayingService.duckedKey
            )
        }

        func load() {
            let saved = UserDefaults.standard.dictionary(forKey: NowPlayingService.duckedKey)
            volumes = Dictionary(uniqueKeysWithValues: ((saved?["volumes"] as? [String: Int]) ?? [:]).compactMap { key, value in Player(rawValue: key).map { ($0, value) } })
            browsers = Set(((saved?["browsers"] as? [String]) ?? []).compactMap(Player.init(rawValue:)))
        }
    }
    private let ledger = DuckLedger()
    nonisolated private static let duckedKey = "assistant.duckedMedia"
    nonisolated private static let duckedShare = 0.25
    /// Locken's voice starts at once, so the music goes down quickly; it comes back up more slowly.
    nonisolated private static let fadeDownMs = 500
    nonisolated private static let fadeUpMs = 800

    /// The browser media volume script: `factor` below 1 fades every audio and video element down over `ms` (remembering its
    /// volume on the element), 1 fades it back up and forgets that. The ramp follows the clock, not a step count, so a tab
    /// whose timers are slowed still lands on the right volume. `ms` 0 jumps straight there.
    nonisolated private static func volumeJS(_ factor: Double, ms: Int) -> String {
        "(function(f,ms){document.querySelectorAll('video,audio').forEach(function(e){if(e.__lockenTimer){clearInterval(e.__lockenTimer);e.__lockenTimer=null}if(f<1&&e.__lockenVol==null)e.__lockenVol=e.volume;if(e.__lockenVol==null)return;var a=e.volume,b=f<1?Math.max(0,e.__lockenVol*f):e.__lockenVol,t=Date.now();function done(){e.volume=b;if(f>=1)delete e.__lockenVol}if(ms<=0){done();return}e.__lockenTimer=setInterval(function(){var p=Math.min(1,(Date.now()-t)/ms);if(p>=1){clearInterval(e.__lockenTimer);e.__lockenTimer=null;done();return}e.volume=Math.min(1,Math.max(0,a+(b-a)*p*p*(3-2*p)))},40)})})(\(factor),\(ms))"
    }

    nonisolated private static func volume(of player: Player) -> Int? {
        let source = "with timeout of 2 seconds\ntell application id \"\(player.rawValue)\" to return (sound volume as integer)\nend timeout"
        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error), error == nil else { return nil }
        return Int(result.int32Value)
    }

    nonisolated private static func isPlaying(_ player: Player) -> Bool {
        let source = "with timeout of 2 seconds\ntell application id \"\(player.rawValue)\" to return (player state as string) is \"playing\"\nend timeout"
        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error), error == nil else { return false }
        return result.booleanValue
    }

    nonisolated private static func setVolume(_ volume: Int, of player: Player) {
        let source = "with timeout of 2 seconds\ntell application id \"\(player.rawValue)\" to set sound volume to \(max(0, min(100, volume)))\nend timeout"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
    }

    /// Moves the player's volume from `from` to `to` over `seconds` along a smooth curve (slow start, slow end), in one
    /// Apple Event script so the steps aren't spaced out by round trips. Blocks `queue` for that long.
    nonisolated private static func fadeVolume(of player: Player, from: Int, to: Int, seconds: Double) {
        let steps = 12
        let levels = (1...steps).map { i -> Int in
            let p = Double(i) / Double(steps)
            let eased = p * p * (3 - 2 * p)
            return max(0, min(100, Int((Double(from) + Double(to - from) * eased).rounded())))
        }
        let source = """
        with timeout of \(Int(seconds) + 5) seconds
            tell application id "\(player.rawValue)"
                repeat with level in {\(levels.map(String.init).joined(separator: ", "))}
                    set sound volume to (contents of level)
                    delay \(String(format: "%.3f", seconds / Double(steps)))
                end repeat
            end tell
        end timeout
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
    }

    /// Turns down Spotify and Music if they're playing, and the media tabs of browsers that allowed it. Called when Locken
    /// starts talking; `unduck` puts everything back.
    func duck() {
        let granted = Player.allCases.filter { $0.isRunning && access[$0] == .granted }
        guard !granted.isEmpty else { return }
        let ledger = ledger
        queue.async {
            for player in granted {
                if player.isBrowser {
                    _ = Self.runInMediaTabs(player, js: Self.volumeJS(Self.duckedShare, ms: Self.fadeDownMs))
                    ledger.browsers.insert(player)
                } else if ledger.volumes[player] == nil, Self.isPlaying(player), let volume = Self.volume(of: player), volume > 0 {
                    // Written down before the volume changes, so a crash right after still finds it.
                    ledger.volumes[player] = volume
                    ledger.save()
                    Self.fadeVolume(of: player, from: volume, to: max(1, Int(Double(volume) * Self.duckedShare)), seconds: Double(Self.fadeDownMs) / 1000)
                    continue
                }
                if player.isBrowser { ledger.save() }
            }
        }
    }

    /// Puts back what the ledger says was turned down, then empties it. A player whose volume the student changed meanwhile
    /// is left alone. `fade` is off when quitting or restoring after a crash, where waiting isn't an option.
    nonisolated private static func putBack(_ ledger: DuckLedger, fade: Bool) {
        for (player, original) in ledger.volumes {
            let ducked = max(1, Int(Double(original) * duckedShare))
            guard let now = volume(of: player), abs(now - ducked) <= 2 else { continue }
            if fade { fadeVolume(of: player, from: now, to: original, seconds: Double(fadeUpMs) / 1000) } else { setVolume(original, of: player) }
        }
        for browser in ledger.browsers { _ = runInMediaTabs(browser, js: volumeJS(1, ms: fade ? fadeUpMs : 0)) }
        ledger.volumes = [:]
        ledger.browsers = []
        ledger.save()
    }

    /// Puts back what `duck` turned down. `wait` is for quitting: it waits at most 1.5 s, because the queue can be busy with a
    /// browser scan; whatever isn't put back by then is put back at the next launch.
    func unduck(wait: Bool = false) {
        let ledger = ledger
        guard wait else {
            queue.async { Self.putBack(ledger, fade: true) }
            return
        }
        let done = DispatchGroup()
        done.enter()
        queue.async {
            Self.putBack(ledger, fade: false)
            done.leave()
        }
        _ = done.wait(timeout: .now() + 1.5)
    }

    /// At launch: puts back anything a crash or force-quit left turned down.
    private func restoreLeftovers() {
        guard UserDefaults.standard.object(forKey: Self.duckedKey) != nil else { return }
        let ledger = ledger
        queue.async {
            ledger.load()
            Self.putBack(ledger, fade: false)
        }
    }
}
