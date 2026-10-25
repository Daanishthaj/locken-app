import Charts
import SwiftUI

// MARK: - Feedback after a week

/// Asks for feedback once an account has used Locken on this Mac for a week. "Not now" asks again in 3 days;
/// "Don't ask again" and sending both stop it. Anyone can also send feedback any time from Settings.
/// Everything here is per account (`feedback.*` keys suffixed with the account ID).
@MainActor
final class FeedbackManager: ObservableObject {
    static let shared = FeedbackManager()

    @Published var isPresented = false

    @MainActor private enum Key {
        static var firstSeen: String { "feedback.firstSeen" + AccountScope.suffix }
        static var nextAsk: String { "feedback.nextAsk" + AccountScope.suffix }
        static var done: String { "feedback.done" + AccountScope.suffix }
    }

    private init() {}

    /// Called when an account signs in on this Mac: starts its one-week clock, then asks if it's due.
    func activateAccount() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Key.firstSeen) == nil { defaults.set(Date(), forKey: Key.firstSeen) }
        checkIfDue()
    }

    func checkIfDue(now: Date = Date()) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Key.done),
              let firstSeen = defaults.object(forKey: Key.firstSeen) as? Date,
              now.timeIntervalSince(firstSeen) >= 7 * 24 * 60 * 60 else { return }
        if let next = defaults.object(forKey: Key.nextAsk) as? Date, next > now { return }
        // Not in the middle of a session: wait for a calmer moment.
        guard !TestAppStateManager.shared.isTimerActive else { return }
        isPresented = true
    }

    func later() {
        UserDefaults.standard.set(Date().addingTimeInterval(3 * 24 * 60 * 60), forKey: Key.nextAsk)
        isPresented = false
    }

    func stopAsking() {
        UserDefaults.standard.set(true, forKey: Key.done)
        isPresented = false
    }

    func sent() {
        UserDefaults.standard.set(true, forKey: Key.done)
    }
}

struct FeedbackSheet: View {
    @ObservedObject private var manager = FeedbackManager.shared
    @ObservedObject private var auth = AuthManager.shared
    /// True when opened from Settings rather than by the one-week prompt.
    var fromSettings = false
    var onClose: () -> Void = {}

    @State private var rating: Int?
    @State private var message = ""
    @State private var sending = false
    @State private var result: String?
    @State private var sentOK = false

