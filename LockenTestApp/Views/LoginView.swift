import SwiftUI

// MARK: - Sign In (shown before anything else in the app)

struct LoginView: View {
    @ObservedObject private var auth = AuthManager.shared

    private enum Mode: String, CaseIterable {
        case signIn = "Sign In"
        case signUp = "Create Account"
    }

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    /// Neutral age screen (COPPA): birth month and year, with no hint of the cutoff.
    @State private var birthMonth: Int?
    @State private var birthYear: Int?
    /// Clickwrap: an unchecked box next to the button, with links to the documents (Berman v. Freedom Financial).
    @State private var agreesToTerms = false
    /// Under 18, a parent or guardian agrees to the Terms too (Terms §2.2).
    @State private var guardianAgrees = false
    /// Once someone under 13 tries to sign up, this Mac stops offering sign-up.
    @State private var isSignUpBlocked = AgeGate.isSignUpBlocked
    @State private var openDocument: LegalDocument?
    /// Shown before Google's own screen: what Locken gets from Google and what it's used for.
    @State private var showingGoogleInfo = false
    @FocusState private var focusedField: Field?

    private enum Field { case email, password }

    // The sign-in screen keeps the violet brand palette (the Focus tab's since the Dashboard/Focus swap).
    private let accent = SquircleTokens.accentColor(for: "focus")



    @State private var codeStatus: CodeSlotsField.Status = .idle
    @State private var resetCodeStatus: CodeSlotsField.Status = .idle
    @State private var resetMFAStatus: CodeSlotsField.Status = .idle
    @State private var newPassword = ""

    private var isResetting: Bool {
        switch auth.phase {
        case .resetCode, .resetMFA, .resetNewPassword: return true
        default: return false
        }
    }

    private var assessment: PasswordPolicy.Assessment { PasswordPolicy.assess(password, email: email) }

    private var signUpAge: Int? {
        guard let birthMonth, let birthYear else { return nil }
        return AgeGate.age(birthMonth: birthMonth, birthYear: birthYear)
    }

    /// Shown only once the age is known to be 13–17, so the under-13 cutoff isn't hinted at.
    private var needsGuardian: Bool {
        guard let age = signUpAge else { return false }
        return age >= AgeGate.minimumAge && age < AgeGate.adultAge
    }

    private var signUpDetailsReady: Bool {
        signUpAge != nil && agreesToTerms && (!needsGuardian || guardianAgrees) && !isSignUpBlocked
    }

    private var canSubmit: Bool {
        guard email.contains("@"), email.contains("."), !password.isEmpty, !auth.isWorking else { return false }
        return mode == .signIn || (assessment.isAcceptable && signUpDetailsReady)
    }

    private var isAwaitingCode: Bool {
        switch auth.phase {
        case .needsMFA, .needsEmailCode: return true
        default: return false
        }
    }

    private var awaitingEmail: String? {
        if case .needsEmailCode(let email, _) = auth.phase { return email }
        return nil
    }

