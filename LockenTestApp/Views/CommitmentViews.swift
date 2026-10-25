import AppKit
import SwiftUI

/// Whether Locken may quit right now. Normally a running session (with commitment mode on) turns a quit into
/// the commitment countdown; Mac shutdown, logout and installing an update always go straight through.
enum AppQuit {
    static var isAllowed = false

    /// Why Locken is quitting, which decides what happens to a running session.
    enum Reason {
        /// The student quit: the session ends.
        case user
        /// Installing an update: the session is kept and the new version picks it up.
        case update
        /// Shutdown, restart or logout: the session is kept and picks up when Locken next opens.
        case powerOff
    }
    static var reason: Reason = .user
}

// MARK: - Commitment countdown

/// "Stay with it?": shown when the student tries to pause, end early or quit during a session with commitment
/// mode on. The stop button unlocks after a short countdown (10 s to pause, 20 s to end or quit); "Keep
/// focusing" is the main action, and Escape picks it too. It floats over the app on a dark glass card.
struct CommitmentGateView: View {
    @ObservedObject private var state = TestAppStateManager.shared
    let action: TestAppStateManager.CommitmentAction

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var secondsLeft: Int = 20
    @State private var ticker: Timer?

    private var accent: Color { SquircleTokens.accentColor(for: "focus") }
    private var unlocked: Bool { secondsLeft <= 0 }

    private var title: String {
        switch action {
        case .pause: return "Pause this session?"
        case .end: return "End this session early?"
        case .quit: return "Quit Locken mid-session?"
        case .shieldOff: return "Turn off the Shield?"
        }
    }

