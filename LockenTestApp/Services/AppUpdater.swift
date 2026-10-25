import AppKit
import CryptoKit
import Foundation

/// Signed in-app updates. Locken checks the website's `version.json` at launch and every 6 hours. An update is
/// installed only when the release key's Ed25519 signature covers its version, build and SHA-256, and the
/// downloaded DMG matches that SHA-256. The private key lives only in the publisher's Keychain
/// (`scripts/release-signing.swift`), so a copy of the website alone can't produce an update this app accepts.
/// The new app replaces the installed one only if its code signature verifies and carries Locken's team ID;
/// otherwise the installed app is kept.
@MainActor
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()

    static let site = "https://locken-app.vercel.app"

    /// Public half of the release signing key (the same key that signed the old app's updates).
    nonisolated static let updatePublicKey = "2MTenzJXoJMSwziVPfiWXMpS/QTjJLZWh4S49UbNDRs="

    struct RemoteVersion: Decodable {
        let version: String
        let build: Int
        let notes: String
        let sha256: String?
        let signature: String?
    }

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, notes: String)
        case installing(String)
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    @Published var isBannerDismissed = false
    /// Shows the "What's new" pop-up. Opened when Check for Updates finds one, or from the banner.
    @Published var isWhatsNewPresented = false
    /// When the server last answered, shown in Settings so a check visibly happened.
    @Published private(set) var lastChecked: Date?
    /// The newest version the website offers, from the last check.
    @Published private(set) var serverVersion: String?

    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    let currentBuild = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0

    private var latest: RemoteVersion?
    private var timer: Timer?

    private init() {}

    /// Starts the launch check and the 6-hourly checks.
    func start() {
        guard timer == nil else { return }
        Task { await check() }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { _ in
            Task { @MainActor in await AppUpdater.shared.check() }
        }
    }

    var isUpdateAvailable: Bool {
        if case .available = status { return true }
        return false
    }

    /// On the sign-in screen nothing is in progress, so a signed update installs straight away instead of asking
    /// (the same download, checksum, signature and code-signature checks as clicking Update).
    func installIfOnSignInScreen() {
        guard isUpdateAvailable, canInstallInPlace, AuthManager.shared.phase == .signedOut else { return }
        install()
    }

    /// Updates install in place only when Locken runs from Applications (not from a build folder or the DMG).
    var canInstallInPlace: Bool {
        Bundle.main.bundleURL.deletingLastPathComponent().path == "/Applications"
    }

    func check(userInitiated: Bool = false) async {
        if case .installing = status { return }
        status = .checking
        var request = URLRequest(url: URL(string: Self.site + "/version.json")!)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10
        guard let (data, response) = try? await SecureNetwork.session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let remote = try? JSONDecoder().decode(RemoteVersion.self, from: data) else {
            status = userInitiated ? .failed("Couldn't reach the update server. Try again later.") : .idle
            return
        }
        lastChecked = Date()
        serverVersion = "\(remote.version) (\(remote.build))"
        // Only a newer build that carries a valid signature counts as an update; anything else is ignored.
        if remote.build > currentBuild, let sha = remote.sha256?.lowercased(), sha.count == 64,
           Self.isSigned(version: remote.version, build: remote.build, sha256: sha, signature: remote.signature) {
            latest = remote
            isBannerDismissed = false
            status = .available(version: remote.version, notes: remote.notes)
            if userInitiated { isWhatsNewPresented = true }
            installIfOnSignInScreen()
        } else {
            latest = nil
            status = .upToDate
        }
    }

    /// Runs `path` with `arguments` in a new session (POSIX_SPAWN_SETSID) and doesn't wait for it.
    nonisolated static func spawnDetached(_ path: String, arguments: [String]) throws {
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))
        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        posix_spawn_file_actions_addopen(&fileActions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&fileActions, 1, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&fileActions, 2, "/dev/null", O_WRONLY, 0)
        let argv = ([path] + arguments).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        let result = posix_spawn(&pid, path, &fileActions, &attributes, argv, environ)
        guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(result)) }
    }

    /// True when `signature` is the release key's signature over this exact version, build and checksum.
    nonisolated static func isSigned(version: String, build: Int, sha256: String, signature: String?,
                                     publicKey: String = updatePublicKey) -> Bool {
        guard let signature, let signatureData = Data(base64Encoded: signature),
              let keyData = Data(base64Encoded: publicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else { return false }
        let message = Data("locken-update|\(version)|\(build)|\(sha256.lowercased())".utf8)
        return key.isValidSignature(signatureData, for: message)
    }

    /// Downloads the DMG into a private folder, checks it against the signed SHA-256, then hands it to a small
    /// script that replaces /Applications/Locken.app and reopens it once this copy has quit.
    func install() {
        guard let latest, let expected = latest.sha256?.lowercased(),
              Self.isSigned(version: latest.version, build: latest.build, sha256: expected, signature: latest.signature) else {
            status = .failed("This update isn't signed by Locken, so it wasn't installed.")
            return
        }
        guard canInstallInPlace else {
            NSWorkspace.shared.open(URL(string: Self.site)!)
            status = .failed("Move Locken to Applications to update in place. The website has the new version.")
            return
        }
        status = .installing("Downloading Locken \(latest.version)…")
        Task {
            do {
                let work = FileManager.default.temporaryDirectory.appendingPathComponent("LockenUpdate-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let (downloaded, response) = try await SecureNetwork.session.download(from: URL(string: Self.site + "/Locken.dmg")!)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                let dmg = work.appendingPathComponent("Locken.dmg")
                try FileManager.default.moveItem(at: downloaded, to: dmg)
                let digest = SHA256.hash(data: try Data(contentsOf: dmg, options: .mappedIfSafe)).map { String(format: "%02x", $0) }.joined()
                guard digest == expected else {
                    try? FileManager.default.removeItem(at: work)
                    status = .failed("The download didn't match the signed checksum, so it wasn't installed.")
                    return
                }
                let script = """
                #!/bin/bash
                set -u
                WORK="$1"
                OLD_PID="$2"
                MOUNT="$WORK/mount"
                # Each step goes to a log, so a failed update can be explained afterwards (no personal data in it).
                LOG="$HOME/Library/Logs/Locken/updater.log"
                mkdir -p "$(dirname "$LOG")"
                exec >>"$LOG" 2>&1
                echo "--- $(date '+%Y-%m-%d %H:%M:%S') installing from $WORK"
                # Wait for this copy of Locken to quit (up to 20 s), then make sure it's gone before replacing it.
                for i in $(seq 1 40); do kill -0 "$OLD_PID" 2>/dev/null || break; sleep 0.5; done
                kill -TERM "$OLD_PID" 2>/dev/null; sleep 1
                mkdir -p "$MOUNT"
                if hdiutil attach "$WORK/Locken.dmg" -readonly -nobrowse -quiet -mountpoint "$MOUNT"; then
                  APP="$(find "$MOUNT" -maxdepth 1 -name '*.app' -print -quit)"
                  if [ -n "$APP" ]; then
                    # Stage the new copy first. Extended attributes (Finder/iCloud tags, the download quarantine)
                    # are cleared only on this staged copy, which came from the DMG whose SHA-256 was signed.
                    STAGED="$WORK/Locken.app"
                    cp -R "$APP" "$STAGED"
                    xattr -cr "$STAGED" 2>/dev/null
                    # Install only if the code signature is intact and it's Locken's own team. Never re-sign.
                    if codesign --verify --deep --strict "$STAGED" >/dev/null 2>&1 \
                       && codesign -dv "$STAGED" 2>&1 | grep -q "TeamIdentifier=P36B98NRT2"; then
                      if [ -d /Applications/Locken.app ]; then mv /Applications/Locken.app "$WORK/Locken-old.app"; fi
                      if ! mv "$STAGED" /Applications/Locken.app; then
                        # Couldn't move the new copy in: put the old one back.
                        [ -d "$WORK/Locken-old.app" ] && mv "$WORK/Locken-old.app" /Applications/Locken.app
                        echo "couldn't move the new copy into Applications; kept the old one"
                      else
                        echo "installed"
                      fi
                    else
                      echo "signature check failed; kept the old copy"
                    fi
                  else
                    echo "no app inside the download"
                  fi
                  hdiutil detach "$MOUNT" -quiet
                else
                  echo "couldn't open the download"
                fi
                rm -rf "$WORK"
                open /Applications/Locken.app
                """
                let scriptURL = work.appendingPathComponent("install.sh")
                try script.write(to: scriptURL, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
                // Started in its own session (setsid), so it isn't killed along with this app's process group when
                // Locken quits to make way for the new copy. Paths go in as arguments, never into the script text.
                try Self.spawnDetached(scriptURL.path, arguments: [work.path, String(ProcessInfo.processInfo.processIdentifier)])
                status = .installing("Installing…")
                try? await Task.sleep(for: .milliseconds(800))
                AppQuit.isAllowed = true // installing an update isn't held up by commitment mode
                AppQuit.reason = .update // a running session carries over to the new version
                NSApplication.shared.terminate(nil)
            } catch {
                status = .failed("The update couldn't be downloaded. Try again later.")
            }
        }
    }
}