    private var isConfirmingNewAccount: Bool {
        if case .needsEmailCode(_, true) = auth.phase { return true }
        return false
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [SquircleTokens.bgTop(for: "focus"), SquircleTokens.bgBottom(for: "focus")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(colors: [accent.opacity(0.16), .clear], center: .top, startRadius: 40, endRadius: 520)
            GhostFibersBackgroundView(glowColor: accent)

            // Scrolls only when the window is too short for the sign-up form; otherwise centered as before.
            GeometryReader { proxy in
                ScrollView {
                    loginColumn
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .ignoresSafeArea()
        .onAppear { focusedField = .email }
        .environment(\.openURL, OpenURLAction { url in
            if let document = LegalDocument(url: url) {
                openDocument = document
                return .handled
            }
            return .systemAction
        })
        .sheet(item: $openDocument) { LegalReaderView(document: $0) }
        .alert("Continue with Google?", isPresented: $showingGoogleInfo) {
            Button("Continue") { continueWithGoogle() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Google will share your name, email address and profile picture with Locken. They're used only to create your Locken account and sign you in, never for ads, and Locken gets nothing else from your Google account. New accounts are asked their age and to agree to the Terms before using Locken.")
        }
    }

    private var loginColumn: some View {
        VStack(spacing: Spacing.xl) {
            VStack(spacing: 6) {
                Text("Locken")
                    .scriptAccent(size: 64)
                    .foregroundColor(.white)
                Text("Deep work, on your terms.")
                    .font(.appFont(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }

            if isAwaitingCode { codeCard } else if isResetting { resetCard } else { card }
        }
        .frame(maxWidth: 400)
        .padding(Spacing.xl)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            JellyRadioPicker(
                items: Mode.allCases.map(\.rawValue),
                selection: Binding(
                    get: { mode.rawValue },
                    set: { mode = Mode(rawValue: $0) ?? .signIn; auth.errorMessage = nil; auth.noticeMessage = nil }
                ),
                label: "Sign in or create an account",
                accentTab: "focus"
            )
            .frame(maxWidth: .infinity)

            field(label: "EMAIL") {
                TextField("Enter your email", text: $email)
                    .focused($focusedField, equals: .email)
                    .onSubmit { focusedField = .password }
            }

            field(label: "PASSWORD") {
                SecureField(mode == .signUp ? "At least 8 characters" : "Your password", text: $password)
                    .textContentType(mode == .signUp ? .newPassword : .password)
                    .focused($focusedField, equals: .password)
                    .onSubmit(submit)
            }

            if mode == .signIn {
                HStack {
                    Spacer()
                    Button("Forgot password?") {
                        focusedField = nil
                        Task { await auth.startPasswordReset(email: email) }
                    }
                    .buttonStyle(.plain)
                    .font(.appFont(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .disabled(auth.isWorking)
                }
            }

            if mode == .signUp && !password.isEmpty {
                strengthMeter(assessment)
            }

            if mode == .signUp {
                if isSignUpBlocked {
                    Text("Sorry, you can't create a Locken account.")
                        .font(.appFont(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("DATE OF BIRTH")
                            .font(.appFont(size: 10, weight: .bold))
                            .tracking(1.0)
                            .foregroundColor(.white.opacity(0.55))
                        BirthMonthYearPicker(month: $birthMonth, year: $birthYear)
                    }

                    AgreementCheckbox(
                        isOn: $agreesToTerms,
                        label: "I agree to the [Terms of Service](locken-legal:terms) and [Privacy Policy](locken-legal:privacy)",
                        accessibilityText: "I agree to the Terms of Service and Privacy Policy"
                    )

                    if needsGuardian {
                        AgreementCheckbox(
                            isOn: $guardianAgrees,
                            label: "My parent or guardian has read the [Terms of Service](locken-legal:terms) and agrees to them",
                            accessibilityText: "My parent or guardian has read the Terms of Service and agrees to them"
                        )
                    }
                }
            }

            if let message = auth.errorMessage {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.appFont(size: 12, weight: .medium))
                    .foregroundColor(SquircleTokens.textGold)
            } else if let notice = auth.noticeMessage {
                Label(notice, systemImage: "envelope")
                    .font(.appFont(size: 12, weight: .medium))
                    .foregroundColor(SquircleTokens.mintAccent)
            }

            Button(action: submit) {
                HStack(spacing: 8) {
                    if auth.isWorking {
                        LogoTraceLoader(size: 16, strokeWidth: 9)
                    }
                    Text(mode.rawValue)
                        .font(.appFont(size: 14, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .borderGlowButton(accent: accent, isProminent: true)
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.5)
            .keyboardShortcut(.defaultAction)

            HStack(spacing: 10) {
                SectionDivider()
                Text("or").font(.appFont(size: 11)).foregroundColor(.white.opacity(0.55))
                SectionDivider()
            }

            Button(action: { showingGoogleInfo = true }) {
                HStack(spacing: 10) {
                    Text("G")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Continue with Google")
                        .font(.appFont(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
            // A new account through Google needs the same age screen and agreement. Google can also create an
            // account from Sign In, so it's off on a Mac that has stopped sign-up.
            .disabled(auth.isWorking || isSignUpBlocked || (mode == .signUp && !signUpDetailsReady))
            .opacity(isSignUpBlocked || (mode == .signUp && !signUpDetailsReady) ? 0.5 : 1)

            VStack(spacing: 4) {
                if mode == .signIn {
                    Text(LegalMarkdown.inline("By signing in, you agree to the [Terms of Service](locken-legal:terms) and [Privacy Policy](locken-legal:privacy)."))
                        .tint(Color(red: 0.84, green: 0.79, blue: 1.0))
                }
                Text("Your session is kept in the macOS Keychain.")
            }
            .font(.appFont(size: 11))
            .foregroundColor(.white.opacity(0.55))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
        .padding(24)
        .luxuryObsidianCard(cornerRadius: 24)
    }

    /// Four bars and a label, plus the first thing to fix.
    private func strengthMeter(_ result: PasswordPolicy.Assessment) -> some View {
        let color: Color = result.score >= 4 ? SquircleTokens.mintAccent : result.score == 3 ? Color(red: 0.55, green: 0.85, blue: 0.6)
            : result.score == 2 ? SquircleTokens.smokedAmber : Color(red: 0.95, green: 0.45, blue: 0.45)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(index < result.score ? color : Color.white.opacity(0.1))
                        .frame(height: 4)
                }
            }
            HStack {
                Text(result.label)
                    .font(.appFont(size: 11, weight: .semibold))
                    .foregroundColor(color)
                if let problem = result.problems.first {
                    Text(problem)
                        .font(.appFont(size: 11))
                        .foregroundColor(.white.opacity(0.55))
                } else if let tip = result.tip {
                    Text(tip)
                        .font(.appFont(size: 11))
                        .foregroundColor(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: result.score)
    }

    // MARK: Forgot password

    /// Emailed code, then the authenticator code if the account has one, then the new password.
    private var resetCard: some View {
        VStack(spacing: 18) {
            switch auth.phase {
            case .resetCode(let email):
                resetHeader("Check your email", "If there's a Locken account for \(email), we sent it a 6-digit code. Enter it to choose a new password.")
                CodeSlotsField(status: $resetCodeStatus, accent: Color(red: 0.84, green: 0.79, blue: 1.0)) { code in
                    Task { resetCodeStatus = await auth.verifyResetCode(code) ? .success : .error }
                }
                resetMessages
                HStack(spacing: 18) {
                    Button("Send a new code") { Task { await auth.startPasswordReset(email: email) } }
                        .buttonStyle(.plain)
                        .font(.appFont(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .disabled(auth.isWorking)
                    backToSignIn
                }
            case .resetMFA:
                resetHeader("Enter your authenticator code", "Your account uses an authenticator app. Type its 6-digit code for Locken to continue.")
                CodeSlotsField(status: $resetMFAStatus, accent: Color(red: 0.84, green: 0.79, blue: 1.0)) { code in
                    Task { resetMFAStatus = await auth.verifyResetMFA(code: code) ? .success : .error }
                }
                resetMessages
                backToSignIn
            case .resetNewPassword(let email):
                let result = PasswordPolicy.assess(newPassword, email: email)
                resetHeader("Choose a new password", "Your other Macs will be signed out. This Mac stays signed in.")
                VStack(alignment: .leading, spacing: Spacing.s) {
                    field(label: "NEW PASSWORD") {
                        SecureField("At least 8 characters", text: $newPassword)
                            .textContentType(.newPassword)
                            .onSubmit(saveNewPassword)
                    }
                    if !newPassword.isEmpty { strengthMeter(result) }
                }
                resetMessages
                Button(action: saveNewPassword) {
                    HStack(spacing: 8) {
                        if auth.isWorking { LogoTraceLoader(size: 16, strokeWidth: 9) }
                        Text("Save New Password")
                            .font(.appFont(size: 14, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .borderGlowButton(accent: accent, isProminent: true)
                }
                .buttonStyle(.plain)
                .disabled(!result.isAcceptable || auth.isWorking)
                .opacity(result.isAcceptable ? 1 : 0.5)
                .keyboardShortcut(.defaultAction)
                backToSignIn
            default:
                EmptyView()
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .luxuryObsidianCard(cornerRadius: 24)
        .onChange(of: auth.phase) { _, _ in
            resetCodeStatus = .idle
            resetMFAStatus = .idle
        }
    }

    private func resetHeader(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.appFont(size: 17, weight: .bold))
                .foregroundColor(.white)
            Text(detail)
                .font(.appFont(size: 12))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var resetMessages: some View {
        if let message = auth.errorMessage {
            Text(message)
                .font(.appFont(size: 12, weight: .medium))
                .foregroundColor(SquircleTokens.textGold)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        } else if let notice = auth.noticeMessage {
            Text(notice)
                .font(.appFont(size: 12, weight: .medium))
                .foregroundColor(SquircleTokens.mintAccent)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var backToSignIn: some View {
        Button("Back to sign in") {
            newPassword = ""
            auth.cancelPasswordReset()
        }
        .buttonStyle(.plain)
        .font(.appFont(size: 12, weight: .semibold))
        .foregroundColor(.white.opacity(0.6))
    }

    private func saveNewPassword() {
        guard !auth.isWorking else { return }
        Task {
            await auth.finishPasswordReset(newPassword: newPassword)
            if auth.user != nil { newPassword = "" }
        }
    }

    /// Second step for accounts with an authenticator app.
    private var codeCard: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text(awaitingEmail != nil ? "Check your email" : "Enter your code")
                    .font(.appFont(size: 17, weight: .bold))
                    .foregroundColor(.white)
                Text(awaitingEmail.map { "We sent a 6-digit code to \($0). Paste or type it below. This Mac will stay signed in afterwards." }
                     ?? "Open your authenticator app (e.g. Google Authenticator) and type the 6-digit code for Locken.")
                    .font(.appFont(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            CodeSlotsField(status: $codeStatus, accent: Color(red: 0.84, green: 0.79, blue: 1.0)) { code in
                Task {
                    let ok = awaitingEmail != nil ? await auth.verifyEmailCode(code) : await auth.verifyMFA(code: code)
                    codeStatus = ok ? .success : .error
                }
            }

            if let message = auth.errorMessage {
                Text(message)
                    .font(.appFont(size: 12, weight: .medium))
                    .foregroundColor(SquircleTokens.textGold)
                    .multilineTextAlignment(.center)
            }

            if let notice = auth.noticeMessage {
                Text(notice)
                    .font(.appFont(size: 12, weight: .medium))
                    .foregroundColor(SquircleTokens.mintAccent)
            }

            // Supabase sends nothing when the email already has an account (so it can't be used to check who's
            // signed up). This hint covers that case without saying which one applies.
            if isConfirmingNewAccount {
                Text("No email after a minute? If you already have a Locken account (including one made with Google), sign in instead.")
                    .font(.appFont(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 18) {
                if awaitingEmail != nil {
                    Button("Send a new code") { Task { await auth.resendEmailCode() } }
                        .buttonStyle(.plain)
                        .font(.appFont(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .disabled(auth.isWorking)
                }
                Button("Use a different account") {
                    if awaitingEmail != nil { auth.cancelEmailCode() } else { Task { await auth.signOut() } }
                }
                .buttonStyle(.plain)
                .font(.appFont(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .luxuryObsidianCard(cornerRadius: 24)
    }

    private func field<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.appFont(size: 10, weight: .bold))
                .tracking(1.0)
                .foregroundColor(.white.opacity(0.5))
            content()
                .textFieldStyle(.plain)
                .font(.appFont(size: 14))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 1))
                )
        }
    }

    /// The age screen, before any account is created. Under 13 stops sign-up on this Mac for good; otherwise the
    /// answer is kept for the new account (AI features need 18+).
    private func passesAgeCheck() -> Bool {
        guard let birthMonth, let birthYear, let age = signUpAge else { return false }
        guard age >= AgeGate.minimumAge else {
            AgeGate.blockSignUp()
            isSignUpBlocked = true
            return false
        }
        AgeGate.shared.rememberForNewAccount(month: birthMonth, year: birthYear)
        AgeGate.shared.rememberAgreementForNewAccount()
        return true
    }

    private func submit() {
        guard canSubmit else { return }
        if mode == .signUp {
            guard passesAgeCheck() else { return }
        } else {
            AgeGate.shared.clearPending()
        }
        Task {
            if mode == .signIn {
                await auth.signIn(email: email, password: password)
            } else {
                await auth.signUp(email: email, password: password)
            }
            if auth.user != nil { password = "" }
        }
    }

    private func continueWithGoogle() {
        if mode == .signUp {
            guard signUpDetailsReady, passesAgeCheck() else { return }
        } else {
            AgeGate.shared.clearPending()
        }
        auth.signInWithGoogle()
    }
}

/// The window's intro moments, kept outside `DisplayScaleRoot` so they survive it rebuilding the window (which it
/// does when the window moves between a Retina and a standard screen); otherwise the receipt welcome would cut out
/// and the startup reveal play again mid-welcome.
/// - The padlock reveal plays over whatever opens first, every time a window opens.
/// - Every sign-in and sign-up is followed by the $0.00 receipt welcome (not reopening Locken while signed in). It
///   covers the window the moment the session exists, so the app is never seen before it; the app loads behind it
///   and is revealed as the receipt falls.
/// True while the startup reveal or the sign-in welcome covers the app. The app is already on screen underneath, so
/// things that play once when it opens (the greeting's signature) wait for this to clear and are seen being written.
@MainActor
final class IntroCover: ObservableObject {
    static let shared = IntroCover()
    @Published var isActive = true
}

struct IntroHost<Content: View>: View {
    @ObservedObject private var auth = AuthManager.shared
    @State private var showsLaunchReveal = true
    @State private var showsReceipt = false
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var signInWelcome: Bool { auth.justSignedIn && auth.user != nil }
    private var isCovering: Bool { showsLaunchReveal || showsReceipt || signInWelcome }

    var body: some View {
        content
            .overlay {
                if showsLaunchReveal {
                    LaunchRevealView { showsLaunchReveal = false }
                } else if showsReceipt || signInWelcome {
                    ReceiptIntroView {
                        showsReceipt = false
                        auth.finishSignInWelcome()
                    }
                }
            }
            .onChange(of: isCovering, initial: true) { _, covering in IntroCover.shared.isActive = covering }
            .onAppear {
                #if DEBUG
                // Testing only: `-previewReceipt YES` plays the receipt welcome right after the startup reveal.
                if UserDefaults.standard.bool(forKey: "previewReceipt") { showsReceipt = true }
                #endif
            }
    }
}

/// Cloudflare's checkbox, shown at the bottom of the sign-in screens only while it needs a click.
struct TurnstileOverlay: View {
    @ObservedObject private var gate = TurnstileGate.shared

    var body: some View {
        if TurnstileGate.isEnabled {
            VStack(spacing: 8) {
                Text("Quick check that you're a person")
                    .font(.appFont(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.75))
                TurnstileWidget()
                    .frame(width: 300, height: 70)
            }
            .padding(14)
            .liquidGlassCard(cornerRadius: 18)
            .padding(.bottom, 28)
            .opacity(gate.needsInteraction ? 1 : 0)
            .allowsHitTesting(gate.needsInteraction)
            .animation(.easeOut(duration: 0.2), value: gate.needsInteraction)
        }
    }
}

/// Shows the app only for a verified session; everything else sees the sign-in screen.
struct AuthGate: View {
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var habits = HabitStore.shared
    @ObservedObject private var ageGate = AgeGate.shared
    @ObservedObject private var updater = AppUpdater.shared
    @ObservedObject private var feedback = FeedbackManager.shared
    @State private var activatedUserID: String?
    var body: some View {
        gatedContent
            // Signed-update checks: at launch and every 6 hours.
            .task { AppUpdater.shared.start() }
    }

    @ViewBuilder
    private var gatedContent: some View {
        switch auth.phase {
        case .restoring:
            LogoTraceLoader(size: 44, ariaLabel: "Opening Locken")
                .frame(minWidth: 1140, minHeight: 740)
                .background(SquircleTokens.bgBottom(for: "dashboard"))
        case .signedOut, .needsMFA, .needsEmailCode, .resetCode, .resetMFA, .resetNewPassword:
            LoginView()
                .frame(minWidth: 1140, minHeight: 740)
                .revealWhenLoaded()
                // The bot check (when switched on): invisible unless Cloudflare asks the person to click.
                .overlay(alignment: .bottom) { TurnstileOverlay() }
        case .signedIn(let user):
            Group {
                if activatedUserID != user.id {
                    LogoTraceLoader(size: 44, ariaLabel: "Opening Locken")
                        .frame(minWidth: 1140, minHeight: 740)
                        .background(SquircleTokens.bgBottom(for: "dashboard"))
                } else if !ageGate.hasCompletedConsent && ageGate.isSyncing {
                    // Checking the account for an answer given on another Mac before asking.
                    LogoTraceLoader(size: 44, ariaLabel: "Opening Locken")
                        .frame(minWidth: 1140, minHeight: 740)
                        .background(SquircleTokens.bgBottom(for: "dashboard"))
                } else if !ageGate.hasCompletedConsent {
                    // Any account without an age and agreement on this Mac or on the account (e.g. a new Google
                    // account made from the Sign In tab) completes them before anything else.
                    ConsentGateView()
                        .frame(minWidth: 1140, minHeight: 740)
                } else {
                    MainContentView()
                        // The pause question and the finish celebration float over whatever page is open.
                        .overlay { SessionMomentsOverlay() }
                        // Commitment mode's "Stay with it?" countdown floats over everything.
                        .overlay { CommitmentGateOverlay() }
                        .overlay(alignment: .top) { UpdateBanner() }
                        .sheet(isPresented: $updater.isWhatsNewPresented) { WhatsNewSheet() }
                        .background {
                            // After a week on this Mac, a one-time "how's it going?" (a separate host so it doesn't
                            // clash with the update sheet).
                            Color.clear.sheet(isPresented: $feedback.isPresented) { FeedbackSheet() }
                        }
                        .revealWhenLoaded()
                }
            }
            .onAppear { activate(user.id) }
            .onChange(of: user.id) { _, id in activate(id) }
        }
    }

    /// Loads this account's locally saved data.
    private func activate(_ userID: String) {
        // This view can appear again for the same account; then the conversation on screen stays.
        let switched = AccountScope.userID != userID
        AccountScope.activate(userID)
        AgeGate.shared.activateAccount()
        habits.activate(userID: userID)
        TestAppStateManager.shared.activateAccount(userID: userID)
        ScreenUsageTracker.shared.activateAccount()
        NowPlayingService.shared.activateAccount()
        CanvasAPIManager.shared.activateAccount()
        AppBlockingManager.shared.activateAccount()
        AdminManager.shared.activateAccount()
        WorkspaceLineup.shared.activateAccount()
        AITaskFormatter.shared.activateAccount()
        AppleNotesService.shared.activateAccount()
        if switched {
            // A different account never sees the last one's conversation, and its own history loads.
            VoiceAssistant.shared.reset()
            AssistantHistoryStore.shared.activateAccount()
        }
        VoiceAssistant.shared.startHotkey()
        AIDigestStore.shared.reset()
        // Canvas loads lazily elsewhere; refresh now so this account's assignments are ready.
        if CanvasAPIManager.shared.isLinked { Task { await CanvasAPIManager.shared.refresh() } }
        activatedUserID = userID
        FeedbackManager.shared.activateAccount()
    }
}

// MARK: - Settings: authenticator app (TOTP)

struct TwoFactorCard: View {
    @ObservedObject private var auth = AuthManager.shared
    @State private var enrollment: AuthManager.Enrollment?
    @State private var codeStatus: CodeSlotsField.Status = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Two-Factor Authentication")
                        .font(.appFont(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Text(auth.totpFactorID != nil ? "On · a code from your authenticator app is needed to sign in"
                                                  : "Require a 6-digit code from Google Authenticator or similar")
                        .font(.appFont(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                if auth.totpFactorID != nil {
                    button("Turn Off", prominent: false) { Task { await auth.removeTOTP() } }
                } else if enrollment == nil {
                    button("Set Up", prominent: true) { Task { enrollment = await auth.beginTOTPEnrollment() } }
                }
            }

            if let enrollment, auth.totpFactorID == nil {
                HStack(alignment: .top, spacing: 18) {
                    if let image = Self.qrImage(enrollment.qrCodeSVG) {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.none)
                            .frame(width: 150, height: 150)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .accessibilityLabel("QR code for your authenticator app")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("1. Scan the QR code in your authenticator app, or enter this key:")
                            .font(.appFont(size: 12))
                            .foregroundColor(.white.opacity(0.75))
                        Text(enrollment.secret)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.white)
                            .textSelection(.enabled)
                        Text("2. Type the 6-digit code it shows:")
                            .font(.appFont(size: 12))
                            .foregroundColor(.white.opacity(0.75))
                        CodeSlotsField(status: $codeStatus, accent: SquircleTokens.accentColor(for: "customize").lightened(0.5)) { code in
                            Task {
                                let ok = await auth.confirmTOTPEnrollment(enrollment, code: code)
                                codeStatus = ok ? .success : .error
                                if ok { self.enrollment = nil }
                            }
                        }
                    }
                }
            }

            if let message = auth.errorMessage {
                Text(message)
                    .font(.appFont(size: 11))
                    .foregroundColor(SquircleTokens.textGold)
            }
        }
        .padding(Spacing.l)
        .innerObsidianCard(cornerRadius: 16)
    }

    private func button(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.appFont(size: 12, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .borderGlowButton(accent: SquircleTokens.accentColor(for: "customize"), isProminent: prominent)
        }
        .buttonStyle(.plain)
        .disabled(auth.isWorking)
    }

    /// Supabase returns the QR code as an SVG (sometimes wrapped in a data URL).
    static func qrImage(_ svg: String) -> NSImage? {
        var markup = svg
        if markup.hasPrefix("data:"), let comma = markup.firstIndex(of: ",") {
            markup = String(markup[markup.index(after: comma)...])
            markup = markup.removingPercentEncoding ?? markup
        }
        return NSImage(data: Data(markup.utf8))
    }
}

// MARK: - Launch reveal

/// Opening screen, about 2.4 s: on the same rounded tile as every page (slightly see-through over the app), "Locken" signs itself in cursive (the same
/// pen-stroke writing as the greeting's name), "Focus for Mac" fades in under it, then it all fades to the app.
/// Quiet on purpose: no logo, glow or motion besides the writing. A click or any key skips it. With Reduce Motion
/// the name appears written and the screen simply fades.
struct LaunchRevealView: View {
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var taglineShown = false
    @State private var isLeaving = false
    @State private var sequence: Task<Void, Never>?
    @FocusState private var isFocused: Bool

    private static func easeOut(_ duration: Double) -> Animation { .timingCurve(0.23, 1, 0.32, 1, duration: duration) }

    var body: some View {
        ZStack {
            // The same tile as every page's background (82% colour over glass, rounded corners), filling the
            // window with a small margin, so the app shows faintly through it.
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(SimpleHomeView.background.opacity(0.82))
                .liquidGlassCard(cornerRadius: 24)
                .padding(12)
            VStack(spacing: 14) {
                SignatureText(text: "Locken", size: 60, duration: 1.5, delay: 0.15, playKey: "launch")
                    .foregroundColor(.white)
                Text("Focus for Mac")
                    .font(.appFont(size: 12, weight: .medium))
                    .tracking(2.4)
                    .foregroundColor(.white.opacity(0.55))
                    .opacity(taglineShown ? 1 : 0)
            }
            .opacity(isLeaving ? 0 : 1)
        }
        .opacity(isLeaving ? 0 : 1)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress { _ in finish(); return .handled }
        .accessibilityHidden(true)
        .onAppear {
            isFocused = true
            sequence = Task { await play() }
        }
        .onDisappear { sequence?.cancel() }
    }

    private func play() async {
        guard await pause(reduceMotion ? 300 : 1400) else { return }
        withAnimation(Self.easeOut(0.5)) { taglineShown = true }
        guard await pause(reduceMotion ? 500 : 1000) else { return }
        finish()
    }

    /// Waits, and reports false if the reveal was skipped meanwhile.
    private func pause(_ milliseconds: Int) async -> Bool {
        try? await Task.sleep(for: .milliseconds(milliseconds))
        return !Task.isCancelled
    }

    private func finish() {
        guard !isLeaving else { return }
        sequence?.cancel()
        withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.45)) { isLeaving = true }
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 200 : 450))
            onFinished()
        }
    }
}

/// The padlock's shackle: up one side, over the top in a half circle, and down the other side.
struct ShackleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = rect.width / 2
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(center: CGPoint(x: rect.midX, y: rect.minY + radius), radius: radius,
                    startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}
