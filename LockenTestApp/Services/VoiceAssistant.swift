//
//  VoiceAssistant.swift
//  LockenTestApp
//
//  The talking assistant on the Assistant tab. It listens with Apple's on-device speech recognition (the
//  microphone audio never leaves the Mac), thinks with the student's own Claude or Gemini key through
//  AITaskFormatter (same 18+ check and personal-info scrubbing as every AI feature), and speaks with Kokoro,
//  an open-source voice that runs on the Mac. Until Kokoro's voice files are downloaded, or if it fails,
//  the Mac's built-in voice speaks instead.
//
//  The assistant only proposes actions. Starting a session or adding a calendar event always waits for the
//  student to press a button, and calendar events need the "add to my calendar" switch to be on.
//

import AVFoundation
import CryptoKit
import Foundation
import KokoroCoreML
import os
import Speech
import SwiftUI

/// Live microphone loudness (0...1) for the listening wave on the Assistant button. It is its own object so only
/// the wave redraws as it changes, not the whole Assistant tab.
@MainActor
final class MicLevelMeter: ObservableObject {
    @Published private(set) var level: Float = 0
    private var lastUpdate = Date.distantPast

    /// Rises fast, falls slowly, and updates at most about 30 times a second.
    func push(_ raw: Float) {
        let now = Date()
        guard now.timeIntervalSince(lastUpdate) >= 1.0 / 30 else { return }
        lastUpdate = now
        level = max(raw, level * 0.8)
    }

    func reset() { level = 0 }

    /// Loudness of one microphone buffer, with about -50 dB (a quiet room) mapped to 0 and -10 dB (loud speech) to 1.
    /// Runs on the audio thread, so it reads nothing but the buffer.
    nonisolated static func loudness(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += samples[i] * samples[i] }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        let decibels = 20 * log10(max(rms, 0.000_01))
        return min(max((decibels + 50) / 40, 0), 1)
    }
}

/// The hold-key rules as a plain value, so they can be checked without pressing a key. Every tick it is told whether the
/// key is down and alone, how long ago the last key press or click was, and whether Locken is busy, and says what to do.
struct HotkeyMachine {
    enum Event: Equatable {
        /// A fresh press while Locken thinks or talks: stop it.
        case pressedWhileBusy
        /// Held alone long enough: start listening.
        case held
        /// Let go, after any press.
        case released
    }

    static let holdSeconds = 0.3
    private var pressedAt: TimeInterval?
    private var settled = false

    mutating func tick(down: Bool, alone: Bool, idleSeconds: TimeInterval, busy: Bool, now: TimeInterval) -> Event? {
        guard down else {
            defer { pressedAt = nil }
            return pressedAt == nil ? nil : .released
        }
        guard let start = pressedAt else {
            pressedAt = now
            // Only a fresh press interrupts; a key still held from the press that started the turn never counts.
            settled = busy
            return busy ? .pressedWhileBusy : nil
        }
        guard !settled else { return nil }
        let held = now - start
        // Another modifier, a key press or a click while it's down means a shortcut, not a hold.
        if !alone || idleSeconds < held - 0.03 {
            settled = true
            return nil
        }
        if held >= Self.holdSeconds {
            settled = true
            return .held
        }
        return nil
    }
}

@MainActor
final class VoiceAssistant: ObservableObject {
    static let shared = VoiceAssistant()

    enum Phase: Equatable { case idle, listening, thinking, speaking }

    struct Message: Identifiable, Equatable {
        enum Role { case student, assistant }
        let id: UUID
        let role: Role
        let text: String
        init(id: UUID = UUID(), role: Role, text: String) { (self.id, self.role, self.text) = (id, role, text) }
    }

    /// Something the assistant suggested doing. Nothing happens until the student confirms it.
    enum Proposal: Equatable {
        case startSession(goal: String, minutes: Int)
        case addEvent(title: String, start: Date, minutes: Int)
        case completeStep(id: UUID, text: String)
        case checkOffAssignment(id: String, title: String)
        case addReminder(title: String, due: Date?)
        case completeHabit(id: UUID, name: String)
        case completeReminder(id: String, title: String)
        case moveReminder(id: String, title: String, due: Date)
        case addNote(title: String, body: String)
        case openPage(tab: String, name: String)
        case music(MusicCommand)
        /// Both go through commitment mode, like the pause and resume buttons.
        case pauseSession
        case resumeSession
    }

    enum MusicCommand: String, Equatable { case playPause = "play_pause", next, previous }

    /// The pages the Assistant can open, by the name the model uses.
    nonisolated static let openablePages: [String: (tab: String, name: String)] = [
        "home": ("dashboard", "Home"), "focus": ("focus", "Focus"), "assistant": ("assistant", "Assistant"), "calendar": ("calendar", "Calendar"),
        "habits": ("analytics", "Habit Tracker"), "analytics": ("usage", "Analytics"), "notes": ("artifacts", "Notes & Reminders"), "settings": ("settings", "Settings"),
    ]

    enum VoiceState: Equatable { case notDownloaded, downloading, ready, failed(String) }

    @Published private(set) var phase: Phase = .idle {
        didSet {
            trace("phase \(oldValue) -> \(phase)")
            if phase != .listening { meter.reset() }
            // Other media is turned down while Locken talks, and put back when it stops.
            if phase == .speaking, oldValue != .speaking {
                if lowersOtherMedia { NowPlayingService.shared.duck() }
            } else if oldValue == .speaking, phase != .speaking {
                NowPlayingService.shared.unduck()
            }
            if phase == .idle { resumeListeningSoon(afterSpeech: oldValue == .speaking) }
        }
    }
    /// How loud the microphone is while Locken listens; drives the wave on the main button.
    let meter = MicLevelMeter()
    /// Hands-free mode: while on, Locken listens again by itself after every reply.
    @Published private(set) var isConversationOn = false
    @Published private(set) var messages: [Message] = []
    /// The saved conversation on screen (see `AssistantHistoryStore`); nil until the first message of a new chat.
    @Published private(set) var currentConversationID: UUID?
    @Published private(set) var liveTranscript = ""
    @Published var proposal: Proposal?
    @Published var errorText: String?
    @Published private(set) var voiceState: VoiceState = .notDownloaded

    /// Off until the student turns it on: the assistant may then suggest calendar events (each one still asks first).
    /// Spotify, Music and browser media get quieter while Locken talks (Settings › Other media).
    @Published var lowersOtherMedia: Bool {
        didSet { UserDefaults.standard.set(lowersOtherMedia, forKey: Self.lowersMediaKey) }
    }
    private static let lowersMediaKey = "assistant.lowersOtherMedia"

    @Published var mayAddCalendarEvents: Bool {
        didSet { UserDefaults.standard.set(mayAddCalendarEvents, forKey: Self.calendarKey) }
    }

    private static let calendarKey = "assistant.mayAddCalendarEvents"

    /// The key to press and hold for the Assistant tab's main button (chosen in Settings).
    enum HoldKey: String, CaseIterable {
        case leftOption = "Left Option", rightOption = "Right Option", leftControl = "Left Control",
             rightCommand = "Right Command", fn = "fn", off = "Off"

        var keyCode: UInt16? {
            switch self {
            case .leftOption: return 58
            case .rightOption: return 61
            case .leftControl: return 59
            case .rightCommand: return 54
            case .fn: return 63
            case .off: return nil
            }
        }

        /// The key's own bit in the modifier state (NX_DEVICE*KEYMASK), so left and right keys can be told apart.
        var deviceBit: UInt {
            switch self {
            case .leftOption: return 0x20
            case .rightOption: return 0x40
            case .leftControl: return 0x01
            case .rightCommand: return 0x10
            case .fn: return 0x800000
            case .off: return 0
            }
        }