    private let accent = SquircleTokens.accentColor(for: "focus")
    private var trimmed: String { message.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func close() {
        if !fromSettings && !sentOK { manager.later() } else { manager.isPresented = false }
        onClose()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(fromSettings ? "Feedback" : "A week with Locken")
                .font(.appFont(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.55))
            Text("How's it going?")
                .font(.appFont(size: 22, weight: .bold))
                .foregroundColor(.white)
                .padding(.top, 4)
            Text("What helps, what's annoying, what's missing. It goes straight to the person who makes Locken.")
                .font(.appFont(size: 12))
                .foregroundColor(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            if sentOK {
                Label("Thanks, that's sent.", systemImage: "checkmark.circle.fill")
                    .font(.appFont(size: 14, weight: .semibold))
                    .foregroundColor(SquircleTokens.mintAccent)
                    .padding(.top, 22)
                HStack {
                    Spacer()
                    Button("Done") { manager.isPresented = false; onClose() }
                        .buttonStyle(.plain)
                        .quietAction()
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 18)
            } else {
                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { value in
                        Button { rating = value } label: {
                            Image(systemName: (rating ?? 0) >= value ? "star.fill" : "star")
                                .font(.system(size: 20))
                                .foregroundColor((rating ?? 0) >= value ? Color(red: 0.98, green: 0.78, blue: 0.3) : .white.opacity(0.35))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(value) star\(value == 1 ? "" : "s")")
                        .accessibilityAddTraits(rating == value ? .isSelected : [])
                    }
                }
                .padding(.top, 18)

                TextEditor(text: $message)
                    .font(.appFont(size: 13))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(height: 120)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
                    )
                    .overlay(alignment: .topLeading) {
                        if message.isEmpty {
                            Text("Type your feedback…")
                                .font(.appFont(size: 13))
                                .foregroundColor(.white.opacity(0.35))
                                .padding(.horizontal, 15)
                                .padding(.vertical, 10)
                                .allowsHitTesting(false)
                        }
                    }
                    .onChange(of: message) { _, value in if value.count > 2000 { message = String(value.prefix(2000)) } }
                    .padding(.top, 14)
                    .accessibilityLabel("Your feedback")

                if let result {
                    Text(result)
                        .font(.appFont(size: 11))
                        .foregroundColor(SquircleTokens.textGold)
                        .padding(.top, 8)
                }

                HStack(spacing: 16) {
                    Button(fromSettings ? "Cancel" : "Not now", action: close)
                        .buttonStyle(.plain)
                        .quietAction()
                        .keyboardShortcut(.cancelAction)
                    if !fromSettings {
                        Button("Don't ask again") { manager.stopAsking(); onClose() }
                            .buttonStyle(.plain)
                            .quietAction()
                    }
                    Spacer()
                    Button {
                        sending = true
                        result = nil
                        Task {
                            let ok = await auth.submitFeedback(rating: rating, message: trimmed)
                            sending = false
                            if ok {
                                sentOK = true
                                manager.sent()
                            } else {
                                result = "Couldn't send it. Check your connection and try again."
                            }
                        }
                    } label: {
                        Text(sending ? "Sending…" : "Send")
                            .font(.appFont(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 8)
                            .borderGlowButton(accent: accent, isProminent: true)
                    }
                    .buttonStyle(.plain)
                    .disabled(sending || (trimmed.isEmpty && rating == nil))
                    .opacity(sending || (trimmed.isEmpty && rating == nil) ? 0.5 : 1)
                }
                .padding(.top, 20)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(28)
        .frame(width: 460)
        .background(Color(red: 0.09, green: 0.09, blue: 0.11))
    }
}

/// Settings row: send feedback any time.
struct FeedbackCard: View {
    @State private var showing = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Feedback")
                    .font(.appFont(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text("Tell the person who makes Locken what works and what doesn't.")
                    .font(.appFont(size: 11))
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer()
            Button { showing = true } label: { Text("Send Feedback…").quietAction() }
                .buttonStyle(.plain)
        }
        .padding(Spacing.l)
        .innerObsidianCard(cornerRadius: 16)
        .sheet(isPresented: $showing) { FeedbackSheet(fromSettings: true) { showing = false } }
    }
}

// MARK: - The owner's admin view

/// Shows the Admin tab only to accounts the server lists as admins. The server checks on every request, so the
/// tab appearing (or someone forcing it) gives nobody data: the admin-overview function answers 403 to everyone else.
@MainActor
final class AdminManager: ObservableObject {
    static let shared = AdminManager()

    @Published private(set) var isAdmin = false
    @Published private(set) var overview: [String: Any] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    private init() {}

    func activateAccount() {
        isAdmin = false
        overview = [:]
        Task {
            let (status, _) = await AuthManager.shared.adminOverview(checkOnly: true)
            isAdmin = status == 200
        }
    }

    private var isFetching = false

    /// `silent` is the live refresh: no "Loading…" state, and a failed poll keeps the last numbers on screen.
    func refresh(silent: Bool = false) async {
        guard !isFetching else { return } // never stack requests when one is slow
        isFetching = true
        defer { isFetching = false }
        if !silent {
            isLoading = true
            error = nil
        }
        let (status, json) = await AuthManager.shared.adminOverview(checkOnly: false)
        isLoading = false
        if status == 200 {
            overview = json
            error = nil
        } else if status == 403 {
            error = "This account isn't an admin."
            isAdmin = false
        } else if !silent {
            error = "Couldn't load the overview. Try again."
        }
    }
}
