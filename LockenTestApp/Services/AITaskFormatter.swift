import Foundation

/// "Intelligent Rephrase": turns a vague session goal ("do math", "read book") into one specific,
/// actionable, motivating goal ("Complete 15 practice problems for Calculus Chapter 4").
///
/// Works with whichever key is saved in Settings: Claude (Anthropic Messages API) for keys starting
/// `sk-ant-`, ChatGPT (OpenAI Chat Completions API) for other `sk-` keys, or Gemini (Google Generative
/// Language API) for keys starting `AIza`. The key is stored in the macOS Keychain. Gemini keys differ in which models they can use, so the best available Flash model is
/// looked up once and the next one is tried if a model is missing or rate-limited.
@MainActor
final class AITaskFormatter: ObservableObject {
    static let shared = AITaskFormatter()

    enum Provider: String {
        case claude, openAI, gemini

        var displayName: String {
            switch self {
            case .claude: return "Claude"
            case .openAI: return "ChatGPT"
            case .gemini: return "Gemini"
            }
        }

        /// Claude keys start with `sk-ant-` and OpenAI's with `sk-` (`sk-proj-…`, `sk-svcacct-…`). Gemini keys are older
        /// standard keys (`AIza…`) or AI Studio's newer auth keys, whose format Google doesn't document, so any other
        /// key is Gemini.
        static func detect(fromKey key: String) -> Provider? {
            if key.hasPrefix("sk-ant-") { return .claude }
            if key.count < 20 || key.contains(where: \.isWhitespace) { return nil }
            return key.hasPrefix("sk-") ? .openAI : .gemini
        }
    }

    /// What the model knows besides the typed text, so "do math" can become the student's real assignment.
    struct Context {
        var sessionMinutes: Int
        var workspaceApp: String?
        var upcomingAssignments: [CanvasAssignment] = []
    }

    enum FormatterError: LocalizedError, Equatable {
        case disabled
        case ageUnknown
        case ageRestricted
        case missingAPIKey
        case unrecognizedKey
        case invalidKey(Provider)
        /// The key works, but its Google Cloud project or restrictions block this use; the text says what to change.
        case keyBlocked(Provider, String)
        /// This model isn't open to the key (403 on one model); the next model is tried.
        case modelUnavailable(Provider)
        case rateLimited(Provider)
        case emptyResponse
        /// The typed goal doesn't say what the work is, so there's nothing to rephrase without guessing.
        case unclearGoal
        case server(Provider, status: Int, message: String)
        case network(String)
        case timedOut

        /// Failures that usually clear on their own within a second or two: worth one more try.
        var isTransient: Bool {
            switch self {
            case .timedOut, .network, .emptyResponse, .rateLimited: return true
            case .server(_, let status, _): return status == 408 || (500...599).contains(status)
            default: return false
            }
        }

        var errorDescription: String? {
            switch self {
            case .unclearGoal:
                return "Couldn't tell what that goal is about. Add the subject or task, like \u{201C}math homework\u{201D} or \u{201C}history essay\u{201D}."
            case .disabled:
                return "Intelligent Rephrase is turned off in Settings."
            case .ageUnknown:
                return "Enter your date of birth in Settings to use AI features."
            case .ageRestricted:
                return "AI features are for people 18 and older."
            case .missingAPIKey:
                return "Add a Claude, ChatGPT or Gemini API key in Settings to use Intelligent Rephrase."
            case .unrecognizedKey:
                return "That doesn't look like a Claude (sk-ant-…), ChatGPT (sk-…) or Gemini (Google AI Studio) key."
            case .invalidKey(let provider):
                return "\(provider.displayName) rejected the API key. Check it in Settings."
            case .keyBlocked(_, let advice):
                return advice
            case .modelUnavailable(let provider):
                return "\(provider.displayName) didn't allow this key to use any of its models. Check the key in Google AI Studio, or create a new one there."
            case .rateLimited(let provider):
                return "\(provider.displayName) is limiting requests right now. Try again in a minute."
            case .emptyResponse:
                return "The AI sent back an empty answer. Try again."
            case .server(let provider, let status, _) where [502, 503, 504, 529].contains(status):
                return "\(provider.displayName) is busy right now (error \(status)). Try again in a moment."
            case .server(let provider, let status, _):
                // The raw server message stays out of the UI; the status is enough to report a problem.
                return "\(provider.displayName) had a problem (error \(status)). Try again in a moment."
            case .network(let message):
                return "Couldn't reach the AI service: \(message)"
            case .timedOut:
                return "That took too long. Try again in a moment."
            }
        }
    }

    /// Latest Claude generation; a one-sentence rewrite comes back in a second or two.
    nonisolated static let claudeModel = "claude-sonnet-5"

