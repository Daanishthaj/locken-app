import SwiftUI

/// Floats the pause question or the finish celebration over the whole window, on the app's own glass, never a
/// black box.
struct SessionMomentsOverlay: View {
    @ObservedObject private var state = TestAppStateManager.shared

    var body: some View {
        ZStack {
            if let session = state.completedSession {
                SessionCelebrationView(session: session)
                    .transition(.opacity)
            } else if state.isPauseReasonPresented {
                PauseReasonView()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: state.completedSession)
        .animation(.easeOut(duration: 0.2), value: state.isPauseReasonPresented)
    }
}

private struct MomentBackdrop: View {
    let accent: Color

    var body: some View {
        ZStack {
            // Dark glass: the app dims almost to black behind the question, with a faint glow of the accent.
            Rectangle().fill(.ultraThinMaterial)
            Color.black.opacity(0.72)
            RadialGradient(colors: [accent.opacity(0.12), .clear], center: .center, startRadius: 20, endRadius: 520)
        }
        .ignoresSafeArea()
        // Swallows clicks so nothing underneath is pressed by accident.
        .contentShape(Rectangle())
        .onTapGesture {}
    }
}

// MARK: - Celebration

/// A finished session: the Locken padlock unlocks, then what the session achieved (real numbers only).
/// Rare, earned moment, so it gets a short sequence (~1.2 s); Reduce Motion shows it open and still.
struct SessionCelebrationView: View {
    let session: TestAppStateManager.CompletedSession

    @ObservedObject private var state = TestAppStateManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isUnlocked = false
    @State private var bodyPulse = false
    @State private var detailsShown = false

    private let accent = SquircleTokens.logoViolet
    private static func easeOut(_ duration: Double) -> Animation { .timingCurve(0.23, 1, 0.32, 1, duration: duration) }
    private static func easeInOut(_ duration: Double) -> Animation { .timingCurve(0.77, 0, 0.175, 1, duration: duration) }

    private var stats: [String] {
        var items = ["\(session.minutes) min focused"]
        if session.stepsTotal > 0 { items.append("\(session.stepsDone) of \(session.stepsTotal) steps done") }
        if session.distractionsBlocked > 0 {
            items.append("\(session.distractionsBlocked) distraction\(session.distractionsBlocked == 1 ? "" : "s") blocked")
        }
        return items
    }