        var flag: NSEvent.ModifierFlags {
            switch self {
            case .leftOption, .rightOption: return .option
            case .leftControl: return .control
            case .rightCommand: return .command
            case .fn, .off: return .function
            }
        }

        /// For the hint under the button, e.g. "left ⌥ Option".
        var hint: String {
            switch self {
            case .leftOption: return "left ⌥ Option"
            case .rightOption: return "right ⌥ Option"
            case .leftControl: return "left ⌃ Control"
            case .rightCommand: return "right ⌘ Command"
            case .fn: return "fn"
            case .off: return ""
            }
        }
    }

    @Published var holdKey: HoldKey {
        didSet { UserDefaults.standard.set(holdKey.rawValue, forKey: Self.holdKeyKey) }
    }

    private static let holdKeyKey = "assistant.holdKey"

    // Listening
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTask: Task<Void, Never>?

    // Speaking
    private var kokoro: KokoroEngine?
    private let playerEngine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var speakTask: Task<Void, Never>?
    /// The request that's thinking, kept so stopping or interrupting can cancel it.
    private var thinkTask: Task<Void, Never>?
    private let fallbackVoice = AVSpeechSynthesizer()
    private var fallbackDelegate: FallbackDelegate?

    private init() {
        mayAddCalendarEvents = UserDefaults.standard.bool(forKey: Self.calendarKey)
        lowersOtherMedia = UserDefaults.standard.object(forKey: Self.lowersMediaKey) as? Bool ?? true
        holdKey = UserDefaults.standard.string(forKey: Self.holdKeyKey).flatMap(HoldKey.init(rawValue:)) ?? .leftOption
        playerEngine.attach(player)
        playerEngine.connect(player, to: playerEngine.mainMixerNode, format: KokoroEngine.audioFormat)
        if Self.voiceFilesPresent() { voiceState = .ready }
        #if DEBUG
        Self.selfCheck()
        #endif
    }

    /// Starts a blank chat (the saved one stays in History), and clears the screen when another account signs in.
    func reset() {
        stopAll()
        messages = []
        currentConversationID = nil
        proposal = nil
        errorText = nil
    }

    /// Shows a saved conversation and carries on in it: new messages are saved to that same conversation.
    func open(_ conversation: SavedConversation) {
        stopAll()
        messages = conversation.messages.map { Message(id: $0.id, role: $0.isStudent ? .student : .assistant, text: $0.text) }
        currentConversationID = conversation.id
        proposal = nil
        errorText = nil
    }

    /// Adds a message to the screen and saves it, starting a new saved conversation if this is the first one.
    private func record(_ role: Message.Role, _ text: String) {
        let message = Message(role: role, text: text)
        messages.append(message)
        let conversation = currentConversationID ?? UUID()
        currentConversationID = conversation
        AssistantHistoryStore.shared.record(StoredMessage(id: message.id, isStudent: role == .student, text: text, date: Date()), in: conversation)
    }

    // MARK: - Listening

    /// Starts hands-free listening, for the main button and the hotkey. `oneQuestion` (the hotkey held from another app)
    /// listens for one question, answers it and stops, so the microphone is never left on in the background.
    func startConversation(oneQuestion: Bool = false) {
        isConversationOn = true
        stopsAfterReply = oneQuestion
        errorText = nil
        // While the student talks, get the first answer ready: this key's model list, and the voice loaded into memory.
        AITaskFormatter.shared.prepare()
        warmUpVoice()
        if phase == .idle { Task { await startListening() } }
    }

    /// Stops listening and talking, for the pause button and when the student leaves the tab.
    func stopConversation() {
        isConversationOn = false
        stopsAfterReply = false
        pushToTalkActive = false
        stopAll()
    }

    /// While Locken is thinking or talking: stop it at once (a pending answer is thrown away) and listen again.
    func interrupt() {
        trace("interrupt() while \(phase)")
        cancelThinking()
        stopSpeaking()
    }

    /// Debug builds only: phase changes and interrupts, no text the student said. Read with
    /// `log show --predicate 'process == "LockenTestApp"' --info` to see why an interrupt did or didn't happen.
    func trace(_ message: String) {
        #if DEBUG
        Self.logger.notice("\(message, privacy: .public)")
        #endif
    }

    private static let logger = Logger(subsystem: "LockenTestApp", category: "assistant")

    // MARK: Hotkey (works in any app)

    private var stopsAfterReply = false
    /// Push to talk: the hotkey listens only while it's held and answers when it's let go.
    private var pushToTalkActive = false
    private var pushToTalkHeld = false
    private var hotkeyTimer: Timer?
    private var resignObserver: NSObjectProtocol?
    private var hotkey = HotkeyMachine()

    /// Every modifier's own bit plus fn; what's left after taking out the hold key's bit is "another key is down".
    private static let modifierBits: UInt = 0x01 | 0x02 | 0x04 | 0x08 | 0x10 | 0x20 | 0x40 | 0x2000 | 0x800000

