import AppKit
import AuthenticationServices
import CryptoKit
import Foundation
import UserNotifications

/// Email + password sign-in through Supabase Auth (GoTrue REST), required before the app opens.
///
/// Security rules this follows:
/// 1. Only the project's public anon key ships in the app; no service-role key exists anywhere in the client.
/// 2. The user's identity comes from the verified session (`GET /auth/v1/user` with the access token),
///    never from anything the app itself claims.
/// 3. Data access relies on Row Level Security on every table (policies scoped to `auth.uid()`).
/// 4. Sign-out revokes the session on the server (`POST /auth/v1/logout`) before local tokens are deleted.
/// 5. A wrong email and a wrong password get the same message, and sign-up never reveals whether an
///    email is already registered.
///
/// Also: sign-up passwords must pass `PasswordPolicy` (and not be in a known breach); accounts with an
/// authenticator app (TOTP, e.g. Google Authenticator) must enter its 6-digit code after the password;
/// "Continue with Google" uses Supabase's Google provider with PKCE.
@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    struct User: Equatable {
        let id: String
        let email: String
        /// The name from the sign-in provider (Google's full name), when it gave one.
        var name: String? = nil
    }

    enum Phase: Equatable {
        case restoring
        case signedOut
        /// Password accepted, but the account has an authenticator app: its 6-digit code is still needed.
        case needsMFA(factorID: String)
        /// First step passed; the 6-digit code emailed to `email` must be entered before this Mac is trusted.
        case needsEmailCode(email: String, isNewAccount: Bool)
        /// Forgot password: a 6-digit code was emailed (if the account exists); it must be entered next.
        case resetCode(email: String)
        /// Forgot password, account with an authenticator app: its code is needed before the password can change.
        case resetMFA(email: String, factorID: String)
        /// Forgot password: identity proven; choose the new password.
        case resetNewPassword(email: String)
        case signedIn(User)
    }

    /// The account's verified authenticator-app factor, if any (for Settings).
    @Published private(set) var totpFactorID: String?

    @Published private(set) var phase: Phase = .restoring {
        didSet {
            guard phase == .signedOut else { return }
            justSignedIn = false
            // Back on the sign-in screen: a waiting update installs now, without asking.
            AppUpdater.shared.installIfOnSignInScreen()
        }
    }
    /// True right after someone signs in or creates an account on this Mac (email code, Google, authenticator
    /// code), until the welcome receipt has played. Never true for a session restored when Locken opens.
    @Published private(set) var justSignedIn = false
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    @Published var noticeMessage: String?

    var user: User? {
        if case .signedIn(let user) = phase { return user }
        return nil
    }

    /// The project shared with the retired main app.
    private let projectURL = URL(string: "https://isohdbjcvluvaflmrfeg.supabase.co")!
    /// Supabase's publishable key (`sb_publishable_…`): public by design, safe in an app; RLS protects data. Unlike the
    /// legacy anon JWT it can be revoked and rotated on its own. It goes on the `apikey` header only, never as a bearer.
    private let publishableKey = "sb_publishable__dafcMM6U-IfaRH_t1JtPg_3oafX8zK"

    /// Renamed from "…auth" in 2.0.3. Items under the old name were saved by builds with a different signature,
    /// so macOS asked for the Mac password every time Locken read them; they're left alone and never read.
    private static let keychainService = "com.locken.LockenTestApp.session"
    private static let invalidCredentials = "Email or password is incorrect."

    /// The session in memory is the source of truth while the app runs; the Keychain only keeps it for next launch.
    /// So a Keychain write that fails (an item an older build saved) can never bring back an old, expired token.
    private var tokenCache: [String: String?] = [:]
    private var accessToken: String? {
        get { cachedToken("accessToken") }
        set { tokenCache["accessToken"] = .some(newValue); store(newValue, account: "accessToken") }
    }
    private var refreshToken: String? {
        get { cachedToken("refreshToken") }
        set { tokenCache["refreshToken"] = .some(newValue); store(newValue, account: "refreshToken") }
    }

    private func cachedToken(_ account: String) -> String? {
        if let cached = tokenCache[account] { return cached }
        let stored = KeychainStore.get(service: Self.keychainService, account: account)
        tokenCache[account] = .some(stored)
        return stored
    }

    private init() {
        SecureNetwork.clearLegacyCache()
        // Open straight into the last verified account instead of waiting on a spinner. The server re-checks
        // the session right away and signs out only if it rejects it; data on the server needs a valid token
        // either way, so nothing is exposed by opening first.
        if accessToken != nil || refreshToken != nil, let cached = lastVerifiedUser {
            applyCachedPhase(cached)
        }
        Task { await restoreSession() }
    }

    /// The phase for the last verified account: signed in, or waiting for its authenticator code.
    private func applyCachedPhase(_ cached: (user: User, factorID: String?)) {
        totpFactorID = cached.factorID
        if let factorID = cached.factorID, Self.assuranceLevel(of: accessToken) != "aal2" {
            phase = .needsMFA(factorID: factorID)
        } else {
            phase = .signedIn(cached.user)
        }
    }

    // MARK: Public actions

    func signIn(email: String, password: String) async {
        guard Self.isValidEmail(email) else {
            errorMessage = "Enter a valid email address."
            return
        }
        await run(throttled: true) {
            let body = ["email": email.trimmingCharacters(in: .whitespaces).lowercased(), "password": password]
            let (json, status) = try await self.request("/auth/v1/token?grant_type=password", body: body)
            // 400 covers both unknown email and wrong password; say the same thing for either.
            guard status == 200 else {
                throw AuthError.message(status == 429 ? "Too many attempts. Wait a minute and try again." : Self.invalidCredentials)
            }
            try await self.requireEmailCode(provingSession: json, email: body["email"]!, isNewAccount: false)
        }
    }

    func signUp(email: String, password: String) async {
        guard Self.isValidEmail(email) else {
            errorMessage = "Enter a valid email address."
            return
        }
        // A mistyped domain ("gmail.comew") would bounce the confirmation code, so catch it before sign-up.
        if let suggestion = Self.emailTypoSuggestion(email) {
            errorMessage = "Did you mean \(suggestion)? Check the email and try again."
            return
        }
        let assessment = PasswordPolicy.assess(password, email: email)
        guard assessment.isAcceptable else {
            errorMessage = assessment.problems.first ?? "Choose a stronger password."
            return
        }
        await run(throttled: true) {
            if await PasswordPolicy.isBreached(password) == true {
                throw AuthError.message("This password has appeared in a data breach. Choose a different one.")
            }
            let body = ["email": email.trimmingCharacters(in: .whitespaces).lowercased(), "password": password]
            let (json, status) = try await self.request("/auth/v1/signup", body: body)
            if status == 200, json["access_token"] != nil {
                // Email confirmation is off in the project: still require a code before trusting this Mac.
                try await self.requireEmailCode(provingSession: json, email: body["email"]!, isNewAccount: false)
            } else if status == 200 || status == 422 || status == 400 {
                // Supabase emailed a confirmation code. Same screen whether or not the email already has an account.
                self.phase = .needsEmailCode(email: body["email"]!, isNewAccount: true)
            } else if status == 429 {
                throw AuthError.message("Too many attempts. Wait a minute and try again.")
            } else {
                throw AuthError.message("Couldn't create the account right now. Try again.")
            }
        }
    }

    /// Revokes the session on the server first, then clears the local tokens. `scope` "global" signs the
    /// account out on every Mac, revoking all of its refresh tokens.
    func signOut(scope: String = "local") async {
        isWorking = true
        defer { isWorking = false }
        if let token = accessToken {
            let status = (try? await request("/auth/v1/logout?scope=\(scope)", body: [:], bearer: token))?.1
            // An expired access token can't log out; refresh once so the session is really revoked on the server.
            if status == 401 || status == 403, let refresh = refreshToken,
               let (json, refreshStatus) = try? await request("/auth/v1/token?grant_type=refresh_token", body: ["refresh_token": refresh]),
               refreshStatus == 200, let fresh = json["access_token"] as? String {
                _ = try? await request("/auth/v1/logout?scope=\(scope)", body: [:], bearer: fresh)
            }
        }
        reverifyTask?.cancel()
        accessToken = nil
        refreshToken = nil
        store(nil, account: "lastUser")
        phase = .signedOut
    }

    /// Signs this account out on every Mac (for a lost or shared Mac).
    func signOutEverywhere() async {
        await signOut(scope: "global")
    }

    // MARK: Password change

    /// Step 1: Supabase emails a 6-digit code, so a password change needs the email inbox as well as this Mac.
    func sendPasswordChangeCode() async -> Bool {
        var sent = false
        await run(throttled: true) {
            let (_, status) = try await self.authorizedRequest("/auth/v1/reauthenticate", body: nil, method: "GET")
            switch status {
            case 200: sent = true
            case 429: throw AuthError.message("Too many attempts. Wait a minute and try again.")
            default: throw AuthError.message("Couldn't send a code right now. Try again.")
            }
        }
        if sent, let email = user?.email { noticeMessage = "We sent a 6-digit code to \(email)." }
        return sent
    }

    /// Step 2: the new password (same rules and breach check as sign-up) and the emailed code. Afterwards every
    /// other Mac signed in to this account is signed out.
    func changePassword(to newPassword: String, code: String) async -> Bool {
        guard let email = user?.email else { return false }
        let assessment = PasswordPolicy.assess(newPassword, email: email)
        guard assessment.isAcceptable else {
            errorMessage = assessment.problems.first ?? "Choose a stronger password."
            return false
        }
        var changed = false
        await run(throttled: true) {
            if await PasswordPolicy.isBreached(newPassword) == true {
                throw AuthError.message("This password has appeared in a data breach. Choose a different one.")
            }
            let (json, status) = try await self.authorizedRequest(
                "/auth/v1/user", body: ["password": newPassword, "nonce": code], method: "PUT"
            )
            let errorCode = json["error_code"] as? String
            switch (status, errorCode) {
            case (200, _):
                changed = true
                _ = try? await self.authorizedRequest("/auth/v1/logout?scope=others", body: [:])
            case (_, "same_password"):
                throw AuthError.message("Choose a password that's different from your current one.")
            case (_, "weak_password"):
                throw AuthError.message("Choose a stronger password.")
            case (429, _):
                throw AuthError.message("Too many attempts. Wait a minute and try again.")
            case (400, _), (401, _), (403, _), (422, _):
                throw AuthError.message("That code didn't match or has expired. Send a new one.")
            default:
                throw AuthError.message("Couldn't change your password right now. Try again.")
            }
        }
        if changed { noticeMessage = "Password changed. Your other Macs were signed out." }
        return changed
    }

    /// A request as the signed-in user, refreshing the access token once if it has expired.
    // MARK: Feedback and the owner's admin view

    /// Saves feedback for the signed-in account. The server sets the account from the token; the user can't read it back.
    /// Your own rows on Locken's servers (profile and any feedback you sent), for Download My Data.
    /// Row Level Security returns only the signed-in account's rows. Nil if the server can't be reached.
    func serverDataForExport() async -> [String: Any]? {
        _ = try? await authorizedRequest("/auth/v1/user", body: nil) // refreshes an expired access token first
        guard let token = accessToken else { return nil }
        var result: [String: Any] = [:]
        let tables = [
            ("profile", "/rest/v1/profiles?select=id,email,full_name,avatar_url,plan,created_at,birth_month,birth_year,terms_agreed_at"),
            ("feedback", "/rest/v1/feedback?select=rating,message,app_version,created_at&order=created_at.desc"),
        ]
        for (key, path) in tables {
            guard let (data, status) = try? await requestData(path, body: nil, bearer: token), status == 200,
                  let rows = try? JSONSerialization.jsonObject(with: data) else { return nil }
            result[key] = rows
        }
        return result
    }

    /// The account's birth month and year and when it agreed to the Terms, as stored on the server, so every Mac
    /// uses the same answer.
    struct AccountConsent {
        let month: Int?
        let year: Int?
        let agreedAt: Date?
    }

    /// Reads this account's consent from its own profile row (RLS limits it to the signed-in user). nil when the
    /// server can't be reached, so the caller keeps what this Mac has.
    func fetchAccountConsent() async -> AccountConsent? {
        guard let id = user?.id else { return nil }
        _ = try? await authorizedRequest("/auth/v1/user", body: nil) // refreshes an expired access token first
        guard let token = accessToken,
              let (data, status) = try? await requestData(
                "/rest/v1/profiles?select=birth_month,birth_year,terms_agreed_at&id=eq.\(id)", body: nil, bearer: token),
              status == 200,
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let row = rows.first else { return nil }
        let agreed = (row["terms_agreed_at"] as? String).flatMap { text -> Date? in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            return formatter.date(from: String(text.prefix(19)))
        }
        return AccountConsent(month: row["birth_month"] as? Int, year: row["birth_year"] as? Int, agreedAt: agreed)
    }

    /// Saves this Mac's answer to the account. The server keeps the first answer only (later changes are refused),
    /// refuses under-13 ages, and sets the agreement time itself. Returns whether it was stored.
    func saveAccountConsent(month: Int?, year: Int?, agreed: Bool) async -> Bool {
        guard let id = user?.id else { return false }
        var body: [String: Any] = [:]
        if let month, let year {
            body["birth_month"] = month
            body["birth_year"] = year
        }
        if agreed { body["terms_agreed_at"] = "now" }
        guard !body.isEmpty,
              let (_, status) = try? await authorizedRequest("/rest/v1/profiles?id=eq.\(id)", body: body, method: "PATCH")
        else { return false }
        return status == 200 || status == 204
    }

    func submitFeedback(rating: Int?, message: String) async -> Bool {
        var body: [String: Any] = ["message": String(message.prefix(2000))]
        if let rating { body["rating"] = min(max(rating, 1), 5) }
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            body["app_version"] = String(version.prefix(20))
        }
        guard let (_, status) = try? await authorizedRequest("/rest/v1/feedback", body: body) else { return false }
        return status == 201 || status == 204
    }

    /// The owner's overview from the admin-overview function. 403 for anyone not on the server's admin list.
    func adminOverview(checkOnly: Bool) async -> (status: Int, json: [String: Any]) {
        guard let (json, status) = try? await authorizedRequest("/functions/v1/admin-overview", body: ["check": checkOnly]) else {
            return (0, [:])
        }
        return (status, json)
    }

    /// Bans (refuses sign-in and ends every session) or unbans an account through admin-overview, which checks on the
    /// server that the caller is an admin and the target isn't. Returns nil on success, or a message to show.
    func adminSetBan(userID: String, banned: Bool) async -> String? {
        guard let (json, status) = try? await authorizedRequest(
            "/functions/v1/admin-overview", body: ["action": banned ? "ban" : "unban", "userId": userID]
        ) else { return "Couldn't reach the server. Try again." }
        if status == 200 { return nil }
        return status == 403 ? "This account isn't an admin." : (json["error"] as? String ?? "Couldn't change that account. Try again.")
    }

    private func authorizedRequest(_ path: String, body: [String: Any]?, method: String? = nil) async throws -> ([String: Any], Int) {
        guard let token = accessToken else { throw AuthError.message("Sign in again to continue.") }
        var result = try await request(path, body: body, bearer: token, method: method)
        if result.1 == 401, let refresh = refreshToken {
            let (json, status) = try await request("/auth/v1/token?grant_type=refresh_token", body: ["refresh_token": refresh])
            guard status == 200, let fresh = json["access_token"] as? String else {
                throw AuthError.message("Your session expired. Sign out and sign in again.")
            }
            accessToken = fresh
            refreshToken = json["refresh_token"] as? String
            result = try await request(path, body: body, bearer: fresh, method: method)
        }
        return result
    }

    /// Permanently deletes the signed-in account through the `delete-account` Edge Function (which takes the
    /// user from the verified token and holds the only service-role key), then this Mac's data for it.
    func deleteAccount() async -> Bool {
        guard let user, var token = accessToken else { return false }
        var deleted = false
        await run {
            var (_, status) = try await self.request("/functions/v1/delete-account", body: [:], bearer: token)
            // An expired access token: refresh once and try again.
            if status == 401, let refresh = self.refreshToken {
                let (json, refreshStatus) = try await self.request("/auth/v1/token?grant_type=refresh_token", body: ["refresh_token": refresh])
                guard refreshStatus == 200, let fresh = json["access_token"] as? String else { throw AuthError.rejected }
                self.accessToken = fresh
                self.refreshToken = json["refresh_token"] as? String
                token = fresh
                (_, status) = try await self.request("/functions/v1/delete-account", body: [:], bearer: token)
            }
            switch status {
            case 200: deleted = true
            case 403: throw AuthError.message("Enter your authenticator code first: sign out, sign back in, then delete the account.")
            default: throw AuthError.message("Couldn't delete your account right now. Try again.")
            }
        }
        guard deleted else { return false }

        // Stop everything that writes for this account, then remove what it left on this Mac.
        TestAppStateManager.shared.deactivateAccount()
        HabitStore.shared.deactivate()
        ScreenUsageTracker.shared.deactivateAccount()
        VoiceAssistant.shared.reset()
        VoiceAssistant.shared.stopHotkey()
        AssistantHistoryStore.shared.deactivate()
        CanvasAPIManager.shared.unlink()
        AITaskFormatter.shared.removeAPIKey()
        ElevenLabsVoice.shared.removeKey()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        AccountScope.eraseLocalData(for: user.id)

        reverifyTask?.cancel()
        accessToken = nil
        refreshToken = nil
        store(nil, account: "lastUser")
        totpFactorID = nil
        phase = .signedOut
        noticeMessage = "Your account was deleted."
        return true
    }

    // MARK: Session

    /// Re-checks a session that was opened offline, until the server confirms or rejects it.
    private var reverifyTask: Task<Void, Never>?

    /// What happened when the stored session was checked with the server.
    private enum RestoreOutcome { case verified, rejected, unreachable }

    /// On launch: verify the stored session with the server (refreshing it if it expired). Tokens are only
    /// cleared when the server rejects them; with no connection the app opens for the last verified account
    /// and keeps re-checking in the background.
    private func restoreSession() async {
        guard accessToken != nil || refreshToken != nil else {
            phase = .signedOut
            return
        }
        switch await checkStoredSession() {
        case .verified:
            return
        case .rejected:
            accessToken = nil
            refreshToken = nil
            store(nil, account: "lastUser")
            phase = .signedOut
        case .unreachable:
            if let cached = lastVerifiedUser {
                applyCachedPhase(cached)
            } else {
                phase = .signedOut
            }
            scheduleReverify()
        }
    }

    private func checkStoredSession() async -> RestoreOutcome {
        do {
            try await settlePhase()
            return .verified
        } catch AuthError.rejected {
            // Expired or revoked access token: fall through to the refresh token.
        } catch {
            return .unreachable
        }
        guard let refresh = refreshToken else { return .rejected }
        do {
            let (json, status) = try await request("/auth/v1/token?grant_type=refresh_token", body: ["refresh_token": refresh])
            if status == 400 || status == 401 || status == 403 { return .rejected }
            guard status == 200 else { return .unreachable }
            try await adoptTokens(json, freshSignIn: false)
            return .verified
        } catch AuthError.rejected {
            return .rejected
        } catch {
            return .unreachable
        }
    }

    private func scheduleReverify() {
        reverifyTask?.cancel()
        reverifyTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self, !Task.isCancelled else { return }
                switch await self.checkStoredSession() {
                case .verified:
                    return
                case .rejected:
                    self.accessToken = nil
                    self.refreshToken = nil
                    self.store(nil, account: "lastUser")
                    self.phase = .signedOut
                    return
                case .unreachable:
                    continue
                }
            }
        }
    }

    /// The account the stored session last proved to be, kept so the app can open offline.
    private var lastVerifiedUser: (user: User, factorID: String?)? {
        guard let raw = KeychainStore.get(service: Self.keychainService, account: "lastUser") else { return nil }
        let parts = raw.components(separatedBy: "\n")
        guard parts.count == 3, !parts[0].isEmpty else { return nil }
        return (User(id: parts[0], email: parts[1]), parts[2].isEmpty ? nil : parts[2])
    }

    /// Stores the new tokens, then asks the server who they belong to; identity comes only from there.
    private func adoptTokens(_ json: [String: Any], freshSignIn: Bool = true) async throws {
        guard let access = json["access_token"] as? String else { throw AuthError.message(Self.invalidCredentials) }
        accessToken = access
        refreshToken = json["refresh_token"] as? String
        try await settlePhase(freshSignIn: freshSignIn)
    }

    /// Signed in only once the session is verified and, if the account has an authenticator app, at AAL2.
    /// A fresh sign-in (not a restored session) shows the welcome receipt.
    private func settlePhase(freshSignIn: Bool = false) async throws {
        let (user, factorID) = try await verifiedUser()
        if freshSignIn { justSignedIn = true }
        totpFactorID = factorID
        store([user.id, user.email, factorID ?? ""].joined(separator: "\n"), account: "lastUser")
        if let factorID, Self.assuranceLevel(of: accessToken) != "aal2" {
            phase = .needsMFA(factorID: factorID)
        } else {
            phase = .signedIn(user)
        }
    }

    private func verifiedUser() async throws -> (User, String?) {
        guard let token = accessToken else { throw AuthError.message(Self.invalidCredentials) }
        let (json, status) = try await request("/auth/v1/user", body: nil, bearer: token)
        // 401/403: the token itself was refused. Anything else non-200 is the server, not the session.
        if status == 401 || status == 403 { throw AuthError.rejected }
        guard status == 200, let id = json["id"] as? String else { throw URLError(.badServerResponse) }
        let factors = json["factors"] as? [[String: Any]] ?? []
        let totp = factors.first { $0["factor_type"] as? String == "totp" && $0["status"] as? String == "verified" }
        let metadata = json["user_metadata"] as? [String: Any]
        let name = (metadata?["full_name"] as? String ?? metadata?["name"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (User(id: id, email: json["email"] as? String ?? "", name: name?.isEmpty == false ? name : nil), totp?["id"] as? String)
    }

    /// The welcome receipt has played.
    func finishSignInWelcome() {
        justSignedIn = false
    }

    /// The `aal` claim of the access token (read only to decide whether to ask for the code; the server enforces it).
    private static func assuranceLevel(of token: String?) -> String? {
        guard let payload = token?.split(separator: ".").dropFirst().first else { return nil }
        var base64 = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["aal"] as? String
    }

    // MARK: Emailed code (every sign-in on a new session)

    /// The first step (password or Google) proved who this is. Its session is revoked right away and never
    /// stored; a one-time code goes to the account's email, and only the session from that code is kept.
    /// After that, the stored session opens the app without a code until the user signs out.
    private func requireEmailCode(provingSession json: [String: Any], email: String, isNewAccount: Bool) async throws {
        if let token = json["access_token"] as? String {
            _ = try? await request("/auth/v1/logout?scope=local", body: [:], bearer: token)
        }
        try await sendEmailCode(to: email)
        phase = .needsEmailCode(email: email, isNewAccount: isNewAccount)
    }

    private func sendEmailCode(to email: String) async throws {
        let (_, status) = try await request("/auth/v1/otp", body: ["email": email, "create_user": false])
        if status == 429 { throw AuthError.message("A code was just sent. Wait a minute before asking for another.") }
        guard status == 200 else { throw AuthError.message("Couldn't send your code. Try again.") }
    }

    func resendEmailCode() async {
        guard case .needsEmailCode(let email, let isNewAccount) = phase else { return }
        await run(throttled: true) {
            if isNewAccount {
                let (_, status) = try await self.request("/auth/v1/resend", body: ["type": "signup", "email": email])
                guard status == 200 else { throw AuthError.message("Couldn't send your code. Try again.") }
            } else {
                try await self.sendEmailCode(to: email)
            }
            self.noticeMessage = "A new code is on its way."
        }
    }

    /// Checks the emailed code; on success this session is stored, so reopening the app won't ask again.
    func verifyEmailCode(_ code: String) async -> Bool {
        guard case .needsEmailCode(let email, let isNewAccount) = phase else { return false }
        var ok = false
        await run(throttled: true) {
            let (json, status) = try await self.request(
                "/auth/v1/verify",
                body: ["type": isNewAccount ? "signup" : "email", "email": email, "token": code]
            )
            guard status == 200, json["access_token"] != nil else {
                throw AuthError.message("That code didn't match or has expired. Check your email or send a new one.")
            }
            do {
                try await self.adoptTokens(json)
            } catch {
                // The code was right (and is now used up); it's finishing the sign-in that failed.
                throw AuthError.message("Your code worked, but Locken couldn't finish signing in. Send a new code and try once more.")
            }
            ok = true
        }
        return ok
    }

    // MARK: Forgot password

    /// The session from the reset code, kept only in memory until the new password is saved, so quitting halfway
    /// leaves nothing signed in on this Mac.
    private var recoveryAccessToken: String?
    private var recoveryRefreshToken: String?

    /// Step 1: emails a 6-digit code. The reply is the same whether or not the email has an account.
    func startPasswordReset(email rawEmail: String) async {
        let email = rawEmail.trimmingCharacters(in: .whitespaces).lowercased()
        guard Self.isValidEmail(email) else {
            errorMessage = "Enter your email above, then choose Forgot password."
            return
        }
        await run(throttled: true) {
            let (_, status) = try await self.request("/auth/v1/otp", body: ["email": email, "create_user": false])
            if status == 429 { throw AuthError.message("A code was just sent. Wait a minute before asking for another.") }
            // Any other answer, including "no such account", gets the same screen.
            self.phase = .resetCode(email: email)
        }
        if case .resetCode = phase {
            noticeMessage = "If there's a Locken account for \(email), we've emailed it a 6-digit code."
        }
    }

    /// Step 2: the emailed code. Accounts with an authenticator app also need that code next.
    func verifyResetCode(_ code: String) async -> Bool {
        guard case .resetCode(let email) = phase else { return false }
        var ok = false
        await run(throttled: true) {
            let (json, status) = try await self.request("/auth/v1/verify", body: ["type": "email", "email": email, "token": code])
            guard status == 200, let access = json["access_token"] as? String else {
                throw AuthError.message("That code didn't match or has expired. Check your email or send a new one.")
            }
            self.recoveryAccessToken = access
            self.recoveryRefreshToken = json["refresh_token"] as? String
            let (user, userStatus) = try await self.request("/auth/v1/user", body: nil, bearer: access)
            guard userStatus == 200 else { throw AuthError.message("Couldn't check your account. Try again.") }
            let factors = user["factors"] as? [[String: Any]] ?? []
            let totp = factors.first { $0["factor_type"] as? String == "totp" && $0["status"] as? String == "verified" }
            if let factorID = totp?["id"] as? String {
                self.phase = .resetMFA(email: email, factorID: factorID)
            } else {
                self.phase = .resetNewPassword(email: email)
            }
            ok = true
        }
        return ok
    }

    /// Step 2b: the authenticator code, so an emailed code alone can't take over a protected account.
    func verifyResetMFA(code: String) async -> Bool {
        guard case .resetMFA(let email, let factorID) = phase, let token = recoveryAccessToken else { return false }
        var ok = false
        await run(throttled: true) {
            let (challenge, status) = try await self.request("/auth/v1/factors/\(factorID)/challenge", body: [:], bearer: token)
            guard status == 200, let challengeID = challenge["id"] as? String else {
                throw AuthError.message("Couldn't check your authenticator code. Try again.")
            }
            let (json, verifyStatus) = try await self.request(
                "/auth/v1/factors/\(factorID)/verify", body: ["challenge_id": challengeID, "code": code], bearer: token
            )
            guard verifyStatus == 200, let access = json["access_token"] as? String else {
                throw AuthError.message("That code didn't match. Check your authenticator app and try again.")
            }
            self.recoveryAccessToken = access
            self.recoveryRefreshToken = json["refresh_token"] as? String ?? self.recoveryRefreshToken
            self.phase = .resetNewPassword(email: email)
            ok = true
        }
        return ok
    }

    /// Step 3: the new password (same rules and breach check as sign-up). Other Macs are signed out, then this
    /// Mac is signed in with the reset session.
    func finishPasswordReset(newPassword: String) async {
        guard case .resetNewPassword(let email) = phase, let token = recoveryAccessToken else { return }
        let assessment = PasswordPolicy.assess(newPassword, email: email)
        guard assessment.isAcceptable else {
            errorMessage = assessment.problems.first ?? "Choose a stronger password."
            return
        }
        var changed = false
        await run(throttled: true) {
            if await PasswordPolicy.isBreached(newPassword) == true {
                throw AuthError.message("This password has appeared in a data breach. Choose a different one.")
            }
            let (json, status) = try await self.request("/auth/v1/user", body: ["password": newPassword], bearer: token, method: "PUT")
            switch (status, json["error_code"] as? String) {
            case (200, _):
                changed = true
            case (_, "same_password"):
                throw AuthError.message("Choose a password that's different from your old one.")
            case (_, "weak_password"):
                throw AuthError.message("Choose a stronger password.")
            case (429, _):
                throw AuthError.message("Too many attempts. Wait a minute and try again.")
            default:
                throw AuthError.message("Couldn't save your new password. Start again from Forgot password.")
            }
            // Anyone who was signed in with the old password, on any other Mac, is signed out.
            _ = try? await self.request("/auth/v1/logout?scope=others", body: [:], bearer: token)
            self.accessToken = token
            self.refreshToken = self.recoveryRefreshToken
            self.recoveryAccessToken = nil
            self.recoveryRefreshToken = nil
            try await self.settlePhase()
        }
        if changed { noticeMessage = "Password changed. Your other Macs were signed out." }
    }

    /// Leaves the reset flow; a half-finished reset session is revoked, not kept.
    func cancelPasswordReset() {
        if let token = recoveryAccessToken {
            Task { _ = try? await request("/auth/v1/logout?scope=local", body: [:], bearer: token) }
        }
        recoveryAccessToken = nil
        recoveryRefreshToken = nil
        errorMessage = nil
        noticeMessage = nil
        phase = .signedOut
    }

    func cancelEmailCode() {
        errorMessage = nil
        noticeMessage = nil
        phase = .signedOut
    }

    // MARK: Authenticator app (TOTP)

    /// Checks the 6-digit code for the pending sign-in. Returns true when it's accepted.
    func verifyMFA(code: String) async -> Bool {
        guard case .needsMFA(let factorID) = phase else { return false }
        var ok = false
        await run(throttled: true) {
            ok = try await self.challengeAndVerify(factorID: factorID, code: code)
            if !ok { throw AuthError.message("That code didn't match. Check your authenticator app and try again.") }
        }
        return ok
    }

    struct Enrollment: Equatable {
        let factorID: String
        let qrCodeSVG: String
        let secret: String
    }

    /// Starts adding an authenticator app: returns the QR code and secret to scan.
    func beginTOTPEnrollment() async -> Enrollment? {
        guard let token = accessToken else { return nil }
        var enrollment: Enrollment?
        await run {
            let body: [String: String] = ["factor_type": "totp", "friendly_name": "Locken \(Int(Date().timeIntervalSince1970))"]
            let (json, status) = try await self.request("/auth/v1/factors", body: body, bearer: token)
            guard status == 200, let id = json["id"] as? String, let totp = json["totp"] as? [String: Any],
                  let qr = totp["qr_code"] as? String, let secret = totp["secret"] as? String else {
                throw AuthError.message("Couldn't start authenticator setup. Try again.")
            }
            enrollment = Enrollment(factorID: id, qrCodeSVG: qr, secret: secret)
        }
        return enrollment
    }

    /// Finishes adding the authenticator app once its first code checks out.
    func confirmTOTPEnrollment(_ enrollment: Enrollment, code: String) async -> Bool {
        var ok = false
        await run(throttled: true) {
            ok = try await self.challengeAndVerify(factorID: enrollment.factorID, code: code)
            if !ok { throw AuthError.message("That code didn't match. Check your authenticator app and try again.") }
        }
        return ok
    }

    func removeTOTP() async {
        guard let factorID = totpFactorID, let token = accessToken else { return }
        await run {
            let (_, status) = try await self.request("/auth/v1/factors/\(factorID)", body: nil, bearer: token, method: "DELETE")
            guard status == 200 else { throw AuthError.message("Couldn't remove the authenticator app. Try again.") }
            self.totpFactorID = nil
        }
    }

    /// Challenge + verify; on success the server returns an AAL2 session, which replaces the current one.
    private func challengeAndVerify(factorID: String, code: String) async throws -> Bool {
        guard let token = accessToken else { return false }
        let (challenge, status) = try await request("/auth/v1/factors/\(factorID)/challenge", body: [:], bearer: token)
        guard status == 200, let challengeID = challenge["id"] as? String else { return false }
        let (json, verifyStatus) = try await request(
            "/auth/v1/factors/\(factorID)/verify",
            body: ["challenge_id": challengeID, "code": code],
            bearer: token
        )
        guard verifyStatus == 200, json["access_token"] != nil else { return false }
        try await adoptTokens(json)
        return true
    }

    // MARK: Google

    private var webAuthSession: ASWebAuthenticationSession?
    private let presentationAnchor = WebAuthAnchor()

    /// "Continue with Google": Supabase's Google provider in a system sign-in sheet, using PKCE so the
    /// returned code is useless to anyone without this app's one-time verifier.
    func signInWithGoogle() {
        let verifier = Self.randomURLSafe(bytes: 32)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        var components = URLComponents(url: projectURL.appendingPathComponent("auth/v1/authorize"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: Self.oauthRedirect),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "s256"),
        ]
        errorMessage = nil
        let session = ASWebAuthenticationSession(url: components.url!, callbackURLScheme: "locken") { [weak self] url, error in
            let code = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "code" }?.value }
            Task { @MainActor in
                guard let self else { return }
                guard let code else {
                    if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                        self.errorMessage = "Google sign-in didn't finish. Try again."
                    }
                    return
                }
                await self.run(throttled: true) {
                    let (json, status) = try await self.request(
                        "/auth/v1/token?grant_type=pkce",
                        body: ["auth_code": code, "code_verifier": verifier]
                    )
                    guard status == 200 else { throw AuthError.message("Google sign-in didn't finish. Try again.") }
                    let email = (json["user"] as? [String: Any])?["email"] as? String ?? ""
                    try await self.requireEmailCode(provingSession: json, email: email, isNewAccount: false)
                }
            }
        }
        session.presentationContextProvider = presentationAnchor
        session.prefersEphemeralWebBrowserSession = false
        webAuthSession = session
        session.start()
    }

    /// Add this exact URL in Supabase → Authentication → URL Configuration → Redirect URLs.
    static let oauthRedirect = "locken://auth-callback"

    private static func randomURLSafe(bytes: Int) -> String {
        var data = Data(count: bytes)
        _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    // MARK: Transport

    private enum AuthError: Error {
        case message(String)
        /// The server refused the session's token.
        case rejected
    }

    /// Format and length only (RFC 5321 caps an address at 254 characters); Supabase validates it again.
    static func isValidEmail(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard trimmed.count <= 254 else { return false }
        return trimmed.range(of: #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static let commonEmailDomains = [
        "gmail.com", "googlemail.com", "yahoo.com", "outlook.com", "hotmail.com", "live.com", "msn.com",
        "icloud.com", "me.com", "mac.com", "aol.com", "proton.me", "protonmail.com",
    ]

    /// Real providers that are only a letter or two from a common one, so they're never "corrected".
    private static let realLookalikeDomains = ["mail.com", "ymail.com", "gmx.com", "aim.com", "email.com", "live.ca", "yahoo.ca"]

    /// The corrected address when the domain looks like a mistyped common one (gmail.comew, gmial.com, gmail.co);
    /// nil when it looks fine. Format only, so it says nothing about whether an account exists.
    static func emailTypoSuggestion(_ email: String) -> String? {
        let trimmed = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard let at = trimmed.lastIndex(of: "@") else { return nil }
        let local = trimmed[..<at]
        let domain = String(trimmed[trimmed.index(after: at)...])
        guard !commonEmailDomains.contains(domain), !realLookalikeDomains.contains(domain) else { return nil }
        let label = domain.split(separator: ".").first.map(String.init) ?? ""
        // Same provider name, wrong ending: gmail.comew, gmail.co, yahoo.cm.
        if let match = commonEmailDomains.first(where: { $0.split(separator: ".").first.map(String.init) == label }) {
            return "\(local)@\(match)"
        }
        // A letter or two off: gmial.com, outlok.com.
        if domain.count >= 8, let match = commonEmailDomains.first(where: { editDistance($0, domain) <= 2 }) {
            return "\(local)@\(match)"
        }
        return nil
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var row = Array(0...b.count)
        for i in 1...a.count {
            var previous = row[0]
            row[0] = i
            for j in 1...b.count {
                let saved = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, previous + (a[i - 1] == b[j - 1] ? 0 : 1))
                previous = saved
            }
        }
        return row[b.count]
    }

    // Client-side backoff on top of Supabase's own per-IP rate limits: after 5 failed sign-ins, sign-ups or
    // code checks in a row, these pause for 30 seconds, doubling with each further failure up to 5 minutes.
    // Saved in UserDefaults so quitting and reopening Locken doesn't reset the pause.
    private var failedAttempts: Int {
        get { UserDefaults.standard.integer(forKey: "auth.throttle.failures") }
        set { UserDefaults.standard.set(newValue, forKey: "auth.throttle.failures") }
    }
    private var lockedUntil: Date? {
        get { UserDefaults.standard.object(forKey: "auth.throttle.lockedUntil") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "auth.throttle.lockedUntil") }
    }

    private func registerFailure() {
        failedAttempts += 1
        guard failedAttempts >= 5 else { return }
        let pause = min(30 * pow(2, Double(failedAttempts - 5)), 300)
        lockedUntil = Date().addingTimeInterval(pause)
    }

    /// `throttled` runs count toward the backoff: a rejected attempt is a failure, anything else resets it.
    private func run(throttled: Bool = false, _ work: @escaping () async throws -> Void) async {
        if throttled, let until = lockedUntil, until > Date() {
            let seconds = Int(until.timeIntervalSinceNow.rounded(.up))
            errorMessage = "Too many attempts. Try again in \(seconds) seconds."
            return
        }
        isWorking = true
        errorMessage = nil
        noticeMessage = nil
        defer { isWorking = false }
        do {
            try await work()
            if throttled {
                failedAttempts = 0
                lockedUntil = nil
            }
        } catch AuthError.message(let text) {
            errorMessage = text
            if throttled { registerFailure() }
        } catch AuthError.rejected {
            errorMessage = Self.invalidCredentials
            if throttled { registerFailure() }
        } catch {
            errorMessage = "Couldn't reach the server. Check your connection."
        }
    }

    private func request(_ path: String, body: [String: Any]?, bearer: String? = nil, method: String? = nil) async throws -> ([String: Any], Int) {
        let (data, status) = try await requestData(path, body: body, bearer: bearer, method: method)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return (json, status)
    }

    /// Auth endpoints Supabase guards with the bot check once CAPTCHA protection is on (not token refresh, the
    /// Google code exchange or code verification).
    private static let captchaPaths = ["/auth/v1/signup", "/auth/v1/token?grant_type=password", "/auth/v1/otp",
                                       "/auth/v1/resend", "/auth/v1/recover"]

    private func requestData(_ path: String, body: [String: Any]?, bearer: String? = nil, method: String? = nil) async throws -> (Data, Int) {
        var body = body
        if body != nil, Self.captchaPaths.contains(where: { path.hasPrefix($0) }) {
            do {
                if let token = try await TurnstileGate.shared.token() {
                    body?["gotrue_meta_security"] = ["captcha_token": token]
                }
            } catch {
                throw AuthError.message(error.localizedDescription)
            }
        }
        var request = URLRequest(url: URL(string: projectURL.absoluteString + path)!)
        request.httpMethod = method ?? (body == nil ? "GET" : "POST")
        request.timeoutInterval = 20
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        // A signed-in user's own token; requests made before sign-in carry only the publishable key.
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await SecureNetwork.session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private func store(_ value: String?, account: String) {
        if let value {
            KeychainStore.set(value, service: Self.keychainService, account: account)
        } else {
            KeychainStore.delete(service: Self.keychainService, account: account)
        }
    }
}


/// Presents the Google sign-in sheet over the app's window.
private final class WebAuthAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}
