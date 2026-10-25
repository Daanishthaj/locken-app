import SwiftUI
import EventKit
import UserNotifications
import CoreServices

private let settingsAccent = SquircleTokens.accentColor(for: "customize")

private func cardTitle(_ title: String, _ subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(title)
            .font(.appFont(size: 14, weight: .semibold))
            .foregroundColor(.white)
        Text(subtitle)
            .font(.appFont(size: 11))
            .foregroundColor(.white.opacity(0.55))
            .fixedSize(horizontal: false, vertical: true)
    }
}

private func smallButton(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(title)
            .font(.appFont(size: 12, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .borderGlowButton(accent: settingsAccent, isProminent: prominent)
    }
    .buttonStyle(.plain)
}

// MARK: - Account and sign-in

/// Who's signed in, where the session lives, password change (with an emailed code), sign out on this Mac,
/// and sign out on every Mac.
struct AccountSecurityCard: View {
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var state = TestAppStateManager.shared
    @State private var nameDraft = ""
    @FocusState private var isNameFocused: Bool

    private var trimmedName: String { String(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)) }

    private enum PasswordStep { case idle, sendingCode, enterCode }
    @State private var passwordStep: PasswordStep = .idle
    @State private var newPassword = ""
    @State private var codeStatus: CodeSlotsField.Status = .idle
    @State private var confirmingSignOutEverywhere = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                cardTitle("Account", auth.user?.email ?? "")
                Spacer()
                smallButton("Sign Out", prominent: false) { Task { await auth.signOut() } }
                    .disabled(auth.isWorking)
            }

            Label("Your session is kept in this Mac's Keychain and can't be copied to another device.", systemImage: "lock.fill")
                .font(.appFont(size: 11))
                .foregroundColor(.white.opacity(0.6))

            SectionDivider()

            HStack(spacing: 12) {
                cardTitle("Your name", "Shown in the dashboard greeting and on your profile card. Saved on this Mac.")
                Spacer()
                TextField("Your name", text: $nameDraft)
                    .textFieldStyle(.plain)
                    .font(.appFont(size: 13))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(width: 180)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 1))
                    )
                    .focused($isNameFocused)
                    .onSubmit { state.displayName = trimmedName }
                    .accessibilityLabel("Your name")
                smallButton("Save", prominent: false) {
                    state.displayName = trimmedName
                    isNameFocused = false
                }
                .disabled(trimmedName == state.displayName)
            }
            .onAppear { nameDraft = state.displayName }
            .onChange(of: state.displayName) { _, name in if !isNameFocused { nameDraft = name } }

            SectionDivider()

            switch passwordStep {
            case .idle, .sendingCode:
                HStack {
                    cardTitle("Password", "Changing it needs a code we email you, and signs out your other Macs.")
                    Spacer()
                    smallButton("Change Password", prominent: false) {
                        passwordStep = .sendingCode
                        Task { passwordStep = await auth.sendPasswordChangeCode() ? .enterCode : .idle }
                    }
                    .disabled(auth.isWorking || passwordStep == .sendingCode)
                }
            case .enterCode:
                passwordForm
            }

            SectionDivider()

            HStack {
                cardTitle("Sign out everywhere", "Signs this account out on every Mac, including this one. Use it if a Mac is lost or shared.")
                Spacer()
                Button { confirmingSignOutEverywhere = true } label: {
                    Text("Sign Out Everywhere…").quietAction()
                }
                .buttonStyle(.plain)
                .disabled(auth.isWorking)
            }

            if passwordStep != .idle || auth.noticeMessage != nil, let message = auth.errorMessage ?? auth.noticeMessage {
                Text(message)
                    .font(.appFont(size: 11))
                    .foregroundColor(auth.errorMessage != nil ? SquircleTokens.textGold : SquircleTokens.mintAccent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.l)
        .innerObsidianCard(cornerRadius: 16)
        .confirmationDialog("Sign out on every Mac?", isPresented: $confirmingSignOutEverywhere) {
            Button("Sign Out Everywhere", role: .destructive) { Task { await auth.signOutEverywhere() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every Mac signed in to this account, including this one, will need your password and an emailed code to sign in again.")
        }
    }

    private var passwordForm: some View {
        let assessment = PasswordPolicy.assess(newPassword, email: auth.user?.email ?? "")
        return VStack(alignment: .leading, spacing: 10) {
            Text("New password")
                .font(.appFont(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
            SecureField("At least 8 characters", text: $newPassword)
                .textContentType(.newPassword)
                .textFieldStyle(.plain)
                .font(.appFont(size: 13))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05)))
                .accessibilityLabel("New password")
            if !newPassword.isEmpty {
                Text(assessment.problems.first ?? assessment.label)
                    .font(.appFont(size: 11))
                    .foregroundColor(assessment.isAcceptable ? SquircleTokens.mintAccent : .white.opacity(0.6))
            }
            Text("Code from your email")
                .font(.appFont(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
            CodeSlotsField(status: $codeStatus, accent: settingsAccent.lightened(0.5)) { code in
                guard assessment.isAcceptable else {
                    codeStatus = .error
                    return
                }
                Task {
                    let ok = await auth.changePassword(to: newPassword, code: code)
                    codeStatus = ok ? .success : .error
                    if ok {
                        newPassword = ""
                        passwordStep = .idle
                    }
                }
            }
            HStack(spacing: 16) {
                Button("Send a new code") { Task { _ = await auth.sendPasswordChangeCode() } }
                    .buttonStyle(.plain)
                    .font(.appFont(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                    .disabled(auth.isWorking)
                Button("Cancel") {
                    newPassword = ""
                    passwordStep = .idle
                    auth.errorMessage = nil
                    auth.noticeMessage = nil
                }
                .buttonStyle(.plain)
                .font(.appFont(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
            }
        }
    }
}

// MARK: - Permissions

/// What macOS lets Locken do, checked live: Calendars, Reminders, notifications, and which apps Locken may
/// control with Apple Events (browsers for the tab blocker and screen time, music apps for Now Playing, Notes).
/// Checking never asks for permission; changes are made in System Settings.
struct PermissionsCard: View {
    private struct AutomationTarget: Identifiable {
        let bundleID: String
        let name: String
        let purpose: String
        var id: String { bundleID }
    }

    private enum Status: Equatable {
        case allowed, denied, notAsked, notRunning, notInstalled, unknown

        var text: String {
            switch self {
            case .allowed: return "Allowed"
            case .denied: return "Not allowed"
            case .notAsked: return "Not asked yet"
            case .notRunning: return "Checked when the app is open"
            case .notInstalled: return "Not installed"
            case .unknown: return "Checking…"
            }
        }
    }

    private static let targets: [AutomationTarget] = [
        .init(bundleID: "com.apple.Safari", name: "Safari", purpose: "Closes blocked tabs, counts site time"),
        .init(bundleID: "com.google.Chrome", name: "Google Chrome", purpose: "Closes blocked tabs, counts site time"),
        .init(bundleID: "company.thebrowser.Browser", name: "Arc", purpose: "Closes blocked tabs, counts site time"),
        .init(bundleID: "ai.perplexity.comet", name: "Comet", purpose: "Closes blocked tabs, counts site time"),
        .init(bundleID: "com.apple.Music", name: "Music", purpose: "Shows the song playing"),
        .init(bundleID: "com.spotify.client", name: "Spotify", purpose: "Shows the song playing"),
        .init(bundleID: "com.apple.Notes", name: "Notes", purpose: "Lists your Apple Notes, if connected"),
    ]

    @State private var calendars: Status = .unknown
    @State private var reminders: Status = .unknown
    @State private var notifications: Status = .unknown
    @State private var automation: [String: Status] = [:]

    private var installedTargets: [AutomationTarget] {
        Self.targets.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                cardTitle("Permissions", "What macOS lets Locken do. Locken never asks for Full Disk Access.")
                Spacer()
                Button { Task { await refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Check again")
                .accessibilityLabel("Check permissions again")
            }

            row("Calendars", "Shows your week in Calendar", calendars)
            row("Reminders", "Shows and edits your reminders", reminders)
            row("Notifications", "Habit and session reminders", notifications)

            Text("CONTROL OTHER APPS")
                .font(.appFont(size: 10, weight: .bold))
                .tracking(1.0)
                .foregroundColor(.white.opacity(0.55))
                .padding(.top, 4)
            ForEach(installedTargets) { target in
                row(target.name, target.purpose, automation[target.bundleID] ?? .unknown)
            }

            HStack {
                Spacer()
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text("Open Privacy & Security").quietAction()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.l)
        .innerObsidianCard(cornerRadius: 16)
        .task { await refresh() }
    }

    private func row(_ title: String, _ purpose: String, _ status: Status) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(status == .allowed ? SquircleTokens.mintAccent : status == .denied ? SquircleTokens.textGold : Color.white.opacity(0.3))
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.appFont(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                Text(purpose)
                    .font(.appFont(size: 11))
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer()
            Text(status.text)
                .font(.appFont(size: 11, weight: .semibold))
                .foregroundColor(status == .denied ? SquircleTokens.textGold : .white.opacity(0.7))
        }
        .accessibilityElement(children: .combine)
    }

    private func refresh() async {
        calendars = Self.status(EKEventStore.authorizationStatus(for: .event))
        reminders = Self.status(EKEventStore.authorizationStatus(for: .reminder))
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: notifications = .allowed
        case .denied: notifications = .denied
        case .notDetermined: notifications = .notAsked
        @unknown default: notifications = .unknown
        }
        let ids = installedTargets.map(\.bundleID)
        // Checking can wait on the other app, so it runs off the main thread, and never shows a prompt.
        let results = await Task.detached(priority: .userInitiated) {
            Dictionary(uniqueKeysWithValues: ids.map { ($0, Self.automationCode(for: $0)) })
        }.value
        for (id, code) in results {
            switch code {
            case noErr: automation[id] = .allowed
            case OSStatus(errAEEventNotPermitted): automation[id] = .denied
            case OSStatus(errAEEventWouldRequireUserConsent): automation[id] = .notAsked
            case OSStatus(procNotFound): automation[id] = .notRunning
            default: automation[id] = .unknown
            }
        }
    }

    private static func status(_ value: EKAuthorizationStatus) -> Status {
        switch value {
        case .fullAccess, .writeOnly: return .allowed
        case .denied, .restricted: return .denied
        case .notDetermined: return .notAsked
        @unknown default: return .unknown
        }
    }

    /// Asks macOS whether Locken may send Apple Events to the app, without prompting the user.
    nonisolated private static func automationCode(for bundleID: String) -> OSStatus {
        var target = AEAddressDesc()
        let created = bundleID.withCString { pointer in
            AECreateDesc(DescType(typeApplicationBundleID), pointer, strlen(pointer), &target)
        }
        guard created == noErr else { return OSStatus(created) }
        defer { AEDisposeDesc(&target) }
        return AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), false)
    }
}

// MARK: - Data on this Mac

/// What Locken keeps on this Mac for the signed-in account, and a way to erase the most personal part.
struct LocalDataCard: View {
    @ObservedObject private var auth = AuthManager.shared
    @State private var confirmingClear = false
    @State private var cleared = false
    @State private var exportNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardTitle("Data on this Mac", "Kept for your account only. Other accounts on this Mac can't see it, and none of it is sent to Locken.")

            VStack(alignment: .leading, spacing: 6) {
                item("Focus stats and session history")
                item("Screen time: app names and website domains (never full addresses), kept 35 days")
                item("Notes, habits and session steps")
                item("Canvas link, AI key and sign-in session, in the Keychain")
            }

            HStack {
                Text(cleared ? "Screen time history cleared." : "Erase recorded app and website time for this account.")
                    .font(.appFont(size: 11))
                    .foregroundColor(cleared ? SquircleTokens.mintAccent : .white.opacity(0.55))
                Spacer()
                Button { confirmingClear = true } label: {
                    Text("Clear Screen Time History…").quietAction()
                }
                .buttonStyle(.plain)
            }

            HStack {
                Text(exportNote ?? "Save a copy of everything Locken keeps about your account, as a JSON file.")
                    .font(.appFont(size: 11))
                    .foregroundColor(exportNote == nil ? .white.opacity(0.55) : SquircleTokens.mintAccent)
                Spacer()
                Button(action: downloadData) {
                    Text("Download My Data…").quietAction()
                }
                .buttonStyle(.plain)
                .disabled(auth.user == nil)
            }
        }
        .padding(Spacing.l)
        .innerObsidianCard(cornerRadius: 16)
        .confirmationDialog("Clear screen time history?", isPresented: $confirmingClear) {
            Button("Clear History", role: .destructive) {
                ScreenUsageTracker.shared.clearHistory()
                cleared = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes the app and website time Locken recorded for this account on this Mac. It can't be undone.")
        }
    }

    private func downloadData() {
        guard let user = auth.user else { return }
        exportNote = "Gathering your data…"
        Task { @MainActor in
            let server = await auth.serverDataForExport()
            guard let data = AccountScope.exportData(for: user.id, email: user.email, server: server) else {
                exportNote = "Couldn't put your data together. Try again."
                return
            }
            save(data)
        }
    }

    private func save(_ data: Data) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Locken data \(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")).json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
            exportNote = "Saved to \(url.lastPathComponent)."
        } catch {
            exportNote = "Couldn't save the file. Try another folder."
        }
    }

    private func item(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").foregroundColor(.white.opacity(0.5))
            Text(text)
                .font(.appFont(size: 12))
                .foregroundColor(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Updates

/// Settings → Updates: the installed version, a manual check, and Update Now when a signed update is ready.
struct UpdatesCard: View {
    @ObservedObject private var updater = AppUpdater.shared

    private var statusText: String {
        switch updater.status {
        case .idle: return "Locken checks for signed updates automatically."
        case .checking: return "Checking…"
        case .upToDate:
            let time = updater.lastChecked.map { " Checked at \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
            let server = updater.serverVersion.map { ", the website offers \($0)." } ?? "."
            return "Locken is up to date." + time + server
        case .available(let version, let notes): return notes.isEmpty ? "Locken \(version) is ready." : "Locken \(version): \(notes)"
        case .installing(let text): return text
        case .failed(let text): return text
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Updates")
                    .font(.appFont(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text("Version \(updater.currentVersion) (\(updater.currentBuild)). \(statusText)")
                    .font(.appFont(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if updater.isUpdateAvailable {
                smallButton("Update Now", prominent: true) { updater.install() }
            } else {
                Button { Task { await updater.check(userInitiated: true) } } label: {
                    Text("Check for Updates").quietAction()
                }
                .buttonStyle(.plain)
                .disabled(updater.status == .checking)
            }
        }
        .padding(Spacing.l)
        .innerObsidianCard(cornerRadius: 16)
    }
}

/// A small note at the top of the window when a signed update is ready. Dismissible; Settings keeps the button.
struct UpdateBanner: View {
    @ObservedObject private var updater = AppUpdater.shared

    var body: some View {
        if case .available(let version, _) = updater.status, !updater.isBannerDismissed {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundColor(settingsAccent.lightened(0.4))
                    .accessibilityHidden(true)
                Text("Locken \(version) is ready")
                    .font(.appFont(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Button("What's new") { updater.isWhatsNewPresented = true }
                    .buttonStyle(.plain)
                    .font(.appFont(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .underline()
                Button { updater.isBannerDismissed = true } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss update notice")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Capsule().fill(.ultraThinMaterial))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .padding(.top, 14)
            .transition(.opacity)
        }
    }
}


// MARK: - What's new in an update

/// The pop-up shown when an update is found: which version, what's in it, and Install / Later.
/// The notes come from the signed update feed; each line (or sentence) becomes one point.
struct WhatsNewSheet: View {
    @ObservedObject private var updater = AppUpdater.shared
    private let accent = SquircleTokens.accentColor(for: "focus")

    private var version: String {
        if case .available(let version, _) = updater.status { return version }
        return ""
    }

    private var points: [String] {
        guard case .available(_, let notes) = updater.status else { return [] }
        return WhatsNewSheet.points(from: notes)
    }

    /// Splits release notes into points: by line if there are several lines, otherwise by sentence or comma list.
    static func points(from notes: String) -> [String] {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var parts = trimmed.components(separatedBy: .newlines)
        if parts.count == 1 { parts = trimmed.components(separatedBy: ". ") }
        if parts.count == 1 { parts = trimmed.components(separatedBy: ", ") }
        return parts
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " -•.\t")) }
            .filter { !$0.isEmpty }
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
    }

    var body: some View {
        // Plain and quiet: a small label, the version as the title, the changes as a simple list. No icon badge,
        // no box around the list, no coloured bullets.
        VStack(alignment: .leading, spacing: 0) {
            Text("Update available")
                .font(.appFont(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.55))
            Text("Locken \(version)")
                .font(.appFont(size: 22, weight: .bold))
                .foregroundColor(.white)
                .padding(.top, 4)
            Text("You're on \(updater.currentVersion). Installing takes a few seconds and reopens Locken.")
                .font(.appFont(size: 12))
                .foregroundColor(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array((points.isEmpty ? ["Fixes and improvements"] : points).enumerated()), id: \.offset) { index, point in
                    if index > 0 {
                        SectionDivider(subtle: true)
                    }
                    Text(point)
                        .font(.appFont(size: 14))
                        .foregroundColor(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 11)
                }
            }
            .padding(.top, 18)

            if !updater.canInstallInPlace {
                Text("Locken isn't in your Applications folder, so Install opens the website to download it.")
                    .font(.appFont(size: 11))
                    .foregroundColor(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }

            HStack {
                Button("Later") { updater.isWhatsNewPresented = false }
                    .buttonStyle(.plain)
                    .quietAction()
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    updater.isWhatsNewPresented = false
                    updater.install()
                } label: {
                    // BorderGlow stays the app's one main button (docs/DESIGN.md).
                    Text("Install")
                        .font(.appFont(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 8)
                        .borderGlowButton(accent: accent, isProminent: true)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 22)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(28)
        .frame(width: 440)
        .background(Color(red: 0.09, green: 0.09, blue: 0.11))
    }
}