    private var stopLabel: String {
        switch action {
        case .pause: return "Pause"
        case .end: return "End session"
        case .quit: return "Quit Locken"
        case .shieldOff: return "Turn off the Shield"
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {}
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: CGFloat(secondsLeft) / CGFloat(action.waitSeconds))
                        .stroke(accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(reduceMotion ? nil : .linear(duration: 1), value: secondsLeft)
                    Text(unlocked ? "OK" : "\(secondsLeft)")
                        .font(.appFont(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .contentTransition(.numericText(countsDown: true))
                }
                .frame(width: 84, height: 84)

                VStack(spacing: 6) {
                    Text(title)
                        .font(.appFont(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    if !state.focusGoal.isEmpty {
                        Text("“\(state.focusGoal)”")
                            .font(.appFont(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    Text("\(Self.clock(state.timerSecondsRemaining)) left. You set this time for a reason. Take a breath before you decide.")
                        .font(.appFont(size: 12))
                        .foregroundColor(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: state.cancelCommitment) {
                    Text("Keep focusing")
                        .font(.appFont(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(accent))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)

                Button(action: state.confirmCommitment) {
                    Text(unlocked ? stopLabel : "\(stopLabel) in \(secondsLeft)s")
                        .quietAction()
                        .opacity(unlocked ? 1 : 0.45)
                }
                .buttonStyle(.plain)
                .disabled(!unlocked)
                .accessibilityHint(unlocked ? "" : "Available in \(secondsLeft) seconds")
            }
            .padding(28)
            .frame(width: 360)
            // Dark glass, like every pop-up.
            .background(SimpleHomeView.background.opacity(0.9).clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous)))
            .liquidGlassCard(cornerRadius: 24)
            .shadow(color: .black.opacity(0.4), radius: 30, y: 16)
        }
        .onAppear(perform: start)
        .onDisappear { ticker?.invalidate() }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private func start() {
        secondsLeft = action.waitSeconds
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            Task { @MainActor in
                if secondsLeft > 0 { secondsLeft -= 1 }
                if secondsLeft <= 0 { timer.invalidate() }
            }
        }
    }

    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Shows the commitment card over the app whenever a stop is waiting.
struct CommitmentGateOverlay: View {
    @ObservedObject private var state = TestAppStateManager.shared

    var body: some View {
        ZStack {
            if let action = state.commitmentRequest {
                CommitmentGateView(action: action)
                    .id(action)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.25), value: state.commitmentRequest)
    }
}

/// The switch in Settings.
struct CommitmentModeToggle: View {
    @ObservedObject private var state = TestAppStateManager.shared

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Commitment mode")
                    .font(.appFont(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text("Pausing, ending a session early, turning off the Shield or quitting Locken mid-session waits a few seconds first, so stopping is a choice, not a reflex.")
                    .font(.appFont(size: 11))
                    .foregroundColor(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: $state.isCommitmentModeOn)
                .toggleStyle(GlassSwitchToggleStyle())
                .accessibilityLabel("Commitment mode")
        }
    }
}

// MARK: - Menu bar timer

/// The menu bar item: the Locken padlock, with the time left while a session runs (shackle lifted while paused).
struct MenuBarTimerLabel: View {
    @ObservedObject private var state = TestAppStateManager.shared
    private static let closed = LockenLogo.menuBarImage(open: false)
    private static let open = LockenLogo.menuBarImage(open: true)

    var body: some View {
        if state.isTimerActive {
            Text("\(Image(nsImage: Self.closed)) \(CommitmentGateView.clock(state.timerSecondsRemaining))")
                .monospacedDigit()
        } else if state.isGoalDefined && state.timerSecondsRemaining < state.timerTotalSeconds {
            Text("\(Image(nsImage: Self.open)) \(CommitmentGateView.clock(state.timerSecondsRemaining))")
                .monospacedDigit()
        } else {
            Image(nsImage: Self.closed)
        }
    }
}

/// The panel under the menu bar item: the goal and time left with Pause/Resume and End (both through commitment
/// mode), or a way to start a session.
struct MenuBarTimerPanel: View {
    @ObservedObject private var state = TestAppStateManager.shared
    @Environment(\.openWindow) private var openWindow

    private var accent: Color { SquircleTokens.accentColor(for: "focus") }
    private var hasSession: Bool { state.isTimerActive || (state.isGoalDefined && state.timerSecondsRemaining < state.timerTotalSeconds) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                LogoTraceLoader(loading: false, size: 18)
                    .foregroundColor(accent)
                Text("Locken")
                    .font(.appFont(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
            }

            if hasSession {
                VStack(alignment: .leading, spacing: 6) {
                    Text(state.focusGoal.isEmpty ? "Focus session" : state.focusGoal)
                        .font(.appFont(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    Text(CommitmentGateView.clock(state.timerSecondsRemaining))
                        .font(.appFont(size: 30, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(.white)
                    ProgressView(value: Double(max(0, state.timerTotalSeconds - state.timerSecondsRemaining)),
                                 total: Double(max(1, state.timerTotalSeconds)))
                        .tint(accent)
                    Text(state.isTimerActive ? "The Shield is on." : "Paused. The Shield is off.")
                        .font(.appFont(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                }
                HStack(spacing: 10) {
                    Button(state.isTimerActive ? "Pause" : "Resume") {
                        if state.isTimerActive { showApp() }
                        state.toggleTimer()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    Button("End") {
                        showApp()
                        state.requestStop(.end)
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Text("No session running.")
                    .font(.appFont(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                Button("Start a session") {
                    state.selectedTab = "dashboard"
                    showApp()
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
            }

            Divider().opacity(0.3)
            HStack {
                Button("Open Locken", action: showApp).buttonStyle(.plain)
                Spacer()
                Button("Quit") { state.requestStop(.quit); if state.commitmentRequest != nil { showApp() } }
                    .buttonStyle(.plain)
            }
            .font(.appFont(size: 12))
            .foregroundColor(.white.opacity(0.75))
        }
        .padding(16)
        .frame(width: 280)
    }

    /// Brings the Locken window forward, opening it again if it was closed.
    private func showApp() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let window = NSApplication.shared.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }
}
