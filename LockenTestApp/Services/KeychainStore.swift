import Foundation
import Security

/// The network session for every request that carries a token or key, or returns account data (Supabase, Canvas,
/// AI providers, the breach check). Nothing is cached to disk and no cookies are kept, so responses such as the
/// signed-in user's email or a student's assignments never land in ~/Library/Caches.
enum SecureNetwork {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration)
    }()

    /// Removes anything earlier builds left in the shared on-disk cache.
    static func clearLegacyCache() {
        URLCache.shared.removeAllCachedResponses()
    }
}

/// Small wrapper over the macOS Keychain for secrets such as the Canvas access token and the AI API key.
/// Items are generic passwords readable only after first unlock, on this device only (never synced).
enum KeychainStore {
    @discardableResult
    static func set(_ value: String, service: String, account: String) -> Bool {
        delete(service: service, account: account)
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecSuccess { return true }
        // The delete didn't go through (an item saved by an older build of Locken, which this build may not be
        // allowed to delete): update its value in place instead, so a stale value is never left behind.
        if status == errSecDuplicateItem {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            return SecItemUpdate(query as CFDictionary, [kSecValueData as String: Data(value.utf8)] as CFDictionary) == errSecSuccess
        }
        return false
    }

    static func get(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// The signed-in account that this Mac's local data belongs to. `AuthGate` sets it on sign-in, so two accounts
/// on one Mac never see each other's screen usage, music stats, Canvas link or AI key.
@MainActor
enum AccountScope {
    private(set) static var userID: String?

    static func activate(_ id: String) {
        userID = id
    }

    /// Appended to file names, defaults keys and Keychain accounts. Empty until someone signs in.
    static var suffix: String {
        guard let userID else { return "" }
        return "-" + userID.filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    /// Moves a Keychain item saved before data was per account to the first account that signs in.
    static func adoptLegacyKeychainItem(service: String, account: String) {
        guard userID != nil, KeychainStore.get(service: service, account: account + suffix) == nil,
              let legacy = KeychainStore.get(service: service, account: account) else { return }
        KeychainStore.set(legacy, service: service, account: account + suffix)
        KeychainStore.delete(service: service, account: account)
    }

    /// The same for a UserDefaults value.
    static func adoptLegacyDefault(_ key: String) {
        let defaults = UserDefaults.standard
        guard userID != nil, defaults.object(forKey: key + suffix) == nil, let legacy = defaults.object(forKey: key) else { return }
        defaults.set(legacy, forKey: key + suffix)
        defaults.removeObject(forKey: key)
    }

    /// The same for a file in Application Support/LockenTestApp.
    static func adoptLegacyFile(named name: String, as scopedName: String) {
        guard userID != nil,
              let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("LockenTestApp", isDirectory: true) else { return }
        let legacy = folder.appendingPathComponent(name)
        let scoped = folder.appendingPathComponent(scopedName)
        guard FileManager.default.fileExists(atPath: legacy.path), !FileManager.default.fileExists(atPath: scoped.path) else { return }
        try? FileManager.default.moveItem(at: legacy, to: scoped)
    }

    /// Deletes this Mac's files and settings for an account (when the account itself is deleted).
    /// Keychain items are removed by their owners first (`CanvasAPIManager.unlink`, `AITaskFormatter.removeAPIKey`).
    /// Every per-account file (in Application Support/LockenTestApp, as "<name>-<user id>.json") and setting.
    /// Delete Account erases all of them, and Download My Data exports all of them.
    static let perAccountFiles = ["habits", "milestones", "notes", "stats", "screen-usage", "session", AssistantHistoryStore.fileName]
    @MainActor static var perAccountDefaultsKeys: [String] {
        ["nowPlayingListenSeconds", "nowPlayingFocusListenSeconds", "canvas.linkMethod", "canvas.host", "canvas.checkedOff",
         "profile.displayName", "blocker.userBlocked", "blocker.userAllowed", AgeGate.agreedKey,
         "feedback.firstSeen", "feedback.nextAsk", "feedback.done", WorkspaceLineup.keyBase,
         AgeGate.monthKey, AgeGate.yearKey, AppleNotesService.connectedKey]
    }

    private static var dataFolder: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LockenTestApp", isDirectory: true)
    }

    private static func scope(_ userID: String) -> String {
        "-" + userID.filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    static func eraseLocalData(for userID: String) {
        let scoped = scope(userID)
        if let folder = dataFolder {
            for name in perAccountFiles {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent("\(name)\(scoped).json"))
                // A file the app couldn't read is set aside as "<name>.json.unreadable"; it goes too.
                try? FileManager.default.removeItem(at: folder.appendingPathComponent("\(name)\(scoped).json.unreadable"))
            }
        }
        for key in perAccountDefaultsKeys {
            UserDefaults.standard.removeObject(forKey: key + scoped)
        }
        if self.userID == userID { self.userID = nil }
    }

    /// Everything Locken keeps about an account, as readable JSON (GDPR/CCPA access and portability). Secrets
    /// (session tokens, Canvas token or feed link, AI key) are left out; only whether they're set is noted.
    /// `server` is the account's own rows fetched from Locken's servers (`AuthManager.serverDataForExport()`).
    static func exportData(for userID: String, email: String, server: [String: Any]?) -> Data? {
        let scoped = scope(userID)
        var onThisMac: [String: Any] = [:]
        if let folder = dataFolder {
            for name in perAccountFiles {
                let url = folder.appendingPathComponent("\(name)\(scoped).json")
                if let data = try? Data(contentsOf: url), let json = try? JSONSerialization.jsonObject(with: data) {
                    onThisMac[name] = json
                }
            }
        }
        var settings: [String: Any] = [:]
        let iso = ISO8601DateFormatter()
        for key in perAccountDefaultsKeys {
            guard let value = UserDefaults.standard.object(forKey: key + scoped) else { continue }
            settings[key] = (value as? Date).map { iso.string(from: $0) } ?? value
        }
        onThisMac["settings"] = settings
        let export: [String: Any] = [
            "exportedAt": iso.string(from: Date()),
            "app": "Locken \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")",
            "account": ["id": userID, "email": email],
            "onLockenServers": server.map { rows -> [String: Any] in
                var copy = rows
                copy["note"] = "Your profile and any feedback you sent. Your password is stored only as a hash and is never exported. Locken also keeps a security record of account changes (which fields changed, never their contents) for 24 months; email daanu.focus@gmail.com for a copy. Locken's servers hold no focus data."
                return copy
            } ?? ["note": "Locken's servers couldn't be reached, so this copy has only what's on this Mac. Try again online, or email daanu.focus@gmail.com for your server data (profile, feedback and account-change record)."],
            "onThisMac": onThisMac,
            "notIncluded": "Sign-in session, Canvas token or feed link and AI key: secrets stay in this Mac's Keychain.",
        ]
        guard JSONSerialization.isValidJSONObject(export) else { return nil }
        return try? JSONSerialization.data(withJSONObject: export, options: [.prettyPrinted, .sortedKeys])
    }
}