    var body: some View {
        ZStack {
            MomentBackdrop(accent: accent)

            VStack(spacing: Spacing.l) {
                padlock
                    .accessibilityHidden(true)

                VStack(spacing: Spacing.xs) {
                    TextGenerateEffect(session.endedEarly ? "Finished early" : "Session complete")
                        .scriptAccent(size: 44)
                        .foregroundColor(.white)
                    if !session.goal.isEmpty {
                        Text(session.goal)
                            .font(.appFont(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(maxWidth: 460)
                    }
                }

                HStack(spacing: Spacing.s) {
                    ForEach(Array(stats.enumerated()), id: \.offset) { index, item in
                        Text(item)
                            .font(.appFont(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .innerObsidianCard(cornerRadius: 12)
                            .opacity(detailsShown ? 1 : 0)
                            .offset(y: detailsShown || reduceMotion ? 0 : 8)
                            .animation(
                                reduceMotion ? .easeOut(duration: 0.2) : Self.easeOut(0.45).delay(Double(index) * 0.06),
                                value: detailsShown
                            )
                    }
                }

                HStack(spacing: Spacing.m) {
                    Button("Start Another") {
                        state.dismissCelebration()
                        state.selectedTab = "dashboard"
                    }
                    .buttonStyle(.plain)
                    .quietAction()

                    Button(action: { state.dismissCelebration() }) {
                        Text("Done")
                            .font(.appFont(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 10)
                            .borderGlowButton(accent: SquircleTokens.accentColor(for: "focus"), isProminent: true)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                }
                .opacity(detailsShown ? 1 : 0)
                .animation(reduceMotion ? .easeOut(duration: 0.2) : Self.easeOut(0.4).delay(0.2), value: detailsShown)
            }
            .padding(Spacing.xl)
        }
        .onAppear(perform: play)
        .onExitCommand { state.dismissCelebration() }
    }

    private var padlock: some View {
        ZStack(alignment: .top) {
            Circle()
                .fill(accent)
                .frame(width: 150, height: 150)
                .blur(radius: 44)
                .opacity(isUnlocked ? 0.45 : 0.15)
                .offset(y: 50)

            // The shackle lifts out of the body and swings open on its right leg.
            ShackleShape()
                .stroke(
                    LinearGradient(colors: [accent.lightened(0.35), accent], startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: 13, lineCap: .round)
                )
                .frame(width: 70, height: 66)
                .rotationEffect(.degrees(isUnlocked ? -22 : 0), anchor: .bottomTrailing)
                .offset(y: isUnlocked ? -14 : 8)

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [accent.lightened(0.15), SquircleTokens.royalPlum.opacity(0.95), accent],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundColor(.white)
                        .opacity(isUnlocked ? 1 : 0)
                        .scaleEffect(isUnlocked || reduceMotion ? 1 : 0.9)
                )
                .frame(width: 116, height: 92)
                .scaleEffect(bodyPulse ? 1.04 : 1, anchor: .bottom)
                .offset(y: 58)
        }
        .frame(width: 150, height: 160)
    }

    private func play() {
        AccessibilityNotification.Announcement(
            "\(session.endedEarly ? "Finished early" : "Session complete"). \(stats.joined(separator: ", "))."
        ).post()
        guard !reduceMotion else {
            isUnlocked = true
            detailsShown = true
            return
        }
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(Self.easeInOut(0.4)) { isUnlocked = true }
            try? await Task.sleep(for: .milliseconds(300))
            // A small spring settle as the lock opens; the one bounce in the sequence.
            withAnimation(.spring(duration: 0.35, bounce: 0.2)) { bodyPulse = true }
            try? await Task.sleep(for: .milliseconds(160))
            withAnimation(.spring(duration: 0.35, bounce: 0.2)) { bodyPulse = false }
            detailsShown = true
        }
    }
}

// MARK: - Pause question

/// Asked before a session pauses. The timer keeps running until a reason is chosen and confirmed;
/// "Finished early" ends the session as done.
struct PauseReasonView: View {
    @ObservedObject private var state = TestAppStateManager.shared
    @State private var reason = ""
    @State private var otherText = ""
    @FocusState private var isOtherFocused: Bool

    private let accent = SquircleTokens.accentColor(for: "focus")
    private var chosen: TestAppStateManager.PauseReason? { TestAppStateManager.PauseReason(rawValue: reason) }
    private var trimmedOther: String { otherText.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// "Other" needs the student to say what the reason is before the session can pause.
    private var otherProblem: String? { TestAppStateManager.otherPauseReasonProblem(otherText) }
    private var canConfirm: Bool { chosen != nil && (chosen != .other || otherProblem == nil) }

    private func confirm() {
        guard canConfirm, let chosen else { return }
        state.confirmPause(chosen, note: chosen == .other ? trimmedOther : nil)
    }

    var body: some View {
        ZStack {
            MomentBackdrop(accent: accent)

            VStack(spacing: Spacing.l) {
                VStack(spacing: Spacing.xs) {
                    TextGenerateEffect("Why are you pausing?")
                        .scriptAccent(size: 38)
                        .foregroundColor(.white)
                    Text(String(format: "%d:%02d left", state.timerSecondsRemaining / 60, state.timerSecondsRemaining % 60)
                         + (state.focusGoal.isEmpty ? "" : " on \(state.focusGoal)"))
                        .font(.appFont(size: 13))
                        .monospacedDigit()
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(maxWidth: 480)
                }

                JellyRadioPicker(
                    items: TestAppStateManager.PauseReason.allCases.map(\.rawValue),
                    selection: $reason,
                    label: "Why are you pausing?"
                )
                .frame(maxWidth: 640)

                if chosen == .other {
                    TextField("Type why you're pausing", text: $otherText)
                        .textFieldStyle(.plain)
                        .font(.appFont(size: 14))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 1))
                        )
                        .frame(maxWidth: 420)
                        .focused($isOtherFocused)
                        .onSubmit(confirm)
                        .onAppear { isOtherFocused = true }
                        .accessibilityLabel("Why you're pausing")
                }

                Text(chosen != .other ? "The timer keeps running until you choose."
                     : trimmedOther.isEmpty ? "Type a reason to pause. The timer keeps running until you do."
                     : (otherProblem ?? "The timer keeps running until you pause."))
                    .font(.appFont(size: 11))
                    .foregroundColor(.white.opacity(0.55))

                HStack(spacing: Spacing.m) {
                    Button("Keep Focusing") { state.isPauseReasonPresented = false }
                        .buttonStyle(.plain)
                        .quietAction()
                        .keyboardShortcut(.cancelAction)

                    Button(action: confirm) {
                        Text(chosen == .finished ? "Finish Session" : "Pause")
                            .font(.appFont(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 10)
                            .borderGlowButton(accent: accent, isProminent: true)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canConfirm)
                    .opacity(canConfirm ? 1 : 0.5)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(Spacing.xl)
        }
        // The question only matters while a session runs; if it ends meanwhile, close it.
        .onChange(of: state.isTimerActive) { _, active in
            if !active { state.isPauseReasonPresented = false }
        }
    }
}
