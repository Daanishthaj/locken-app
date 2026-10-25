import Foundation

/// Age screening. Sign-up asks for a birth month and year without hinting at any cutoff (COPPA's neutral age
/// screen): under-13s can't create an account, and this Mac remembers that so the form can't simply be retried.
/// AI features need 18+, because Claude's and Gemini's terms require it. The answer is kept per account on this Mac
/// and on the account itself (`profiles.birth_month`, `birth_year`, `terms_agreed_at`), so every Mac uses the same
/// one: the account's answer wins, and a Mac that already has an answer uploads it. The server keeps the first
/// answer only and refuses under-13 ages.
@MainActor
final class AgeGate: ObservableObject {
    static let shared = AgeGate()

    static let minimumAge = 13
    static let aiMinimumAge = 18
    /// Under 18 (or the age of majority), a parent or guardian must agree to the Terms too.
    static let adultAge = 18

    struct Birth: Equatable {
        let month: Int
        let year: Int

        var age: Int { AgeGate.age(birthMonth: month, birthYear: year) }
    }

    /// The signed-in account's answer; nil until it has given one on this Mac.
    @Published private(set) var birth: Birth?

    /// An answer from sign-up, kept until the new account is signed in on this Mac.
    private var pending: Birth?
    /// When the signed-in account agreed to the Terms and Privacy Policy on this Mac; nil if it hasn't yet.
    @Published private(set) var agreedAt: Date?
    /// The sign-up form's agreement, kept until the new account is signed in.
    private var pendingAgreement = false
    static let agreedKey = "legal.agreedAt"

    /// Every account needs both before it can use Locken, however it signed in (including Google from Sign In).
    var hasCompletedConsent: Bool { birth != nil && agreedAt != nil }
    /// True while the account's answer is being fetched, so a new Mac doesn't ask before it knows.
    @Published private(set) var isSyncing = false

    private static let blockedKey = "signup.ageBlocked"
    static let monthKey = "age.birthMonth"
    static let yearKey = "age.birthYear"

    private init() {}

    /// Age in whole years. The day isn't asked, so in the birthday month itself the lower age is used.
    nonisolated static func age(birthMonth: Int, birthYear: Int, now: Date = Date(), calendar: Calendar = .current) -> Int {
        let today = calendar.dateComponents([.year, .month], from: now)
        let years = (today.year ?? 0) - birthYear
        return (today.month ?? 0) > birthMonth ? years : years - 1
    }

    // MARK: Sign-up

    static var isSignUpBlocked: Bool { UserDefaults.standard.bool(forKey: blockedKey) }

    static func blockSignUp() {
        UserDefaults.standard.set(true, forKey: blockedKey)
    }

    func rememberForNewAccount(month: Int, year: Int) {
        pending = Birth(month: month, year: year)
    }

    /// Called when someone signs in to an existing account instead, so a sign-up answer can't land on it.
    func clearPending() {
        pending = nil
        pendingAgreement = false
    }

    func rememberAgreementForNewAccount() {
        pendingAgreement = true
    }

    /// Records that the signed-in account agreed to the Terms and Privacy Policy, with the time.
    func recordAgreement() {
        guard AccountScope.userID != nil else { return }
        let now = Date()
        UserDefaults.standard.set(now, forKey: Self.agreedKey + AccountScope.suffix)
        agreedAt = now
    }

    // MARK: Per account

    /// Loads the signed-in account's answer, saving a pending one from sign-up first.
    func activateAccount() {
        if let pending {
            save(pending)
            self.pending = nil
        }
        if pendingAgreement {
            recordAgreement()
            pendingAgreement = false
        }
        agreedAt = UserDefaults.standard.object(forKey: Self.agreedKey + AccountScope.suffix) as? Date
        let defaults = UserDefaults.standard
        let month = defaults.integer(forKey: Self.monthKey + AccountScope.suffix)
        let year = defaults.integer(forKey: Self.yearKey + AccountScope.suffix)
        birth = (1...12).contains(month) && year > 1900 ? Birth(month: month, year: year) : nil
        isSyncing = !hasCompletedConsent // set now, so the consent screen doesn't flash before the check starts
        Task { await syncWithAccount() }
    }

    /// Makes this Mac and the account agree: the account's answer replaces this Mac's; if the account has none yet,
    /// this Mac's answer is uploaded. Offline, this Mac's answer stands until the next sign-in.
    func syncWithAccount() async {
        guard let userID = AccountScope.userID else { return }
        isSyncing = !hasCompletedConsent
        defer { isSyncing = false }
        guard let server = await AuthManager.shared.fetchAccountConsent(), AccountScope.userID == userID else { return }
        if let month = server.month, let year = server.year {
            save(Birth(month: month, year: year))
        }
        if let agreed = server.agreedAt {
            UserDefaults.standard.set(agreed, forKey: Self.agreedKey + AccountScope.suffix)
            agreedAt = agreed
        }
        let uploadBirth = server.month == nil ? birth : nil
        let uploadAgreement = server.agreedAt == nil && agreedAt != nil
        if uploadBirth != nil || uploadAgreement {
            _ = await AuthManager.shared.saveAccountConsent(month: uploadBirth?.month, year: uploadBirth?.year,
                                                            agreed: uploadAgreement)
        }
    }

    /// Records the answer for the signed-in account. It can't be changed afterwards in the app.
    func save(month: Int, year: Int) {
        save(Birth(month: month, year: year))
    }

    private func save(_ answer: Birth) {
        guard AccountScope.userID != nil else { return }
        UserDefaults.standard.set(answer.month, forKey: Self.monthKey + AccountScope.suffix)
        UserDefaults.standard.set(answer.year, forKey: Self.yearKey + AccountScope.suffix)
        birth = answer
    }

    /// nil when the account hasn't given its birth month and year on this Mac yet.
    var meetsAIMinimum: Bool? { birth.map { $0.age >= Self.aiMinimumAge } }
}
