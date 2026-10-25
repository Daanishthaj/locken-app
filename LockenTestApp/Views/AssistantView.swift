//
//  AssistantView.swift
//  LockenTestApp
//
//  The Assistant tab: talk to Locken. Strands is the hero; the mic button is the one main action,
//  replaced by a confirm card whenever the assistant suggests starting a session or adding an event.
//

import SwiftUI

struct AssistantView: View {
    @ObservedObject private var assistant = VoiceAssistant.shared
    @ObservedObject private var state = TestAppStateManager.shared
    @ObservedObject private var ai = AITaskFormatter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var typed = ""
    @State private var optionMonitor: Any?
    @State private var showHistory = false

    private var accent: Color { SquircleTokens.accentColor(for: "assistant") }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Spacing.l) {
                PageHeader(title: "Assistant", subtitle: "Talk to Locken about your work. It plans and starts sessions, knows what's due, and keeps you going.") { historyButton }

                hero
                status

                if !ai.isConfigured {
                    notice("The assistant thinks with your Claude or Gemini key. Add one in Settings to start talking.", action: "Open Settings") {
                        state.selectedTab = "customize"
                    }
                } else if let proposal = assistant.proposal {
                    proposalCard(proposal)
                } else {
                    micButton
                }

                if let error = assistant.errorText {
                    Text(error)
                        .font(.appFont(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)
                }

                if ai.isConfigured { typeField }
                conversation
                options
            }
            .lockenPage(maxWidth: PageWidth.reading)
        }
        .gradualBlurBottom()
        // The microphone stays off until the student presses the button or holds the hotkey. Hands-free listening stops
        // when they leave the tab or switch to another app (`VoiceAssistant.startHotkey` watches for that).
        .onAppear {
            installEscapeInterrupt()
            assistant.prepareVoice() // the voice takes about ten seconds to load: have it ready before the first reply
        }
        .onDisappear {
            assistant.stopConversation()
            removeEscapeInterrupt()
        }
        // History slides in over the page, so the conversation on screen stays where it is.
        .overlay(alignment: .trailing) {
            if showHistory {
                AssistantHistoryPanel(isOpen: $showHistory)
                    .padding(12)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85), value: showHistory)
    }

    private var historyButton: some View {
        Button { showHistory.toggle() } label: {
            Label("History", systemImage: "clock.arrow.circlepath")
                .font(.appFont(size: 14, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .borderGlowButton(accent: accent, isProminent: false)
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
        .accessibilityLabel(showHistory ? "Close conversation history" : "Open conversation history")
        .help("Your saved conversations, by day")
    }

    // MARK: Hero

    /// React Bits Strands, the aurora across the top of the page (the 3D orb stays on Home). It shows what the
    /// assistant is doing: calm when idle, lifted while it thinks, following the student's voice while it listens, and
    /// moving like speech while Locken talks.
    private var hero: some View { AssistantAurora(assistant: assistant, meter: assistant.meter) }

    private var status: some View {
        Group {
            switch assistant.phase {
            case .idle: Text(assistant.isConversationOn ? "One moment…" : "The microphone is off. Press the button to talk.")
            case .listening: Text(assistant.liveTranscript.isEmpty ? (assistant.messages.isEmpty ? "Listening. Say what you're working on." : "Listening…") : assistant.liveTranscript)
            case .thinking: Text("Thinking…")
            case .speaking: Text(assistant.messages.last?.text ?? "")
            }
        }
        .font(.appFont(size: 15, weight: .semibold))
        .foregroundColor(.white.opacity(0.85))
        .multilineTextAlignment(.center)
        .frame(maxWidth: 480, minHeight: 40)
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: Main action

    /// The one main button: pause or resume hands-free listening, or cut Locken off while it talks.
    private var micButton: some View {
        Button(action: pressMic) {
            Label(micTitle, systemImage: micIcon)
                .font(.appFont(size: 14, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 26)
                .padding(.vertical, 11)
            .borderGlowButton(accent: accent, isProminent: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(micTitle)
        .accessibilityValue(assistant.phase == .listening ? "Listening" : "")
        .help(assistant.holdKey == .off ? "" : "Or press and hold \(assistant.holdKey.hint)")
        .overlay(alignment: .bottom) {
            if assistant.holdKey != .off {
                Text("or \(assistant.phase == .speaking || assistant.phase == .thinking ? "press" : "hold") \(assistant.holdKey.hint)")
                    .font(.appFont(size: 11))
                    .foregroundColor(.white.opacity(0.55))
                    .fixedSize()
                    .offset(y: 24)
            }
        }
        .padding(.bottom, 18)
    }

    private func pressMic() {
        if assistant.phase == .speaking || assistant.phase == .thinking { assistant.interrupt() }
        else if assistant.isConversationOn { assistant.stopConversation() }
        else { assistant.startConversation() }
    }

    // MARK: Escape

    /// Escape stops Locken while it thinks or talks (a local monitor: only while this tab is open and Locken is in front).
    /// The hotkey itself is watched app-wide by `VoiceAssistant.startHotkey`.
    private func installEscapeInterrupt() {
        guard optionMonitor == nil else { return }
        optionMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53, assistant.phase == .speaking || assistant.phase == .thinking else { return event }
            assistant.trace("Escape pressed")
            assistant.interrupt()
            return nil
        }
    }

    private func removeEscapeInterrupt() {
        if let optionMonitor { NSEvent.removeMonitor(optionMonitor) }
        optionMonitor = nil
    }

    private var micTitle: String {
        if assistant.phase == .speaking { return "Interrupt" }
        if assistant.phase == .thinking { return "Stop" }
        return assistant.isConversationOn ? "Pause Listening" : "Start Listening"
    }

    private var micIcon: String {
        if assistant.phase == .speaking { return "hand.raised.fill" }
        if assistant.phase == .thinking { return "stop.fill" }
        return assistant.isConversationOn ? "mic.slash.fill" : "mic.fill"
    }

    private func proposalCard(_ proposal: VoiceAssistant.Proposal) -> some View {
        VStack(spacing: 14) {
            Text(proposalText(proposal))
                .font(.appFont(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            if assistant.isConversationOn {
                Text("Say yes or no, or click.")
                    .font(.appFont(size: 11))
                    .foregroundColor(.white.opacity(0.6))
            }
            HStack(spacing: 18) {
                Button("Not now") { assistant.proposal = nil }
                    .buttonStyle(.plain)
                    .quietAction()
                Button { assistant.confirmProposal(reduceMotion: reduceMotion) } label: {
                    Text(proposalButton(proposal))
                        .font(.appFont(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .borderGlowButton(accent: accent, isProminent: true)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: 460)
        .luxuryObsidianCard()
    }

    private func proposalText(_ proposal: VoiceAssistant.Proposal) -> String {
        switch proposal {
        case .startSession(let goal, let minutes):
            return "Start a \(minutes)-minute session on \(goal)?"
        case .addEvent(let title, let start, let minutes):
            return "Add \(title) to your calendar, \(start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())) for \(minutes) minutes?"
        case .completeStep(_, let text):
            return "Mark the step “\(text)” done?"
        case .checkOffAssignment(_, let title):
            return "Mark “\(title)” done? Only in Locken: nothing is sent to Canvas."
        case .addReminder(let title, let due):
            let when = due.map { " for \($0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))" } ?? ""
            return "Add the reminder “\(title)”\(when)?"
        case .completeHabit(_, let name):
            return "Tick off “\(name)” for today?"
        case .completeReminder(_, let title):
            return "Mark the reminder “\(title)” done?"
        case .moveReminder(_, let title, let due):
            return "Move the reminder “\(title)” to \(due.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))?"
        case .addNote(let title, _):
            return title.isEmpty ? "Save this as a note?" : "Save a note called “\(title)”?"
        case .openPage(_, let name):
            return "Open \(name)?"
        case .music(let command):
            switch command {
            case .playPause: return "Play or pause your music?"
            case .next: return "Skip to the next song?"
            case .previous: return "Go back to the last song?"
            }
        case .pauseSession:
            return "Pause your focus session? You'll still get the short wait first."
        case .resumeSession:
            return "Resume your focus session?"
        }
    }

    private func proposalButton(_ proposal: VoiceAssistant.Proposal) -> String {
        switch proposal {
        case .startSession: return "Start Session"
        case .addEvent: return "Add to Calendar"
        case .completeStep, .checkOffAssignment, .completeHabit, .completeReminder: return "Mark Done"
        case .addReminder: return "Add Reminder"
        case .moveReminder: return "Move Reminder"
        case .addNote: return "Save Note"
        case .openPage: return "Open"
        case .music: return "Do It"
        case .pauseSession: return "Pause"
        case .resumeSession: return "Resume"
        }
    }

    // MARK: Typing and history

    private var typeField: some View {
        TextField("Or type here and press Return", text: $typed)
            .textFieldStyle(.plain)
            .font(.appFont(size: 13))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
            .innerObsidianCard()
            .frame(maxWidth: 460)
            // Room below the Talk button so its glow doesn't spill onto the field.
            .padding(.top, 16)
            .onSubmit {
                assistant.send(typed)
                typed = ""
            }
            .disabled(assistant.phase == .thinking)
    }

    @ViewBuilder private var conversation: some View {
        if !assistant.messages.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(assistant.messages) { message in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(message.role == .student ? "You" : "Locken")
                            .font(.appFont(size: 11, weight: .bold))
                            .foregroundColor(message.role == .student ? .white.opacity(0.55) : accent)
                        Text(message.text)
                            .font(.appFont(size: 13))
                            .foregroundColor(.white.opacity(0.85))
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("New chat") { assistant.reset() }
                    .buttonStyle(.plain)
                    .quietAction()
            }
            .padding(Spacing.l)
            .luxuryObsidianCard()
        }
    }

    // MARK: Options

    private var options: some View {
        VStack(alignment: .leading, spacing: 14) {
            if state.appleCalendarStatus == .connected {
                Toggle(isOn: $assistant.mayAddCalendarEvents) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Let the assistant add calendar events")
                            .font(.appFont(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        Text("It asks before adding each one. Google calendars added to the Mac's Calendar app work too.")
                            .font(.appFont(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .toggleStyle(GlassSwitchToggleStyle(tint: accent))
            } else {
                Text("Connect Apple Calendar in Settings to let the assistant read your week and add events.")
                    .font(.appFont(size: 11))
                    .foregroundColor(.white.opacity(0.6))
            }

            Divider().overlay(Color.white.opacity(0.08))
            voiceRow
        }
        .padding(Spacing.l)
        .luxuryObsidianCard()
    }

    @ViewBuilder private var voiceRow: some View {
        switch assistant.voiceState {
        case .ready:
            Text("Locken's voice runs on this Mac. What you say is turned into text on this Mac too; only that text goes to your AI provider.")
                .font(.appFont(size: 11))
                .foregroundColor(.white.opacity(0.6))
        case .downloading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Getting Locken's voice ready (\(VoiceAssistant.voiceDownloadSize))…")
                    .font(.appFont(size: 11))
                    .foregroundColor(.white.opacity(0.6))
            }
        case .notDownloaded, .failed:
            VStack(alignment: .leading, spacing: 6) {
                Text(failure ?? "Locken's natural voice is a one-time \(VoiceAssistant.voiceDownloadSize) download from GitHub (the open-source Kokoro project). Until then, the Mac's built-in voice speaks.")
                    .font(.appFont(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                Button("Download voice") { assistant.downloadVoice() }
                    .buttonStyle(.plain)
                    .quietAction()
            }
        }
    }

    private var failure: String? {
        if case .failed(let message) = assistant.voiceState { return message }
        return nil
    }

    private func notice(_ text: String, action: String, perform: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Text(text)
                .font(.appFont(size: 13))
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            Button(action, action: perform)
                .buttonStyle(.plain)
                .quietAction()
        }
        .padding(Spacing.l)
        .frame(maxWidth: 460)
        .luxuryObsidianCard()
    }
}

/// Its own view so the microphone level, which changes about 30 times a second, redraws only this and not the whole tab.
private struct AssistantAurora: View {
    @ObservedObject var assistant: VoiceAssistant
    @ObservedObject var meter: MicLevelMeter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// What the page needs to know (see `strands-entry.jsx`): `speaking` or a `level`, nothing when idle.
    private var props: [String: String] {
        switch assistant.phase {
        case .idle: return [:]
        case .listening: return ["level": String(format: "%.2f", (Double(meter.level) * 20).rounded() / 20)]
        case .thinking: return ["level": "0.45"]
        case .speaking: return ["speaking": "1"]
        }
    }

    var body: some View {
        ReactBitsWebView(page: .strands, props: props)
            .accessibilityHidden(true)
            .frame(maxWidth: .infinity)
            .frame(height: 320)
            // Brighter whenever it listens, thinks or talks, so the student can see it's live.
            .opacity(assistant.phase == .idle ? 0.55 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: assistant.phase)
    }
}