    /// Starts watching the hold key (signed in, AI key saved, hotkey not Off). It reads which modifier keys are down, about
    /// 30 times a second, wherever the student is: that needs no permission and records no keystrokes. Holding the key for
    /// 0.3 s starts listening (push to talk: it stops listening and answers when the key is let go); pressing it while
    /// Locken thinks or talks stops it at once.
    func startHotkey() {
        guard hotkeyTimer == nil else { return }
        let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.hotkeyTick() }
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        hotkeyTimer = timer
        // Hands-free listening started inside Locken ends when the student leaves it; the hotkey starts it again from anywhere.
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stopConversation() }
        }
    }

    func stopHotkey() {
        hotkeyTimer?.invalidate()
        hotkeyTimer = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        hotkey = HotkeyMachine()
    }

    /// Whether the hold key is down, and whether it's the only modifier down.
    private func holdKeyState() -> (down: Bool, alone: Bool) {
        guard holdKey != .off else { return (false, false) }
        let flags = NSEvent.modifierFlags
        let raw = flags.rawValue
        let sideBits = Self.modifierBits & ~0x800000
        if holdKey == .fn || raw & sideBits == 0 {
            // No left/right information (or the fn key): go by the modifier kind alone.
            let others = flags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .capsLock])
            return (flags.contains(holdKey.flag), others == holdKey.flag)
        }
        return (raw & holdKey.deviceBit != 0, raw & Self.modifierBits == holdKey.deviceBit)
    }

    private func hotkeyTick() {
        guard holdKey != .off, AITaskFormatter.shared.isConfigured, AuthManager.shared.user != nil else {
            hotkey = HotkeyMachine()
            return
        }
        let (down, alone) = holdKeyState()
        // How long ago the last key press or click was: one of those while the key is down makes it a shortcut.
        // Only asked while the key is down: the state machine ignores it otherwise (this runs 30 times a second, all day).
        let idle: TimeInterval = down
            ? [CGEventType.keyDown, .leftMouseDown, .rightMouseDown]
                .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? .infinity
            : .infinity
        let busy = phase == .speaking || phase == .thinking
        switch hotkey.tick(down: down, alone: alone, idleSeconds: idle, busy: busy, now: ProcessInfo.processInfo.systemUptime) {
        case .pressedWhileBusy:
            trace("hotkey press: interrupt")
            interrupt()
        case .held:
            startFromHotkey()
        case .released:
            endPushToTalk()
        case nil:
            break
        }
    }

    private func startFromHotkey() {
        guard phase != .thinking else { return }
        trace("hotkey hold, app active \(NSApp.isActive)")
        if phase == .speaking {
            interrupt()
        } else if isConversationOn && !stopsAfterReply {
            // Hands-free listening started with the button: the hotkey pauses it, like the button.
            stopConversation()
        } else {
            // Push to talk, in any app: listens while the key is held, answers once it's let go, and doesn't keep
            // listening after that.
            pushToTalkActive = true
            pushToTalkHeld = true
            startConversation(oneQuestion: true)
            // The student may not see the window, so a short sound says the microphone is live.
            if !NSApp.isActive { NSSound(named: NSSound.Name("Tink"))?.play() }
        }
    }

    /// The hotkey was let go: stop listening and send what was heard. If listening hadn't started yet, it never will.
    private func endPushToTalk() {
        pushToTalkHeld = false
        guard pushToTalkActive else { return }
        pushToTalkActive = false
        if phase == .listening { finishListening() } else if phase == .idle { stopConversation() }
    }

    private func cancelThinking() {
        thinkTask?.cancel()
        thinkTask = nil
        if phase == .thinking { phase = .idle }
    }

    /// The short wait after Locken talks keeps the end of its own voice out of the microphone. After a quiet cycle
    /// (nothing was said) there's no voice to wait for, so listening restarts almost at once and no words are lost.
    private func resumeListeningSoon(afterSpeech: Bool) {
        guard isConversationOn else { return }
        // One question from another app: stop after the reply (or an error) unless a confirm card still needs a yes or no.
        if stopsAfterReply, proposal == nil, afterSpeech || errorText != nil { stopConversation(); return }
        guard errorText == nil else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(afterSpeech ? 350 : 60))
            guard isConversationOn, errorText == nil, phase == .idle else { return }
            // Nothing was said in the quiet cycle: for one question, that's the end.
            if stopsAfterReply, !afterSpeech, proposal == nil { stopConversation(); return }
            await startListening()
        }
    }

    /// Ends the turn after the student stops talking for a moment.
    private func scheduleEndOfTurn(after text: String) {
        silenceTask?.cancel()
        silenceTask = Task {
            try? await Task.sleep(for: .milliseconds(1400))
            guard !Task.isCancelled, phase == .listening, liveTranscript == text else { return }
            finishListening()
        }
    }

    private func startListening() async {
        guard phase == .idle else { return }
        errorText = nil
        guard await Self.microphoneAllowed() else {
            errorText = "Locken needs the microphone to hear you. Turn it on in System Settings › Privacy & Security › Microphone, or type below."
            return
        }
        guard await Self.speechRecognitionAllowed() else {
            errorText = "Locken needs Speech Recognition to understand you. Turn it on in System Settings › Privacy & Security › Speech Recognition, or type below."
            return
        }
        // Stopped while the permissions were checked (the hotkey was let go at once): don't start.
        guard isConversationOn, phase == .idle else { return }
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            errorText = "Speech recognition on this Mac isn't ready. Turn on Dictation in System Settings › Keyboard, or type below."
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        // Keeps the audio on the Mac; Apple's servers are never used.
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        recognitionRequest = request
        liveTranscript = ""

        let input = audioEngine.inputNode
        guard input.outputFormat(forBus: 0).channelCount > 0 else {
            errorText = "No microphone found. Connect one, or type below."
            return
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            request.append(buffer)
            let level = MicLevelMeter.loudness(of: buffer)
            Task { @MainActor in
                // A buffer that arrives just after listening ends must not light the wave up again.
                if self?.phase == .listening { self?.meter.push(level) }
            }
        }
        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            input.removeTap(onBus: 0)
            errorText = "The microphone couldn't start. Check that one is connected, or type below."
            return
        }
        phase = .listening

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            Task { @MainActor in
                guard let self else { return }
                if let text, text != self.liveTranscript {
                    self.liveTranscript = text
                    self.scheduleEndOfTurn(after: text)
                }
                if isFinal || error != nil { self.endRecognition(deliver: true) }
            }
        }
    }

    private func finishListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        // The final result arrives through the recognition callback; if nothing was heard, end here.
        if liveTranscript.trimmingCharacters(in: .whitespaces).isEmpty { endRecognition(deliver: false); return }
        // The microphone is already off, so a final result that never arrives would leave Locken deaf on "Listening…".
        // After two seconds, go with what was heard.
        let request = recognitionRequest
        Task {
            try? await Task.sleep(for: .seconds(2))
            if phase == .listening, recognitionRequest === request { endRecognition(deliver: true) }
        }
    }

    private func endRecognition(deliver: Bool) {
        guard phase == .listening else { return }
        silenceTask?.cancel()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        let heard = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        liveTranscript = ""
        guard deliver, !heard.isEmpty else { phase = .idle; return }
        // A spoken "yes" or "no" answers a pending suggestion without touching the screen.
        if proposal != nil, let answer = Self.confirmation(in: heard) {
            phase = .idle
            if answer { confirmProposal(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) } else { proposal = nil }
            return
        }
        phase = .idle
        send(heard)
    }

    // MARK: - Thinking

    /// Sends what the student said (or typed) and speaks the answer.
    func send(_ rawText: String) {
        let text = String(rawText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000))
        guard !text.isEmpty, phase != .thinking else { return }
        // Typing while Locken listens: drop the half-heard speech and use the typed text.
        if phase == .listening { endRecognition(deliver: false) }
        stopSpeaking()
        errorText = nil
        proposal = nil
        record(.student, text)
        warmUpVoice() // while the answer is on its way
        phase = .thinking

        let history = messages.suffix(12).map { ($0.role == .student ? "Student" : "Locken") + ": " + $0.text }
        // The steps and assignments are numbered in the context, so the model's "number" is looked up in these same lists.
        let steps = Array(TestAppStateManager.shared.milestones.prefix(12))
        let assignments = Array(CanvasAPIManager.shared.assignments.prefix(10))
        let habits = habitsToTick()
        let reminders = Array(TestAppStateManager.shared.openReminders.prefix(12))
        let context = buildContext(steps: steps, assignments: assignments, habits: habits, reminders: reminders)
        let state = TestAppStateManager.shared
        let abilities = AITaskFormatter.AssistantAbilities(
            canAddEvents: mayAddCalendarEvents && state.appleCalendarStatus == .connected,
            canAddReminders: state.hasReminderAccess,
            canEditReminders: state.hasReminderAccess && !reminders.isEmpty,
            // Spotify and Music only: a browser tab can be paused but not resumed or skipped from outside.
            canControlMusic: NowPlayingService.shared.track.map { !$0.player.isBrowser } ?? false,
            canPause: state.isTimerActive,
            canResume: !state.isTimerActive && state.isGoalDefined && state.timerSecondsRemaining < state.timerTotalSeconds
        )
        thinkTask = Task {
            do {
                let raw = try await AITaskFormatter.shared.assistantReply(history: history, context: context, abilities: abilities)
                // Stopped or interrupted while thinking: the answer is dropped, never spoken.
                guard !Task.isCancelled, phase == .thinking else { return }
                let reply = Self.parseReply(raw, now: Date(), steps: steps, assignments: assignments, habits: habits, reminders: reminders,
                                            canControlMusic: abilities.canControlMusic, canPause: abilities.canPause, canResume: abilities.canResume)
                record(.assistant, reply.say)
                switch reply.proposal {
                case .addEvent? where !abilities.canAddEvents, .addReminder? where !abilities.canAddReminders: proposal = nil
                default: proposal = reply.proposal
                }
                speak(reply.say)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, phase == .thinking else { return }
                phase = .idle
                errorText = error.localizedDescription
            }
        }
    }

    /// What the assistant knows about the student's day. Goes through AITaskFormatter's scrubbing like all AI text.
    /// Today's habits the Assistant may tick off: due today, not done, and not ones that tick themselves.
    private func habitsToTick() -> [Habit] {
        let habits = HabitStore.shared
        let now = Date()
        return Array(habits.activeHabits.filter { HabitMath.isScheduled($0, on: now) && !habits.isDone($0, on: now) && !habits.isAutoTracked($0) }.prefix(12))
    }

    /// "2h 5m", "45m", "0m".
    nonisolated static func duration(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    /// The numbers behind "how much did I focus?" questions: focus time and screen time as totals, never app or website names.
    private func statsLines(now: Date) -> [String] {
        let state = TestAppStateManager.shared
        let calendar = Calendar.current
        var lines: [String] = []

        let monday = HabitMath.weekStart(now)
        let weekDays = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }.filter { $0 <= now }
        func focus(_ date: Date) -> Int { state.stats.focusSecondsByDay[ScreenUsageTracker.dayKey(date)] ?? 0 }
        func sessions(_ date: Date) -> Int { state.stats.sessionsByDay[ScreenUsageTracker.dayKey(date)] ?? 0 }
        // Consecutive days with focus time, counting back from today (or from yesterday while today is still empty).
        var streak = 0
        var cursor = focus(now) > 0 ? now : calendar.date(byAdding: .day, value: -1, to: now)!
        while focus(cursor) > 0, streak < 365 {
            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        lines.append("Focus time: today \(Self.duration(Double(focus(now)))) in \(sessions(now)) sessions; this week \(Self.duration(Double(weekDays.map(focus).reduce(0, +)))) in \(weekDays.map(sessions).reduce(0, +)) sessions; focus streak \(streak) days.")

        let usage = ScreenUsageTracker.shared.days
        if let today = usage[ScreenUsageTracker.dayKey(now)], today.total > 0 {
            let parts = ScreenUsageTracker.Category.allCases.compactMap { category -> String? in
                let seconds = today.seconds(in: category)
                return seconds >= 60 ? "\(category.title) \(Self.duration(seconds))" : nil
            }
            lines.append("Screen time on this Mac today: \(Self.duration(today.total))" + (parts.isEmpty ? "." : " (" + parts.joined(separator: ", ") + ")."))
        }
        let weekScreen = weekDays.map { usage[ScreenUsageTracker.dayKey($0)]?.total ?? 0 }.reduce(0, +)
        if weekScreen > 0 { lines.append("Screen time this week: \(Self.duration(weekScreen)).") }
        return lines
    }

    private func buildContext(steps: [TestMilestone], assignments: [CanvasAssignment], habits tickable: [Habit], reminders: [TestAppStateManager.AppleReminder]) -> String {
        let state = TestAppStateManager.shared
        let habits = HabitStore.shared
        let now = Date()
        let day = DateFormatter()
        day.dateFormat = "EEE MMM d, h:mm a"
        var lines = ["Now: \(day.string(from: now))"]

        if state.isTimerActive {
            lines.append("In a focus session now: \"\(state.focusGoal)\", \(max(1, state.timerSecondsRemaining / 60)) minutes left.")
        } else {
            lines.append("Not in a focus session.")
        }

        let today = habits.activeHabits.filter { HabitMath.isScheduled($0, on: now) }
        if !today.isEmpty {
            lines.append("Today's habits: " + today.prefix(12).map { habit in
                "\(habit.name) (\(habits.isDone(habit, on: now) ? "done" : "not done"), streak \(habits.currentStreak(habit)) days)"
            }.joined(separator: ", "))
        }
        if !tickable.isEmpty {
            lines.append("Habits you can tick off:")
            for (index, habit) in tickable.enumerated() { lines.append("\(index + 1). \(habit.name)") }
        }
        lines.append(contentsOf: statsLines(now: now))

        let assignments = CanvasAPIManager.shared.assignments
            .filter { ($0.dueDate ?? .distantPast) > now }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            .prefix(10)
        if !assignments.isEmpty {
            lines.append("Upcoming Canvas assignments:")
            for assignment in assignments {
                var line = "- \(assignment.title)"
                if !assignment.courseName.isEmpty { line += " (\(assignment.courseName))" }
                if let due = assignment.dueDate { line += ", due \(day.string(from: due))" }
                lines.append(line)
            }
        }

        if !steps.isEmpty {
            lines.append("Focus steps:")
            for (index, step) in steps.enumerated() { lines.append("\(index + 1). \(step.text)\(step.isDone ? " (done)" : "")") }
        }
        if !assignments.isEmpty {
            lines.append("Canvas assignments, not done yet:")
            for (index, assignment) in assignments.enumerated() {
                let due = assignment.dueDate.map { ", due \(day.string(from: $0))" } ?? ""
                lines.append("\(index + 1). \(assignment.title)\(assignment.courseName.isEmpty ? "" : " (\(assignment.courseName))")\(due)")
            }
        }

        if !reminders.isEmpty {
            lines.append("Open reminders:")
            for (index, reminder) in reminders.enumerated() {
                let due = reminder.due.map { ", due \(day.string(from: $0))" } ?? ""
                lines.append("\(index + 1). \(reminder.title)\(due)")
            }
        }

        if state.appleCalendarStatus == .connected {
            let events = state.upcomingEvents.prefix(15)
            lines.append(events.isEmpty ? "Calendar: nothing in the next 7 days." : "Calendar, next 7 days:")
            for event in events {
                lines.append("- \(event.title), \(event.isAllDay ? "all day " : "")\(day.string(from: event.start))")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Actions

    /// Runs the proposal the student confirmed.
    func confirmProposal(reduceMotion: Bool) {
        guard let proposal else { return }
        self.proposal = nil
        switch proposal {
        case .startSession(let goal, let minutes):
            stopConversation()
            TestAppStateManager.shared.startFocus(goal: goal, minutes: minutes, playIntro: !reduceMotion)
        case .addEvent(let title, let start, let minutes):
            guard mayAddCalendarEvents else { return }
            do {
                try TestAppStateManager.shared.addCalendarEvent(title: title, start: start, minutes: minutes)
                record(.assistant, "Added \(title) to your calendar.")
            } catch {
                errorText = "That event couldn't be added. Check that Locken can use your calendar in System Settings."
            }
        case .completeStep(let id, let text):
            // Only if it's still open: the student may have ticked it themselves while the card was showing.
            guard TestAppStateManager.shared.milestones.first(where: { $0.id == id })?.isDone == false else {
                record(.assistant, "That step was already done.")
                return
            }
            TestAppStateManager.shared.toggleMilestone(id: id)
            record(.assistant, "Marked “\(text)” done.")
        case .checkOffAssignment(let id, let title):
            guard let assignment = CanvasAPIManager.shared.assignments.first(where: { $0.id == id }) else {
                record(.assistant, "That assignment is already off your list.")
                return
            }
            CanvasAPIManager.shared.checkOff(assignment)
            record(.assistant, "Marked “\(title)” done.")
        case .addReminder(let title, let due):
            let state = TestAppStateManager.shared
            var draft = TestAppStateManager.ReminderDraft(listID: state.defaultReminderListID ?? "", title: title)
            if let due {
                draft.hasDate = true
                draft.hasTime = true
                draft.hasAlert = true
                draft.date = due
            }
            if state.saveReminder(draft) {
                record(.assistant, "Added the reminder “\(title)”.")
            } else {
                errorText = "That reminder couldn't be added. Check that Locken can use Reminders in System Settings."
            }
        case .completeHabit(let id, let name):
            let habits = HabitStore.shared
            // Only if it's still open: it may have been ticked, or archived, while the card was showing.
            guard let habit = habits.activeHabits.first(where: { $0.id == id }), !habits.isDone(habit, on: Date()), !habits.isAutoTracked(habit) else {
                record(.assistant, "“\(name)” is already done.")
                return
            }
            habits.toggle(habit, on: Date())
            record(.assistant, "Ticked off “\(name)” for today.")
        case .completeReminder(let id, let title):
            let state = TestAppStateManager.shared
            guard state.openReminders.contains(where: { $0.id == id }) else {
                record(.assistant, "That reminder is already done.")
                return
            }
            state.setReminderCompleted(id: id, true)
            record(.assistant, "Marked the reminder “\(title)” done.")
        case .moveReminder(let id, let title, let due):
            let state = TestAppStateManager.shared
            guard let reminder = state.openReminders.first(where: { $0.id == id }) else {
                record(.assistant, "That reminder is no longer open.")
                return
            }
            // Everything else about the reminder stays as it was; only its due date and time change.
            var draft = TestAppStateManager.ReminderDraft(listID: reminder.listID, title: reminder.title)
            draft.reminderID = reminder.id
            draft.notes = reminder.notes
            draft.priority = reminder.priority
            draft.repeats = reminder.repeats
            draft.url = reminder.url
            draft.hasDate = true
            draft.hasTime = true
            draft.hasAlert = reminder.hasAlert
            draft.date = due
            if state.saveReminder(draft) {
                record(.assistant, "Moved “\(title)” to \(due.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())).")
            } else {
                errorText = "That reminder couldn't be changed. Check that Locken can use Reminders in System Settings."
            }
        case .addNote(let title, let body):
            let state = TestAppStateManager.shared
            state.addNote()
            if let id = state.notes.first?.id { state.updateNote(id: id, title: title, body: body) }
            record(.assistant, title.isEmpty ? "Saved the note." : "Saved the note “\(title)”.")
        case .openPage(let tab, let name):
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { TestAppStateManager.shared.selectedTab = tab }
            record(.assistant, "Opened \(name).")
        case .music(let command):
            guard let track = NowPlayingService.shared.track, !track.player.isBrowser else {
                record(.assistant, "Nothing is playing in Spotify or Music right now.")
                return
            }
            switch command {
            case .playPause: NowPlayingService.shared.playPause()
            case .next: NowPlayingService.shared.nextTrack()
            case .previous: NowPlayingService.shared.previousTrack()
            }
        case .pauseSession:
            let state = TestAppStateManager.shared
            guard state.isTimerActive else {
                record(.assistant, "No session is running.")
                return
            }
            // Same path as the Pause button: commitment mode's short wait, then why you're pausing. The prompt is in the
            // app window, so bring it forward.
            state.toggleTimer()
            NSApplication.shared.activate(ignoringOtherApps: true)
            record(.assistant, "Finish the short wait in Locken to pause.")
        case .resumeSession:
            let state = TestAppStateManager.shared
            guard !state.isTimerActive, state.isGoalDefined, state.timerSecondsRemaining < state.timerTotalSeconds else {
                record(.assistant, "There's no paused session to resume.")
                return
            }
            state.toggleTimer()
            record(.assistant, "Back to it.")
        }
    }

    // MARK: - Speaking

    private func speak(_ text: String) {
        guard !text.isEmpty else { phase = .idle; return }
        phase = .speaking
        guard voiceState == .ready else {
            speakWithMacVoice(text)
            return
        }
        // The voice model loads off the main thread: loading it here froze the whole window for a second or more on the first
        // reply (a typed question never warmed it up) and again after it had been let go.
        speakTask = Task {
            guard let engine = await self.voiceEngine() else {
                if !Task.isCancelled { self.speakWithMacVoice(text) }
                return
            }
            if !Task.isCancelled { await self.play(text, with: engine) }
        }
    }

    private func play(_ text: String, with engine: KokoroEngine) async {
        do {
            if !playerEngine.isRunning { try playerEngine.start() }
            player.play()
            var pending = 0
            var finished = false
            func enqueue(_ buffer: AVAudioPCMBuffer) {
                pending += 1
                player.scheduleBuffer(buffer) { [weak self] in
                    Task { @MainActor in
                        pending -= 1
                        if finished, pending == 0, self?.phase == .speaking { self?.phase = .idle }
                    }
                }
            }
            // A sentence at a time: the model makes a whole chunk before it hands over any audio, so a long reply stayed silent
            // until all of it was ready. This way the first sentence starts as soon as it is made, and the next is made while it plays.
            for (index, sentence) in Self.sentences(in: text).enumerated() {
                if Task.isCancelled { break }
                if index > 0, let gap = Self.pause(seconds: 0.22) { enqueue(gap) }
                let stream = try engine.speak(sentence, voice: Self.voiceName)
                for await event in stream {
                    if Task.isCancelled { break }
                    guard case .audio(let buffer) = event else { continue }
                    enqueue(buffer)
                }
            }
            finished = true
            if pending == 0, phase == .speaking { phase = .idle }
        } catch {
            if phase == .speaking { speakWithMacVoice(text) }
        }
    }

    /// The reply split into sentences for speaking; one that is only a word or two ("Sure.") joins the next.
    nonisolated static func sentences(in text: String) -> [String] {
        var result: [String] = []
        var current = ""
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .bySentences) { piece, _, _, _ in
            guard let sentence = piece?.trimmingCharacters(in: .whitespacesAndNewlines), !sentence.isEmpty else { return }
            current += (current.isEmpty ? "" : " ") + sentence
            if current.count >= 24 {
                result.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            if let last = result.popLast() { result.append(last + " " + current) } else { result.append(current) }
        }
        return result.isEmpty ? [text] : result
    }

    /// A short silence between two spoken sentences.
    private static func pause(seconds: Double) -> AVAudioPCMBuffer? {
        let format = KokoroEngine.audioFormat
        let frames = AVAudioFrameCount(format.sampleRate * seconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        if let data = buffer.floatChannelData?[0] { data.update(repeating: 0, count: Int(frames)) }
        return buffer
    }

    private func speakWithMacVoice(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .max { $0.quality.rawValue < $1.quality.rawValue }
        let delegate = FallbackDelegate { [weak self] in
            Task { @MainActor in if self?.phase == .speaking { self?.phase = .idle } }
        }
        fallbackDelegate = delegate
        fallbackVoice.delegate = delegate
        fallbackVoice.speak(utterance)
    }

    func stopSpeaking() {
        speakTask?.cancel()
        speakTask = nil
        player.stop()
        // Stopping the engine as well guarantees no queued audio is still played.
        playerEngine.stop()
        fallbackVoice.stopSpeaking(at: .immediate)
        if phase == .speaking { phase = .idle }
    }

    func stopAll() {
        if phase == .listening { endRecognition(deliver: false) }
        cancelThinking()
        stopSpeaking()
    }

    private final class FallbackDelegate: NSObject, AVSpeechSynthesizerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { onFinish() }
        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { onFinish() }
    }

    // MARK: - Kokoro voice files

    /// Kokoro's voice: warm, clear American English.
    private static let voiceName = "af_heart"
    /// Pinned to one release and checked against its SHA-256, so a changed or swapped file is never used.
    private static let voiceFilesURL = URL(string: "https://github.com/Jud/kokoro-coreml/releases/download/models-2026-03-23/kokoro-models.tar.gz")!
    private static let voiceFilesSHA256 = "0d24bbf80526456bd8640f9f484cd1c333aee8a936e618ac44e619eafb79aec9"
    static let voiceDownloadSize = "103 MB"

    private static var voiceDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Locken/Voice/kokoro-2026-03-23", isDirectory: true)
    }

    /// The folder holding the voice files: the download folder itself, or the one folder inside it.
    private static func modelDirectory() -> URL? {
        let root = voiceDirectory
        if KokoroEngine.isDownloaded(at: root) { return root }
        let children = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return children.first { KokoroEngine.isDownloaded(at: $0) }
    }

    private static func voiceFilesPresent() -> Bool { modelDirectory() != nil }

    /// Loads the voice off the main thread, so the first reply doesn't freeze the window while the model loads.
    private func warmUpVoice() {
        guard kokoro == nil, !isWarmingVoice, voiceState == .ready, let directory = Self.modelDirectory() else { return }
        isWarmingVoice = true
        Task {
            let engine = await Task.detached(priority: .userInitiated) { try? KokoroEngine(modelDirectory: directory) }.value
            if kokoro == nil { kokoro = engine }
            isWarmingVoice = false
        }
    }
    private var isWarmingVoice = false

    /// The voice model, loaded in the background if it isn't in memory (waiting for a warm-up that's already running).
    private func voiceEngine() async -> KokoroEngine? {
        while isWarmingVoice, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(50)) }
        if let kokoro { return kokoro }
        guard let directory = Self.modelDirectory() else { voiceState = .notDownloaded; return nil }
        let engine = await Task.detached(priority: .userInitiated) { try? KokoroEngine(modelDirectory: directory) }.value
        if kokoro == nil { kokoro = engine }
        return kokoro
    }

    /// Starts loading the voice in the background (when the Assistant tab opens, or a question is asked). The model takes about
    /// ten seconds to load and warm up, so having it ready before the first reply is what makes Locken answer out loud at once.
    func prepareVoice() { warmUpVoice() }

    /// Downloads Locken's voice once (about 103 MB), checks its fingerprint, then unpacks it.
    func downloadVoice() {
        guard voiceState != .downloading else { return }
        voiceState = .downloading
        Task {
            do {
                let (file, response) = try await URLSession.shared.download(from: Self.voiceFilesURL)
                defer { try? FileManager.default.removeItem(at: file) }
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw VoiceDownloadError.server }
                guard try await Self.sha256(of: file) == Self.voiceFilesSHA256 else { throw VoiceDownloadError.mismatch }
                try await Self.unpack(file, into: Self.voiceDirectory)
                guard Self.voiceFilesPresent() else { throw VoiceDownloadError.mismatch }
                voiceState = .ready
            } catch VoiceDownloadError.mismatch {
                try? FileManager.default.removeItem(at: Self.voiceDirectory)
                voiceState = .failed("The voice download didn't check out, so it wasn't used. Try again later.")
            } catch {
                voiceState = .failed("The voice couldn't be downloaded. Check your internet connection and try again.")
            }
        }
    }

    private enum VoiceDownloadError: Error { case server, mismatch }

    nonisolated private static func sha256(of file: URL) async throws -> String {
        try await Task.detached {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            var hasher = SHA256()
            while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }.value
    }

    nonisolated private static func unpack(_ archive: URL, into directory: URL) async throws {
        try await Task.detached {
            try? FileManager.default.removeItem(at: directory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let tar = Process()
            tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            tar.arguments = ["-xzf", archive.path, "-C", directory.path]
            try tar.run()
            tar.waitUntilExit()
            guard tar.terminationStatus == 0 else { throw VoiceDownloadError.mismatch }
        }.value
    }

    // MARK: - Permissions

    private static func microphoneAllowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    private static func speechRecognitionAllowed() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
            }
        default: return false
        }
    }

    // MARK: - Reply parsing

    /// true for a short yes ("yes", "sure, do it"), false for a short no ("no", "not now"), nil for anything else.
    nonisolated static func confirmation(in heard: String) -> Bool? {
        let words = heard.lowercased().replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\u{2019}", with: "")
            .components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
        guard !words.isEmpty, words.count <= 5 else { return nil }
        let no: Set<String> = ["no", "nope", "nah", "not", "dont", "cancel", "skip", "never", "stop"]
        if words.contains(where: no.contains) { return false }
        let yes: Set<String> = ["yes", "yeah", "yep", "sure", "ok", "okay", "start", "go", "add", "confirm", "please", "do"]
        return words.contains(where: yes.contains) ? true : nil
    }

    struct Reply: Equatable {
        let say: String
        let proposal: Proposal?
    }

    /// What to say when the model's reply isn't complete JSON (cut off mid-sentence, or wrapped in a code fence).
    /// Never the raw text: that would read out "json", braces and quote marks. Takes the "say" sentence if there
    /// is one, trimmed to its last whole sentence when the reply was cut off, and drops code fences otherwise.
    nonisolated static func plainSpeech(from raw: String) -> String {
        guard let key = raw.range(of: #""say"\s*:\s*""#, options: .regularExpression) else {
            let unfenced = raw.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // JSON with no "say" has nothing worth reading out.
            if unfenced.hasPrefix("{") || unfenced.hasPrefix("[") { return "Sorry, that didn't come through. Try asking again." }
            return String(unfenced.prefix(600))
        }
        var escaped = false
        var value = ""
        var closed = false
        for character in raw[key.upperBound...] {
            if escaped { value.append("\\"); value.append(character); escaped = false }
            else if character == "\\" { escaped = true }
            else if character == "\"" { closed = true; break }
            else { value.append(character) }
        }
        // Decode the JSON escapes (\n, \", é); a half-written escape just stays as it is.
        var say = (try? JSONSerialization.jsonObject(with: Data("\"\(value)\"".utf8), options: .fragmentsAllowed) as? String) ?? value
        say = say.trimmingCharacters(in: .whitespacesAndNewlines)
        if !closed, let end = say.lastIndex(where: { ".!?".contains($0) }) { say = String(say[...end]) }
        return String(say.prefix(600))
    }

    /// "YYYY-MM-DDTHH:MM" in local time, if it is between an hour ago and a year ahead.
    nonisolated private static func localTime(_ value: Any?, now: Date) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        guard let text = value as? String, let date = formatter.date(from: String(text.prefix(16))),
              date > now.addingTimeInterval(-3600), date < now.addingTimeInterval(366 * 86400) else { return nil }
        return date
    }

    /// Reads the model's JSON reply. Anything that isn't valid JSON is spoken as plain text with no action, and
    /// every action is checked: minutes 5–180, short titles, and events between an hour ago and a year ahead.
    nonisolated static func parseReply(_ raw: String, now: Date, steps: [TestMilestone] = [], assignments: [CanvasAssignment] = [],
                                       habits: [Habit] = [], reminders: [TestAppStateManager.AppleReminder] = [],
                                       canControlMusic: Bool = false, canPause: Bool = false, canResume: Bool = false) -> Reply {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let open = trimmed.firstIndex(of: "{"), let close = trimmed.lastIndex(of: "}"), open < close,
              let json = try? JSONSerialization.jsonObject(with: Data(trimmed[open...close].utf8)) as? [String: Any]
        else { return Reply(say: plainSpeech(from: trimmed), proposal: nil) }

        let say = String(((json["say"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(600))
        guard let action = json["action"] as? [String: Any], let type = action["type"] as? String else {
            return Reply(say: say, proposal: nil)
        }
        let minutes = (action["minutes"] as? NSNumber)?.intValue ?? 25
        guard (5...180).contains(minutes) else { return Reply(say: say, proposal: nil) }

        switch type {
        case "start_session":
            let goal = ((action["goal"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !goal.isEmpty else { return Reply(say: say, proposal: nil) }
            return Reply(say: say, proposal: .startSession(goal: String(goal.prefix(110)), minutes: minutes))
        case "add_event":
            let title = ((action["title"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, let start = localTime(action["start"], now: now) else { return Reply(say: say, proposal: nil) }
            return Reply(say: say, proposal: .addEvent(title: String(title.prefix(100)), start: start, minutes: minutes))
        case "add_reminder":
            let title = ((action["title"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            // A "due" that is there but not a sensible time rejects the whole reminder, rather than saving a wrong date.
            let due = localTime(action["due"], now: now)
            guard !title.isEmpty, due != nil || (action["due"] == nil || action["due"] is NSNull) else { return Reply(say: say, proposal: nil) }
            return Reply(say: say, proposal: .addReminder(title: String(title.prefix(100)), due: due))
        case "complete_step":
            // The number is the step's place in the numbered list the model was given; a done or unknown step is ignored.
            guard let number = (action["number"] as? NSNumber)?.intValue, steps.indices.contains(number - 1), !steps[number - 1].isDone
            else { return Reply(say: say, proposal: nil) }
            return Reply(say: say, proposal: .completeStep(id: steps[number - 1].id, text: String(steps[number - 1].text.prefix(110))))
        case "check_off_assignment":
            guard let number = (action["number"] as? NSNumber)?.intValue, assignments.indices.contains(number - 1)
            else { return Reply(say: say, proposal: nil) }
            return Reply(say: say, proposal: .checkOffAssignment(id: assignments[number - 1].id, title: String(assignments[number - 1].title.prefix(110))))
        case "complete_habit":
            guard let number = (action["number"] as? NSNumber)?.intValue, habits.indices.contains(number - 1) else { return Reply(say: say, proposal: nil) }
            return Reply(say: say, proposal: .completeHabit(id: habits[number - 1].id, name: String(habits[number - 1].name.prefix(80))))
        case "complete_reminder":
            guard let number = (action["number"] as? NSNumber)?.intValue, reminders.indices.contains(number - 1) else { return Reply(say: say, proposal: nil) }
            return Reply(say: say, proposal: .completeReminder(id: reminders[number - 1].id, title: String(reminders[number - 1].title.prefix(100))))
        case "move_reminder":
            guard let number = (action["number"] as? NSNumber)?.intValue, reminders.indices.contains(number - 1),
                  let due = localTime(action["due"], now: now) else { return Reply(say: say, proposal: nil) }
            return Reply(say: say, proposal: .moveReminder(id: reminders[number - 1].id, title: String(reminders[number - 1].title.prefix(100)), due: due))
        case "add_note":
            let title = String(((action["title"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
            let body = String(((action["body"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
            guard !title.isEmpty || !body.isEmpty else { return Reply(say: say, proposal: nil) }
            return Reply(say: say, proposal: .addNote(title: title, body: body))
        case "open_page":
            guard let key = (action["page"] as? String)?.lowercased(), let page = openablePages[key] else { return Reply(say: say, proposal: nil) }
            return Reply(say: say, proposal: .openPage(tab: page.tab, name: page.name))
        case "music":
            guard canControlMusic, let command = MusicCommand(rawValue: (action["command"] as? String) ?? "") else { return Reply(say: say, proposal: nil) }
            return Reply(say: say, proposal: .music(command))
        case "pause_session":
            return Reply(say: say, proposal: canPause ? .pauseSession : nil)
        case "resume_session":
            return Reply(say: say, proposal: canResume ? .resumeSession : nil)
        default:
            return Reply(say: say, proposal: nil)
        }
    }

    #if DEBUG
    /// Debug-only checks of the reply parser, run once at launch.
    private static func selfCheck() {
        let now = ISO8601DateFormatter().date(from: "2026-10-20T12:00:00Z")!
        // A word or two ("Sure.", "Want me to?") joins the sentence next to it; longer sentences are spoken one at a time.
        assert(sentences(in: "Sure. I can start a twenty five minute session on chemistry. Want me to?")
            == ["Sure. I can start a twenty five minute session on chemistry. Want me to?"])
        assert(sentences(in: "Your next session starts at three. You have a chemistry set due tomorrow, and two reminders left. Want me to start a session?")
            == ["Your next session starts at three.", "You have a chemistry set due tomorrow, and two reminders left.", "Want me to start a session?"])
        assert(sentences(in: "Okay") == ["Okay"])
        assert(parseReply("Hello there", now: now) == Reply(say: "Hello there", proposal: nil))
        // A reply cut off mid-sentence is never read out as raw JSON.
        assert(parseReply("```json\n{\n\"say\": \"Got it. I can add a block tomorrow. Get", now: now) == Reply(say: "Got it. I can add a block tomorrow.", proposal: nil))
        assert(parseReply(#"{"say":"He said \"hi\" to me"#, now: now) == Reply(say: #"He said "hi" to me"#, proposal: nil))
        assert(parseReply("```json\n{\"action\": {\"type\": \"add_ev", now: now).say.hasPrefix("Sorry"))
        assert(parseReply(#"{"say":"Let's go","action":{"type":"start_session","goal":"Essay intro","minutes":25}}"#, now: now)
            == Reply(say: "Let's go", proposal: .startSession(goal: "Essay intro", minutes: 25)))
        assert(parseReply(#"{"say":"x","action":{"type":"start_session","goal":"A","minutes":999}}"#, now: now).proposal == nil)
        assert(parseReply(#"{"say":"x","action":{"type":"start_session","goal":"  ","minutes":25}}"#, now: now).proposal == nil)
        assert(parseReply(#"{"say":"x","action":{"type":"add_event","title":"Study","start":"2030-01-01T10:00","minutes":60}}"#, now: now).proposal == nil)
        if case .addEvent(let title, _, let minutes)? = parseReply(#"```json {"say":"Done","action":{"type":"add_event","title":"Study bio","start":"2026-10-21T16:00","minutes":60}} ```"#, now: now).proposal {
            assert(title == "Study bio" && minutes == 60)
        } else {
            assertionFailure("add_event should parse")
        }
        assert(parseReply(#"{"say":"x","action":{"type":"delete_everything"}}"#, now: now).proposal == nil)
        // The hold key: a tap does nothing; a hold starts listening once and ends on release; a shortcut, another modifier or a
        // press while Locken is busy never starts it.
        typealias Step = (t: Double, down: Bool, alone: Bool, idle: Double, busy: Bool)
        func events(_ steps: [Step]) -> [HotkeyMachine.Event] {
            var machine = HotkeyMachine()
            return steps.compactMap { machine.tick(down: $0.down, alone: $0.alone, idleSeconds: $0.idle, busy: $0.busy, now: $0.t) }
        }
        let quiet = 30.0
        assert(events([(0, true, true, quiet, false), (0.1, true, true, quiet, false), (0.15, false, true, quiet, false)]) == [.released], "a tap")
        assert(events([(0, true, true, quiet, false), (0.2, true, true, quiet, false), (0.31, true, true, quiet, false), (0.5, true, true, quiet, false), (0.9, false, true, quiet, false)]) == [.held, .released], "a hold")
        assert(events([(0, true, true, quiet, false), (0.2, true, true, 0.05, false), (0.4, true, true, 0.25, false), (0.5, false, true, quiet, false)]) == [.released], "a key typed while holding")
        assert(events([(0, true, false, quiet, false), (0.4, true, false, quiet, false), (0.5, false, false, quiet, false)]) == [.released], "another modifier down")
        assert(events([(0, true, true, quiet, true), (0.5, true, true, quiet, true), (0.6, false, true, quiet, false)]) == [.pressedWhileBusy, .released], "a press while busy")
        assert(events([(0, true, true, 0.1, false), (0.4, true, true, 0.5, false)]) == [.held], "a key typed just before the press doesn't count")
        assert(events([(0, true, true, quiet, false), (0.4, true, true, quiet, false), (0.5, false, true, quiet, false), (1, true, true, quiet, false), (1.4, true, true, quiet, false)]) == [.held, .released, .held], "holding again")
        // Steps and assignments are picked by their number in the lists the model was given.
        let steps = [TestMilestone(text: "Plan"), TestMilestone(text: "Write intro", isDone: true), TestMilestone(text: "Wrap up")]
        let homework = [CanvasAssignment(id: "a1", title: "Essay", courseName: "English", dueDate: nil, htmlURL: nil)]
        assert(parseReply(#"{"say":"x","action":{"type":"complete_step","number":3}}"#, now: now, steps: steps).proposal == .completeStep(id: steps[2].id, text: "Wrap up"))
        assert(parseReply(#"{"say":"x","action":{"type":"complete_step","number":2}}"#, now: now, steps: steps).proposal == nil, "already done")
        assert(parseReply(#"{"say":"x","action":{"type":"complete_step","number":9}}"#, now: now, steps: steps).proposal == nil)

        // Habits, reminders, notes, pages, music and pausing: only the numbered or allowed ones become actions.
        let habit = Habit(name: "Read 20 pages", symbol: "book", category: "Learning")
        let reminder = TestAppStateManager.AppleReminder(
            id: "r1", title: "Email Mr. Lee", notes: "", due: nil, hasDueTime: false, listID: "l1", listTitle: "School", color: .red,
            priority: .none, repeats: .never, hasAlert: false, url: "", isCompleted: false, completedAt: nil)
        assert(parseReply(#"{"say":"x","action":{"type":"complete_habit","number":1}}"#, now: now, habits: [habit]).proposal == .completeHabit(id: habit.id, name: "Read 20 pages"))
        assert(parseReply(#"{"say":"x","action":{"type":"complete_habit","number":2}}"#, now: now, habits: [habit]).proposal == nil)
        assert(parseReply(#"{"say":"x","action":{"type":"complete_habit","number":1}}"#, now: now).proposal == nil, "no habits to tick")
        assert(parseReply(#"{"say":"x","action":{"type":"complete_reminder","number":1}}"#, now: now, reminders: [reminder]).proposal == .completeReminder(id: "r1", title: "Email Mr. Lee"))
        assert(parseReply(#"{"say":"x","action":{"type":"complete_reminder","number":0}}"#, now: now, reminders: [reminder]).proposal == nil)
        if case .moveReminder(let id, _, _)? = parseReply(#"{"say":"x","action":{"type":"move_reminder","number":1,"due":"2026-10-21T16:00"}}"#, now: now, reminders: [reminder]).proposal {
            assert(id == "r1")
        } else {
            assertionFailure("move_reminder should parse")
        }
        assert(parseReply(#"{"say":"x","action":{"type":"move_reminder","number":1,"due":"2030-01-01T16:00"}}"#, now: now, reminders: [reminder]).proposal == nil, "a date years away is refused")
        assert(parseReply(#"{"say":"x","action":{"type":"move_reminder","number":1}}"#, now: now, reminders: [reminder]).proposal == nil, "no date")
        assert(parseReply(#"{"say":"x","action":{"type":"add_note","title":"Bio","body":"Mitosis has four phases"}}"#, now: now).proposal == .addNote(title: "Bio", body: "Mitosis has four phases"))
        assert(parseReply(#"{"say":"x","action":{"type":"add_note","title":" ","body":""}}"#, now: now).proposal == nil)
        if case .addNote(_, let body)? = parseReply(#"{"say":"x","action":{"type":"add_note","body":"\#(String(repeating: "a", count: 5000))"}}"#, now: now).proposal {
            assert(body.count == 2000, "a long note is cut to 2000 characters")
        } else {
            assertionFailure("a note with only a body should parse")
        }
        assert(parseReply(#"{"say":"x","action":{"type":"open_page","page":"analytics"}}"#, now: now).proposal == .openPage(tab: "usage", name: "Analytics"))
        assert(parseReply(#"{"say":"x","action":{"type":"open_page","page":"admin"}}"#, now: now).proposal == nil, "Admin isn't openable by voice")
        assert(parseReply(#"{"say":"x","action":{"type":"music","command":"next"}}"#, now: now).proposal == nil, "no player")
        assert(parseReply(#"{"say":"x","action":{"type":"music","command":"next"}}"#, now: now, canControlMusic: true).proposal == .music(.next))
        assert(parseReply(#"{"say":"x","action":{"type":"music","command":"shuffle"}}"#, now: now, canControlMusic: true).proposal == nil)
        assert(parseReply(#"{"say":"x","action":{"type":"pause_session"}}"#, now: now).proposal == nil, "nothing is running")
        assert(parseReply(#"{"say":"x","action":{"type":"pause_session"}}"#, now: now, canPause: true).proposal == .pauseSession)
        assert(parseReply(#"{"say":"x","action":{"type":"resume_session"}}"#, now: now, canResume: true).proposal == .resumeSession)
        assert(parseReply(#"{"say":"x","action":{"type":"resume_session"}}"#, now: now, canPause: true).proposal == nil, "a running session can't be resumed")
        assert(parseReply(#"{"say":"x","action":{"type":"end_session"}}"#, now: now, canPause: true).proposal == nil, "ending a session isn't an action")
        assert(parseReply(#"{"say":"x","action":{"type":"complete_step","number":1}}"#, now: now).proposal == nil, "no steps")
        assert(parseReply(#"{"say":"x","action":{"type":"check_off_assignment","number":1}}"#, now: now, assignments: homework).proposal == .checkOffAssignment(id: "a1", title: "Essay"))
        assert(parseReply(#"{"say":"x","action":{"type":"check_off_assignment","number":0}}"#, now: now, assignments: homework).proposal == nil)
        assert(parseReply(#"{"say":"x","action":{"type":"add_reminder","title":"Email Mr. Lee"}}"#, now: now).proposal == .addReminder(title: "Email Mr. Lee", due: nil))
        assert(parseReply(#"{"say":"x","action":{"type":"add_reminder","title":"Email Mr. Lee","due":null}}"#, now: now).proposal == .addReminder(title: "Email Mr. Lee", due: nil))
        assert(parseReply(#"{"say":"x","action":{"type":"add_reminder","title":"Email","due":"2030-01-01T10:00"}}"#, now: now).proposal == nil, "a due date a year out is rejected, not dropped")
        assert(parseReply(#"{"say":"x","action":{"type":"add_reminder","title":"  "}}"#, now: now).proposal == nil)
        if case .addReminder(_, let due)? = parseReply(#"{"say":"x","action":{"type":"add_reminder","title":"Email","due":"2026-10-21T09:00"}}"#, now: now).proposal {
            assert(due != nil)
        } else {
            assertionFailure("add_reminder with a due time should parse")
        }
        assert(confirmation(in: "Yes") == true && confirmation(in: "sure, do it") == true && confirmation(in: "okay start it") == true)
        assert(confirmation(in: "no") == false && confirmation(in: "not now") == false && confirmation(in: "please don't") == false)
        assert(confirmation(in: "what's due tomorrow") == nil && confirmation(in: "yes but first tell me about my biology homework") == nil)
    }
    #endif
}