    @Published private(set) var provider: Provider?
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }

    var isConfigured: Bool { provider != nil }

    /// "-v2" since 2.0.3: items from earlier builds made macOS ask for the Mac password, so they are never read.
    private static let keychainService = "com.locken.LockenTestApp.ai-v2"
    private static let keychainAccountBase = "llm.apiKey"
    /// Per account, so one account's key is never used by another on the same Mac.
    private static var keychainAccount: String { keychainAccountBase + AccountScope.suffix }
    private static let enabledKey = "ai.rephraseEnabled"

    /// Gemini models this key can use, best first; looked up on first use.
    private var geminiModels: [String]?

    private init() {
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        provider = KeychainStore.get(service: Self.keychainService, account: Self.keychainAccount).flatMap(Provider.detect)
        #if DEBUG
        Self.selfCheck()
        #endif
    }

    #if DEBUG
    private static func selfCheck() {
        assert(Provider.detect(fromKey: "sk-ant-api03-abc") == .claude)
        assert(Provider.detect(fromKey: "sk-proj-0123456789012345678901") == .openAI)
        assert(Provider.detect(fromKey: "sk-012345678901234567890") == .openAI)
        assert(Provider.detect(fromKey: "sk-short") == nil)
        assert(Provider.detect(fromKey: "AIzaSyA0123456789012345678901") == .gemini)
        assert(Provider.detect(fromKey: "short") == nil)
        assert(Provider.detect(fromKey: "sk-proj-has a space in it but long enough") == nil)
    }
    #endif

    /// Loads the signed-in account's API key.
    func activateAccount() {
        AccountScope.adoptLegacyKeychainItem(service: Self.keychainService, account: Self.keychainAccountBase)
        provider = KeychainStore.get(service: Self.keychainService, account: Self.keychainAccount).flatMap(Provider.detect)
        geminiModels = nil
        cooldowns = [:]
    }

    // MARK: API key

    @discardableResult
    func saveAPIKey(_ rawKey: String) throws -> Provider {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let detected = Provider.detect(fromKey: key) else { throw FormatterError.unrecognizedKey }
        KeychainStore.set(key, service: Self.keychainService, account: Self.keychainAccount)
        provider = detected
        geminiModels = nil
        cooldowns = [:]
        return detected
    }

    func removeAPIKey() {
        KeychainStore.delete(service: Self.keychainService, account: Self.keychainAccount)
        provider = nil
        geminiModels = nil
        cooldowns = [:]
    }

    // MARK: Rephrase

    /// Whether the AI can be asked to judge a video right now (on, a key added, and the user is 18+).
    var canJudgeVideos: Bool { isEnabled && isConfigured && AgeGate.shared.meetsAIMinimum == true }

    /// Asks the AI whether a YouTube video belongs in a study session. Only the video's title, channel and the
    /// session goal are sent. Returns the verdict and a short reason to show the student.
    func judgeVideo(title: String, channel: String, goal: String) async throws -> (isEducational: Bool, reason: String) {
        let system = """
        You decide whether a YouTube video is appropriate during a student's focus session. Say YES only if it is \
        educational or clearly needed for schoolwork (lessons, lectures, tutorials, explainers, documentaries, \
        how-tos, practice problems, language learning, assigned media). Say NO for entertainment, gaming, music \
        videos, vlogs, reactions, pranks, shorts, highlights or anything mainly for fun. Answer on one line as \
        "YES: reason" or "NO: reason", with a reason of at most 12 words.
        """
        let user = "Session goal: \(goal.isEmpty ? "not given" : goal)\nVideo title: \(title)\nChannel: \(channel)"
        let raw = try await ask(system: system, user: user, maxTokens: 60)
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let verdict = line.uppercased().hasPrefix("YES")
        let reason = line.split(separator: ":", maxSplits: 1).dropFirst().first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        return (verdict, reason)
    }

    func rephrase(_ text: String, context: Context) async throws -> String {
        let raw = try await ask(
            system: Self.systemPrompt(sessionMinutes: context.sessionMinutes),
            user: Self.userMessage(for: text, context: context)
        )
        let goal = Self.cleaned(raw)
        guard !goal.isEmpty else { throw FormatterError.emptyResponse }
        if goal.uppercased().hasPrefix("UNCLEAR") { throw FormatterError.unclearGoal }
        return goal
    }

    // MARK: Assistant

    /// What the Assistant may suggest right now. Each one needs something true of the app at that moment, so the model is only
    /// told about actions that can work.
    struct AssistantAbilities: Equatable {
        var canAddEvents = false
        var canAddReminders = false
        /// Reminders access: mark reminders done and move them.
        var canEditReminders = false
        /// A music player is running.
        var canControlMusic = false
        /// A focus session is running (pausing goes through commitment mode).
        var canPause = false
        /// A focus session is paused.
        var canResume = false
    }

    /// The Assistant tab's reply as JSON (see `assistantPrompt`). `history` is the last few turns, oldest first.
    func assistantReply(history: [String], context: String, abilities: AssistantAbilities) async throws -> String {
        let user = "About the student's day:\n\(context)\n\nConversation:\n\(history.joined(separator: "\n"))"
        let reply = try await ask(system: Self.assistantPrompt(abilities), user: user, maxTokens: 400, quick: true)
        guard !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw FormatterError.emptyResponse }
        return reply
    }

    nonisolated static func assistantPrompt(_ abilities: AssistantAbilities) -> String {
        let canAddEvents = abilities.canAddEvents, canAddReminders = abilities.canAddReminders
        let eventAction = canAddEvents
            ? #"- {"type":"add_event","title":"Study biology","start":"YYYY-MM-DDTHH:MM","minutes":60} to put something on their calendar (local time)."#
            : "- You can't add calendar events. If asked, say they can turn that on at the bottom of the Assistant tab."
        let reminderAction = canAddReminders
            ? #"- {"type":"add_reminder","title":"Email Mr. Lee","due":"YYYY-MM-DDTHH:MM"} to add a reminder to the Reminders app (local time; leave "due" out for no date)."#
            : "- You can't add reminders. If asked, say Locken needs Reminders access (Notes & Reminders tab)."
        let reminderEdits = abilities.canEditReminders
            ? """
            - {"type":"complete_reminder","number":1} to mark reminder 1 (numbered below) done in the Reminders app.
            - {"type":"move_reminder","number":1,"due":"YYYY-MM-DDTHH:MM"} to change when reminder 1 is due (local time).
            """
            : "- You can't change reminders. If asked, say Locken needs Reminders access (Notes & Reminders tab)."
        let music = abilities.canControlMusic
            ? #"- {"type":"music","command":"play_pause"} to play or pause their music; "command" can also be "next" or "previous" song."#
            : "- No music player is running, so you can't control music."
        var session: [String] = []
        if abilities.canPause { session.append(#"- {"type":"pause_session"} to pause their running focus session. The app makes them wait a moment first; never push them to quit."#) }
        if abilities.canResume { session.append(#"- {"type":"resume_session"} to resume their paused focus session."#) }
        if session.isEmpty { session.append("- You can't pause, resume or end a focus session; only start one. If asked to stop one, say it's their call in the app.") }
        return """
        You are Locken, a friendly study coach inside a focus app for students. You talk out loud, so every reply \
        is spoken: one to three short sentences, plain words, no lists, markdown, emoji or links.

        You help the student plan and start focus sessions, answer questions about their schedule (Canvas \
        assignments, habits and calendar, given below), and coach them: encourage them when they're stuck, help \
        them pick what to do next, and check in on how a running session is going. Only use the facts given; \
        never invent assignments, events or due dates. Keep the conversation on their studies, focus and \
        wellbeing; for anything else, steer back kindly in one sentence.

        You can suggest one action. The app asks the student to confirm it, so describe it as a suggestion:
        - {"type":"start_session","goal":"Draft the intro of the history essay","minutes":25} to start a focus \
        session (5 to 180 minutes; 25 if they don't say).
        - {"type":"complete_step","number":2} to tick off step 2 of their focus steps (numbered below), when they \
        say they finished it.
        - {"type":"check_off_assignment","number":1} to mark Canvas assignment 1 (numbered below) done in Locken, \
        when they say they handed it in. Nothing is sent to Canvas.
        \(eventAction)
        \(reminderAction)
        \(reminderEdits)
        - {"type":"complete_habit","number":2} to tick off today's habit 2 (numbered below) when they say they did it.
        - {"type":"add_note","title":"Biology ideas","body":"the note's text"} to save a note in Locken's Notes, when they ask you to jot something down.
        - {"type":"open_page","page":"analytics"} to open a page; "page" is one of home, focus, assistant, calendar, habits, analytics, notes, settings.
        \(music)
        \(session.joined(separator: "\n"))

        You can also answer questions about their day from the facts given: focus time, screen time, streaks, habits, \
        reminders, assignments and events. Say the numbers plainly; if a fact isn't given, say you don't have it.

        Reply with JSON only, no other text: {"say":"what you say out loud","action":null}, or with one action \
        in place of null.
        """
    }

    // MARK: Digests

    struct DigestReminder {
        let title: String
        let due: Date?
        let hasDueTime: Bool
        let list: String
        /// "high", "medium", "low", or empty.
        let priority: String
    }

    struct DigestItem {
        enum Kind: String { case canvas = "Canvas", calendar = "Calendar" }
        let kind: Kind
        let start: Date
        var end: Date? = nil
        var isAllDay = false
        let title: String
        var detail: String = ""
    }

    /// A short digest of the student's open reminders: what needs attention, what's coming, and an order to do them in.
    func remindersDigest(_ reminders: [DigestReminder], now: Date = Date()) async throws -> String {
        let text = try await ask(system: Self.remindersDigestPrompt(now: now), user: Self.remindersDigestMessage(reminders, now: now), maxTokens: 900)
        let digest = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !digest.isEmpty else { throw FormatterError.emptyResponse }
        return digest
    }

    /// A plan for the next 7 days from Canvas due dates and calendar events.
    func weekDigest(_ items: [DigestItem], now: Date = Date()) async throws -> String {
        let text = try await ask(system: Self.weekDigestPrompt(now: now), user: Self.weekDigestMessage(items), maxTokens: 900)
        let digest = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !digest.isEmpty else { throw FormatterError.emptyResponse }
        return digest
    }

    nonisolated static func remindersDigestPrompt(now: Date) -> String {
        """
        You turn a student's open reminders into a short digest they can read in under a minute.
        Today is \(now.formatted(.dateTime.weekday(.wide).month(.wide).day().hour().minute())).

        Reply in Markdown with these sections, each starting with a level-3 heading (###):
        ### Needs attention
        Overdue reminders and ones due today, most urgent first, with when they're due. \
        If there are none, write one line saying so.
        ### Coming up
        Up to 6 reminders due next, in date order, with their day.
        ### Suggested order
        3 to 5 bullets on what to do first and why (due date, priority), grouping quick tasks together.

        Use only the reminders given. Never invent reminders, dates or details. No emojis, \
        no introduction or sign-off.
        """
    }

    /// Title, list, due date and priority only; reminder notes are never sent.
    nonisolated static func remindersDigestMessage(_ reminders: [DigestReminder], now: Date) -> String {
        let sorted = reminders.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }.prefix(60)
        let lines = sorted.map { reminder -> String in
            var parts = ["- \(reminder.title) [\(reminder.list)]"]
            if let due = reminder.due {
                let when = reminder.hasDueTime
                    ? due.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                    : due.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
                let overdue = reminder.hasDueTime ? due < now : due < Calendar.current.startOfDay(for: now)
                parts.append("due \(when)\(overdue ? " (overdue)" : "")")
            } else {
                parts.append("no due date")
            }
            if !reminder.priority.isEmpty { parts.append("\(reminder.priority) priority") }
            return parts.joined(separator: " · ")
        }
        return lines.isEmpty ? "I have no open reminders." : "My open reminders:\n" + lines.joined(separator: "\n")
    }

    nonisolated static func weekDigestPrompt(now: Date) -> String {
        """
        You turn a student's next 7 days of Canvas assignments and calendar events into a short weekly plan.
        Today is \(now.formatted(.dateTime.weekday(.wide).month(.wide).day().hour().minute())).

        Reply in Markdown with these sections, each starting with a level-3 heading (###):
        ### Due this week
        Bullets in date order: the assignment, its course, and its due day and time. \
        Start the bullet with **Soon:** when it's due within 48 hours. If nothing is due, write one line saying so.
        ### Busy days
        1 to 3 bullets naming the days with the most events or deadlines, and why.
        ### Plan
        3 to 5 bullets suggesting when to work on which assignment, using free time around the events, \
        for example "Tuesday after school: 45 minutes on Unit 1 Review".

        Use only the items given. Never invent assignments, events, courses or times. No emojis, \
        no introduction or sign-off.
        """
    }

    nonisolated static func weekDigestMessage(_ items: [DigestItem]) -> String {
        let lines = items.sorted { $0.start < $1.start }.prefix(80).map { item -> String in
            let day = item.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            let time: String
            if item.isAllDay {
                time = "all day"
            } else if let end = item.end {
                time = "\(item.start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))"
            } else {
                time = "due \(item.start.formatted(date: .omitted, time: .shortened))"
            }
            let detail = item.detail.isEmpty ? "" : " (\(item.detail))"
            return "- [\(item.kind.rawValue)] \(day), \(time): \(item.title)\(detail)"
        }
        return lines.isEmpty ? "Nothing is scheduled or due in the next 7 days." : "My next 7 days:\n" + lines.joined(separator: "\n")
    }

    // MARK: Milestones

    /// Breaks a session goal into a few small steps to tick off during the session.
    func milestones(for goal: String, context: Context) async throws -> [String] {
        let raw = try await ask(
            system: Self.milestonesPrompt(sessionMinutes: context.sessionMinutes),
            user: Self.userMessage(for: goal, context: context)
        )
        let steps = Self.steps(from: raw)
        guard !steps.isEmpty else { throw FormatterError.emptyResponse }
        return steps
    }

    /// How many steps suit a session: a few for short ones, more for long ones.
    nonisolated static func stepCount(sessionMinutes: Int) -> Int {
        switch sessionMinutes {
        case ..<20: return 3
        case ..<50: return 4
        default: return 5
        }
    }

    nonisolated static func milestonesPrompt(sessionMinutes: Int) -> String {
        """
        You break a student's focus-session goal into \(stepCount(sessionMinutes: sessionMinutes)) small milestones \
        they will tick off, in order, during a \(sessionMinutes)-minute session.

        Each milestone:
        - Is one concrete step toward the goal, specific to its subject and material.
        - Starts with a verb such as Read, Outline, Solve, Draft, Check or Review.
        - Is sized so all of them together fit in about \(sessionMinutes) minutes.
        - Is at most 60 characters, plain, with no emojis.

        If the goal matches one of their upcoming Canvas assignments, use what that assignment involves.

        Reply with the milestones only, one per line, no numbering, bullets or other text.
        """
    }

    /// One step per line, without the numbering or bullets a model may add anyway.
    nonisolated static func steps(from raw: String) -> [String] {
        let markers = Set("-*•–·.)")
        return raw.split(whereSeparator: \.isNewline)
            .map { line -> String in
                var text = line.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
                while let first = text.first, markers.contains(first) || first.isNumber {
                    text.removeFirst()
                    text = text.trimmingCharacters(in: .whitespaces)
                }
                return cleaned(text)
            }
            .filter { !$0.isEmpty }
            .prefix(6)
            .map { $0 }
    }

    // MARK: Provider

    /// Removes contact details and links from text before it goes to an AI provider: email addresses, phone
    /// numbers and web addresses become placeholders. Every AI request goes through `ask`, which applies this.
    nonisolated static func scrubPersonalInfo(_ text: String) -> String {
        let rules: [(String, String)] = [
            (#"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, "[email]"),
            (#"(?:https?://|www\.)[^\s<>"']+"#, "[link]"),
            (#"(?<![\w])(?:\+?\d{1,3}[\s.-]?)?(?:\(\d{3}\)|\d{3})[\s.-]?\d{3}[\s.-]?\d{4}(?![\w])"#, "[phone]"),
        ]
        var result = text
        for (pattern, placeholder) in rules {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: placeholder)
        }
        return result
    }

    /// `quick` is for replies that are spoken aloud: Gemini skips most of its thinking and gives up on a slow model fast.
    private func ask(system: String, user rawUser: String, maxTokens: Int = 400, quick: Bool = false) async throws -> String {
        let user = Self.scrubPersonalInfo(rawUser)
        guard isEnabled else { throw FormatterError.disabled }
        // Claude's, ChatGPT's and Gemini's terms don't allow users under 18.
        switch AgeGate.shared.meetsAIMinimum {
        case nil: throw FormatterError.ageUnknown
        case false?: throw FormatterError.ageRestricted
        case true?: break
        }
        guard let key = KeychainStore.get(service: Self.keychainService, account: Self.keychainAccount) else {
            throw FormatterError.missingAPIKey
        }
        guard let provider = Provider.detect(fromKey: key) else { throw FormatterError.unrecognizedKey }

        switch provider {
        case .claude:
            return try await Self.retryingOnce { try await Self.askClaude(system: system, user: user, key: key, maxTokens: maxTokens, quick: quick) }
        case .openAI:
            return try await Self.retryingOnce { try await Self.askOpenAI(system: system, user: user, key: key, maxTokens: maxTokens, quick: quick) }
        case .gemini:
            if geminiModels == nil { geminiModels = await Self.availableGeminiModels(key: key) }
            return try await askGemini(system: system, user: user, key: key, maxTokens: maxTokens, quick: quick)
        }
    }

    // MARK: Prompt

    nonisolated static func systemPrompt(sessionMinutes: Int) -> String {
        """
        You turn a student's rough focus-session goal into one clear goal they can finish in this session.

        Students often type vague, lazy goals like "do math" or "read book". Rewrite the goal so it is:
        - Specific: name the exact task, the material and an amount (problems, pages, sections, paragraphs).
        - Actionable: start with a concrete verb such as Complete, Draft, Read and annotate, Solve, Outline, Review.
        - Achievable in about \(sessionMinutes) minutes: scale the amount to the session length.
        - Motivating but plain: no hype, emojis or exclamation marks.

        Keep the student's intent and subject. Never change the subject to something they didn't mention.

        Canvas assignments are reference only. Use one only when the goal names its subject, course, topic or \
        title (for example "precalc", "unit 1 review" or "spanish vocab"). Never pick an assignment just \
        because it is due soon. If the goal names a subject but no assignment matches, keep their subject and \
        choose a realistic scope they can edit afterwards.

        If the goal doesn't say what the work is (random words, a name, a joke, gibberish, or something like \
        "lock in" or "work"), don't guess. Reply with exactly: UNCLEAR

        Examples:
        do math -> Complete 15 practice problems for Calculus Chapter 4
        read book -> Read and annotate Chapter 3 of the Biology textbook
        essay -> Draft the introduction and first body paragraph of the history essay
        locken lockin -> UNCLEAR
        asdf -> UNCLEAR

        Reply with the goal only (or UNCLEAR): one sentence, at most 110 characters, no quotation marks, no preamble.
        """
    }

    nonisolated static func userMessage(for text: String, context: Context) -> String {
        var lines = ["Goal: \(text)", "Session length: \(context.sessionMinutes) minutes"]
        if let app = context.workspaceApp { lines.append("Working in: \(app)") }
        let assignments = context.upcomingAssignments.prefix(8)
        if !assignments.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE MMM d"
            lines.append("Upcoming Canvas assignments (reference only; use one only if the goal names it):")
            for assignment in assignments {
                var line = "- \(assignment.title)"
                if !assignment.courseName.isEmpty { line += " (\(assignment.courseName))" }
                if let due = assignment.dueDate { line += ", due \(formatter.string(from: due))" }
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n")
    }

    /// First line only, without quotes or a "Goal:" label the model might add anyway.
    nonisolated static func cleaned(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstLine = text.split(whereSeparator: \.isNewline).first { text = String(firstLine) }
        for label in ["goal:", "rephrased goal:", "rewritten goal:"] where text.lowercased().hasPrefix(label) {
            text = String(text.dropFirst(label.count))
        }
        let trimmable = CharacterSet(charactersIn: "\"'“”‘’`*").union(.whitespaces)
        return text.trimmingCharacters(in: trimmable)
    }

    /// A dropped connection, a busy server or a blank reply usually works the second time, so Claude and ChatGPT get one more
    /// try before the student sees an error. Gemini has its own fallback across models.
    nonisolated private static func retryingOnce(_ work: () async throws -> String) async throws -> String {
        do { return try await work() }
        catch let error as FormatterError where error.isTransient {
            try await Task.sleep(for: .seconds(1))
            return try await work()
        }
    }

    // MARK: Claude (Anthropic Messages API)

    nonisolated private static func askClaude(system: String, user: String, key: String, maxTokens: Int, quick: Bool) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        // A spoken reply that hasn't started in 15 s is better retried than waited for.
        request.timeoutInterval = quick ? 15 : (maxTokens > 400 ? 60 : 30)
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": claudeModel,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [["role": "user", "content": user]],
        ])

        let (data, status) = try await send(request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard status == 200 else {
            let message = ((json?["error"] as? [String: Any])?["message"] as? String) ?? ""
            switch status {
            case 401, 403: throw FormatterError.invalidKey(.claude)
            case 429: throw FormatterError.rateLimited(.claude)
            default: throw FormatterError.server(.claude, status: status, message: message)
            }
        }
        let blocks = json?["content"] as? [[String: Any]] ?? []
        let text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw FormatterError.emptyResponse }
        return text
    }

    // MARK: ChatGPT (OpenAI Chat Completions API)

    /// Plain chat models, best first (no reasoning step, so a spoken reply comes back in a second or two). The next one
    /// is tried when a key has no access to one.
    nonisolated static let openAIModels = ["gpt-4.1-mini", "gpt-4o-mini"]

    nonisolated private static func askOpenAI(system: String, user: String, key: String, maxTokens: Int, quick: Bool) async throws -> String {
        for model in openAIModels {
            var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
            request.httpMethod = "POST"
            request.timeoutInterval = quick ? 15 : (maxTokens > 400 ? 60 : 30)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "authorization")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": model,
                "max_completion_tokens": maxTokens,
                "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
            ])

            let (data, status) = try await send(request)
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if status == 200 {
                let choice = (json?["choices"] as? [[String: Any]])?.first
                let text = (choice?["message"] as? [String: Any])?["content"] as? String ?? ""
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw FormatterError.emptyResponse }
                return text
            }
            let error = json?["error"] as? [String: Any]
            let message = error?["message"] as? String ?? ""
            let code = error?["code"] as? String ?? ""
            let hasNextModel = model != openAIModels.last
            switch status {
            case 401: throw FormatterError.invalidKey(.openAI)
            case 403 where hasNextModel, 404 where hasNextModel: continue // no access to this model: try the next one
            case 403: throw FormatterError.keyBlocked(.openAI, "ChatGPT didn't allow this key to use a model Locken can use. Check the key's project and permissions at platform.openai.com, or create a new key there.")
            case 404: throw FormatterError.keyBlocked(.openAI, "ChatGPT has no model Locken can use for this key. Check the key's project at platform.openai.com, or create a new key there.")
            // A key with no credit left also answers 429; it needs billing, not waiting.
            case 429 where code == "insufficient_quota":
                throw FormatterError.keyBlocked(.openAI, "This ChatGPT key has no credit left. Add credit at platform.openai.com/settings/organization/billing, or paste a different key. A ChatGPT Plus subscription doesn't include API credit.")
            case 429: throw FormatterError.rateLimited(.openAI)
            default: throw FormatterError.server(.openAI, status: status, message: message)
            }
        }
        throw FormatterError.emptyResponse
    }

    // MARK: Gemini (Generative Language API)

    private func askGemini(system: String, user: String, key: String, maxTokens: Int, quick: Bool) async throws -> String {
        let models = geminiCandidates(quick: quick)
        guard !models.isEmpty else {
            geminiModels = nil // every model was "not offered to this key": look the list up again next time
            throw FormatterError.modelUnavailable(.gemini)
        }
        if quick { return try await raceGemini(models, system: system, user: user, key: key, maxTokens: maxTokens) }
        var lastError: FormatterError = .emptyResponse
        for model in models {
            do {
                return try await Self.askGemini(model: model, system: system, user: user, key: key, maxTokens: maxTokens, quick: false)
            } catch let error as FormatterError {
                lastError = error
                guard noteFailure(error, of: model, quick: false) else { throw error }
            }
        }
        throw lastError
    }

    /// Spoken replies: asks the best model and, if it hasn't answered in 5 seconds (or has failed), starts the next one
    /// alongside it. The first answer wins, so one slow or overloaded model costs a few seconds, not its whole timeout.
    private func raceGemini(_ models: [String], system: String, user: String, key: String, maxTokens: Int) async throws -> String {
        enum Event: Sendable { case answered(String, String), failed(String, FormatterError), hedge(Int) }
        return try await withThrowingTaskGroup(of: Event.self) { group in
            var started = 0
            var running = 0
            var lastError: FormatterError = .emptyResponse
            func startNext() {
                guard started < models.count else { return }
                let model = models[started]
                started += 1
                running += 1
                group.addTask {
                    do { return .answered(model, try await Self.askGemini(model: model, system: system, user: user, key: key, maxTokens: maxTokens, quick: true)) }
                    catch let error as FormatterError { return .failed(model, error) }
                }
                let generation = started
                group.addTask { try await Task.sleep(for: .seconds(5)); return .hedge(generation) }
            }
            startNext()
            while let event = try await group.next() {
                switch event {
                case .answered(let model, let reply):
                    // Next time (even after a relaunch) start with the model that just answered.
                    UserDefaults.standard.set(model, forKey: Self.fastModelKey)
                    group.cancelAll()
                    return reply
                case .failed(let model, let error):
                    running -= 1
                    lastError = error
                    guard noteFailure(error, of: model, quick: true) else { group.cancelAll(); throw error }
                    startNext()
                case .hedge(let generation):
                    // Only if no other model has been started since this timer began.
                    if generation == started { startNext() }
                }
                if running == 0, started == models.count { throw lastError }
            }
            throw lastError
        }
    }

    /// Models that failed for now (out of quota, overloaded or too slow) and when to try them again. A model that
    /// isn't offered to this key at all is dropped from the list instead.
    private var cooldowns: [String: Date] = [:]

    /// Puts a failed model aside for as long as that kind of failure usually lasts. False means no other model can fix it
    /// (a bad key, say), so the request ends.
    private func noteFailure(_ error: FormatterError, of model: String, quick: Bool) -> Bool {
        let rest: TimeInterval
        switch error {
        case .modelUnavailable, .server(_, 404, _):
            geminiModels?.removeAll { $0 == model }
            forgetFastModel(model)
            return true
        // A dropped connection or a blank answer says nothing lasting about the model: just try the next one.
        case .network, .emptyResponse: return true
        case .rateLimited: rest = 15 * 60
        case .server(_, 500...599, _): rest = 2 * 60
        case .timedOut where quick: rest = 5 * 60
        default: return false
        }
        cooldowns[model] = Date().addingTimeInterval(rest)
        forgetFastModel(model)
        return true
    }

    /// The models to try, in order: this key's list (or the built-in one) without those that are resting, unless all of
    /// them are. Spoken replies start with the model that last answered quickly.
    private func geminiCandidates(quick: Bool) -> [String] {
        var models = geminiModels ?? Self.fallbackGeminiModels
        if quick { models = Self.quickGeminiOrder(models, preferred: UserDefaults.standard.string(forKey: Self.fastModelKey)) }
        let now = Date()
        let ready = models.filter { (cooldowns[$0] ?? .distantPast) <= now }
        return Array((ready.isEmpty ? models : ready).prefix(4))
    }

    /// Looks up this key's Gemini models ahead of the first spoken question, so that question doesn't wait for the list.
    /// Sends nothing for a student under 18 (the AI terms don't allow it) or with AI turned off.
    func prepare() {
        guard isEnabled, provider == .gemini, geminiModels == nil, !isPreparing, AgeGate.shared.meetsAIMinimum == true,
              let key = KeychainStore.get(service: Self.keychainService, account: Self.keychainAccount) else { return }
        isPreparing = true
        Task {
            let models = await Self.availableGeminiModels(key: key)
            if geminiModels == nil { geminiModels = models }
            isPreparing = false
        }
    }
    private var isPreparing = false

    /// The model remembered as fast for spoken replies, so a relaunch doesn't re-test slow ones.
    private static let fastModelKey = "assistant.fastGeminiModel"

    private func forgetFastModel(_ model: String) {
        if UserDefaults.standard.string(forKey: Self.fastModelKey) == model {
            UserDefaults.standard.removeObject(forKey: Self.fastModelKey)
        }
    }

    /// Order for spoken replies, where waiting costs more than polish: the model that last answered quickly first,
    /// then older stable full-size models (the newest are the busiest and have hung for 40 s), then lite models,
    /// with previews and the "-latest" aliases (which point at the newest model) last.
    nonisolated static func quickGeminiOrder(_ models: [String], preferred: String?) -> [String] {
        func version(_ name: String) -> Double {
            let digits = name.dropFirst("gemini-".count).prefix { $0.isNumber || $0 == "." }
            return Double(digits) ?? .greatestFiniteMagnitude
        }
        func tier(_ name: String) -> Int {
            if name.hasSuffix("-latest") || name.contains("preview") || name.contains("exp") { return 2 }
            return name.contains("lite") ? 1 : 0
        }
        let ordered = models.sorted { a, b in
            if tier(a) != tier(b) { return tier(a) < tier(b) }
            return version(a) < version(b)
        }
        guard let preferred, ordered.contains(preferred) else { return ordered }
        return [preferred] + ordered.filter { $0 != preferred }
    }

    nonisolated private static func askGemini(model: String, system: String, user: String, key: String, maxTokens: Int, quick: Bool) async throws -> String {
        func attempt(thinkingMinimal: Bool) async throws -> (Data, Int) {
            var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!)
            request.httpMethod = "POST"
            request.timeoutInterval = quick ? 7 : (maxTokens > 400 ? 60 : 30)
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            // Roomy limit: newer Gemini models spend part of it thinking before they answer.
            var config: [String: Any] = ["maxOutputTokens": max(1024, maxTokens * 2)]
            // A spoken reply gains nothing from long reasoning, and it adds seconds of silence.
            if thinkingMinimal { config["thinkingConfig"] = ["thinkingLevel": "minimal"] }
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "systemInstruction": ["parts": [["text": system]]],
                "contents": [["role": "user", "parts": [["text": user]]]],
                "generationConfig": config,
            ])
            return try await send(request)
        }

        var (data, status) = try await attempt(thinkingMinimal: quick)
        // Some models don't accept that setting (HTTP 400); ask again without it.
        if quick, status == 400 { (data, status) = try await attempt(thinkingMinimal: false) }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard status == 200 else { throw geminiError(status: status, json: json) }
        let candidate = (json?["candidates"] as? [[String: Any]])?.first
        let parts = (candidate?["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
        let text = parts.filter { ($0["thought"] as? Bool) != true }.compactMap { $0["text"] as? String }.joined()
        // A blank answer (blocked, or all of the limit spent thinking) is a failure, so the next model gets its turn
        // instead of the blank one winning the race.
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw FormatterError.emptyResponse }
        return text
    }

    /// Turns Google's error into what the student should do. Google's own text stays out of the UI; its
    /// machine-readable reason picks the message.
    nonisolated static func geminiError(status: Int, json: [String: Any]?) -> FormatterError {
        let error = json?["error"] as? [String: Any]
        let message = (error?["message"] as? String) ?? ""
        let details = error?["details"] as? [[String: Any]] ?? []
        let reasons = Set(details.compactMap { $0["reason"] as? String })
        let blocked = ["API_KEY_SERVICE_BLOCKED", "API_KEY_HTTP_REFERRER_BLOCKED", "API_KEY_IP_ADDRESS_BLOCKED",
                       "API_KEY_IOS_APP_BLOCKED", "API_KEY_ANDROID_APP_BLOCKED"]

        if reasons.contains("API_KEY_INVALID") || (status == 400 && message.localizedCaseInsensitiveContains("api key not valid")) {
            return .invalidKey(.gemini)
        }
        if reasons.contains("SERVICE_DISABLED") {
            return .keyBlocked(.gemini, "The Gemini API is turned off for this key's Google Cloud project. Create a key in Google AI Studio, or turn on the Generative Language API for that project.")
        }
        let fix = "Create a new key at aistudio.google.com/apikey and paste it in Settings, or change this key in Google Cloud Console › APIs & Services › Credentials."
        if reasons.contains("API_KEY_SERVICE_BLOCKED") {
            return .keyBlocked(.gemini, "This key isn't allowed to use the Gemini API: its API restrictions leave out the Generative Language API (common for Firebase or Maps keys). \(fix)")
        }
        if reasons.contains("API_KEY_HTTP_REFERRER_BLOCKED") {
            return .keyBlocked(.gemini, "This key only works on certain websites, so a Mac app can't use it. \(fix) Set Application restrictions to None.")
        }
        if reasons.contains("API_KEY_IP_ADDRESS_BLOCKED") {
            return .keyBlocked(.gemini, "This key only works from certain IP addresses. \(fix) Set Application restrictions to None.")
        }
        if !reasons.isDisjoint(with: blocked) {
            return .keyBlocked(.gemini, "This key only works in a phone app, so a Mac app can't use it. \(fix) Set Application restrictions to None.")
        }
        if status == 400 && message.localizedCaseInsensitiveContains("location is not supported") {
            return .keyBlocked(.gemini, "Gemini isn't available where you are, so Google refused the request.")
        }
        switch status {
        case 401: return .invalidKey(.gemini)
        case 403: return .modelUnavailable(.gemini)
        case 429: return .rateLimited(.gemini)
        default: return .server(.gemini, status: status, message: message)
        }
    }

    /// Used when the model list can't be fetched.
    nonisolated static let fallbackGeminiModels = [
        "gemini-3.5-flash", "gemini-3.6-flash", "gemini-3.7-flash", "gemini-3.8-flash",
        "gemini-3.5-flash-lite", "gemini-3.1-flash-lite", "gemini-2.5-flash",
    ]

    /// Flash models this key can call with `generateContent`, newest stable full-size model first.
    nonisolated private static func availableGeminiModels(key: String) async -> [String] {
        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=200")!)
        request.timeoutInterval = 5 // the built-in list takes over if this is slow
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        guard let response = try? await send(request), response.1 == 200,
              let json = (try? JSONSerialization.jsonObject(with: response.0)) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else { return fallbackGeminiModels }

        let names = models.compactMap { model -> String? in
            guard let name = model["name"] as? String,
                  (model["supportedGenerationMethods"] as? [String])?.contains("generateContent") == true else { return nil }
            return name.hasPrefix("models/") ? String(name.dropFirst("models/".count)) : name
        }
        let ranked = rankedGeminiModels(names)
        return ranked.isEmpty ? fallbackGeminiModels : ranked
    }

    nonisolated static func rankedGeminiModels(_ names: [String]) -> [String] {
        let excluded = ["image", "tts", "audio", "live", "embed", "computer-use", "robotics", "aqa", "learnlm"]
        func version(_ name: String) -> Double {
            let digits = name.dropFirst("gemini-".count).prefix { $0.isNumber || $0 == "." }
            return Double(digits) ?? 0
        }
        func isUnstable(_ name: String) -> Bool { name.contains("preview") || name.contains("exp") }
        return names
            .filter { $0.hasPrefix("gemini-") && $0.contains("flash") && !excluded.contains(where: $0.contains) }
            .sorted { a, b in
                if isUnstable(a) != isUnstable(b) { return !isUnstable(a) }
                if a.contains("lite") != b.contains("lite") { return !a.contains("lite") }
                return version(a) > version(b)
            }
    }

    // MARK: Transport

    nonisolated private static func send(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            let (data, response) = try await SecureNetwork.session.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError where error.code == .timedOut {
            throw FormatterError.timedOut
        } catch {
            throw FormatterError.network(error.localizedDescription)
        }
    }
}
