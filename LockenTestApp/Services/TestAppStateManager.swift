import SwiftUI
import Combine
import EventKit
import AVFoundation

// MARK: - State Architecture: Isolated Local Models

public struct TestMilestone: Identifiable, Codable, Equatable {
    public var id: UUID
    public var text: String
    public var isDone: Bool

    public init(id: UUID = UUID(), text: String, isDone: Bool = false) {
        self.id = id
        self.text = text
        self.isDone = isDone
    }
}

public struct TestProjectNote: Identifiable, Codable, Equatable {
    public var id: UUID
    public var title: String
    public var body: String
    public var updatedAt: Date

    public init(id: UUID = UUID(), title: String = "", body: String = "", updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.body = body
        self.updatedAt = updatedAt
    }
}

@MainActor
public class TestAppStateManager: ObservableObject {
    public static let shared = TestAppStateManager()

    // Active Navigation Tab
    @Published public var selectedTab: String = "dashboard" { // dashboard, focus, habits, calendar, notes, settings
        didSet {
            // While a session runs, Home isn't shown: asking for it (the sidebar, opening the app) lands on Focus.
            if isTimerActive, selectedTab == "dashboard" || selectedTab == "new" { selectedTab = "focus" }
            isCountdownPresented = false
            // Leaving mid-transition still starts the session, just without pulling the user back to the timer.
            if isSessionIntroPlaying { finishSessionIntro(presentCountdown: false) }
        }
    }
    /// The full-page focus countdown; shown whenever a session starts or resumes, hidden when navigating to a tab.
    @Published public var isCountdownPresented = false
    /// The papers transition (Resources/Web/papers.html) that plays between starting a session and its timer.
    @Published public private(set) var isSessionIntroPlaying = false
    private var introWorkspaceApp: String?
    @Published public var searchQuery: String = ""

    // Shield & Enclave
    /// The Focus Shield: while on, sessions quit distracting apps and close blocked browser tabs.
    @Published public var isShieldActive: Bool = true {
        didSet { if isShieldActive != oldValue { updateSessionIntegrations(); saveRunningSession() } }
    }
    @Published public var isLocalOnlyMode: Bool = true

    // Apple Calendar & Reminders — real EventKit access (triggers the macOS permission prompt)
    public enum AppleCalendarStatus: Equatable {
        case disconnected
        case connected
        case denied
    }
    @Published public private(set) var appleCalendarStatus: AppleCalendarStatus = .disconnected
    private let appleCalendarLinkedKey = "appleCalendar.linked"

    public struct AppleCalendarEvent: Identifiable, Equatable {
        public let id: String
        public let title: String
        public let start: Date
        public let end: Date
        public let isAllDay: Bool
        public let calendarTitle: String
        public let color: Color
    }

    public enum ReminderPriority: String, CaseIterable, Sendable {
        case none = "None", low = "Low", medium = "Medium", high = "High"

        /// EventKit's scale: 0 none, 1–4 high, 5 medium, 6–9 low.
        var ekValue: Int {
            switch self {
            case .none: return 0
            case .high: return 1
            case .medium: return 5
            case .low: return 9
            }
        }

        init(ekValue: Int) {
            switch ekValue {
            case 1...4: self = .high
            case 5: self = .medium
            case 6...9: self = .low
            default: self = .none
            }
        }
    }

    public enum ReminderRepeat: String, CaseIterable, Sendable {
        case never = "Never", daily = "Daily", weekly = "Weekly", monthly = "Monthly", yearly = "Yearly"

        var frequency: EKRecurrenceFrequency? {
            switch self {
            case .never: return nil
            case .daily: return .daily
            case .weekly: return .weekly
            case .monthly: return .monthly
            case .yearly: return .yearly
            }
        }

        init(_ frequency: EKRecurrenceFrequency?) {
            switch frequency {
            case .daily: self = .daily
            case .weekly: self = .weekly
            case .monthly: self = .monthly
            case .yearly: self = .yearly
            default: self = .never
            }
        }
    }

    /// A list in the Reminders app.
    public struct ReminderList: Identifiable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let color: Color
    }

    public struct AppleReminder: Identifiable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let notes: String
        public let due: Date?
        /// False for date-only reminders, so the time isn't shown.
        public let hasDueTime: Bool
        public let listID: String
        public let listTitle: String
        public let color: Color
        public let priority: ReminderPriority
        public let repeats: ReminderRepeat
        public let hasAlert: Bool
        public let url: String
        public let isCompleted: Bool
        public let completedAt: Date?
    }

    /// Everything the reminder editor can change; `id` is nil for a new reminder.
    public struct ReminderDraft: Identifiable, Equatable {
        /// Identifies this editing session (for `.sheet(item:)`), not the reminder.
        public let id = UUID()
        public var reminderID: String?
        public var title = ""
        public var notes = ""
        public var listID = ""
        public var hasDate = false
        public var date = Date()
        public var hasTime = false
        public var repeats = ReminderRepeat.never
        public var hasAlert = false
        public var priority = ReminderPriority.none
        public var url = ""

        public init(listID: String, title: String = "") {
            self.listID = listID
            self.title = title
            // New reminders with a date default to the next whole hour.
            let calendar = Calendar.current
            let hour = calendar.date(bySettingHour: calendar.component(.hour, from: Date()), minute: 0, second: 0, of: Date()) ?? Date()
            date = calendar.date(byAdding: .hour, value: 1, to: hour) ?? Date()
        }

        public init(_ reminder: AppleReminder) {
            reminderID = reminder.id
            title = reminder.title
            notes = reminder.notes
            listID = reminder.listID
            hasDate = reminder.due != nil
            date = reminder.due ?? Date()
            hasTime = reminder.hasDueTime
            repeats = reminder.repeats
            hasAlert = reminder.hasAlert
            priority = reminder.priority
            url = reminder.url
        }
    }

    /// Events from today through the next 7 days (read from the Mac's calendars while connected).
    @Published public private(set) var upcomingEvents: [AppleCalendarEvent] = []
    /// Every incomplete reminder in the Reminders app, soonest due first (undated ones last).
    @Published public private(set) var openReminders: [AppleReminder] = []
    @Published public private(set) var hasReminderAccess = false
    /// The user turned Reminders access off for Locken; only System Settings can turn it back on.
    @Published public private(set) var isReminderAccessDenied = false
    /// Reminders completed in the last 30 days, newest first (only loaded while `showsCompletedReminders`).
    @Published public private(set) var completedReminders: [AppleReminder] = []
    @Published public var showsCompletedReminders = false {
        didSet { if showsCompletedReminders != oldValue { loadReminders() } }
    }
    @Published public private(set) var reminderLists: [ReminderList] = []
    @Published public private(set) var defaultReminderListID: String?
    /// The last Reminders error, shown on the Notes & Reminders page.
    @Published public var reminderError: String?
    /// Recreated after access is granted: a store made before the grant can keep returning nothing.
    private var eventStore = EKEventStore()
    private var eventStoreObserver: NSObjectProtocol?


    // Focus Session
    @Published public var focusGoal: String = ""
    /// Set once the user has said what this session is for (Dashboard setup or a Canvas assignment).
    @Published public private(set) var isGoalDefined = false
    @Published public var timerTotalSeconds: Int = 25 * 60
    @Published public var timerSecondsRemaining: Int = 25 * 60 {
        // Any change other than the clock's own tick (a new session, adaptive time) moves the end time.
        didSet {
            guard !isApplyingTick, isTimerActive else { return }
            sessionEndDate = Date().addingTimeInterval(TimeInterval(timerSecondsRemaining))
            saveRunningSession()
        }
    }
    /// When the running countdown reaches zero. The timer counts from the clock, not from ticks, so it stays exact
    /// on any page, in the background, or when macOS slows the app down.
    private var sessionEndDate: Date?
    private var isApplyingTick = false
    /// What a finished session achieved, for the celebration. nil when there's nothing to celebrate.
    public struct CompletedSession: Identifiable, Equatable {
        public let id = UUID()
        public let goal: String
        public let minutes: Int
        public let stepsDone: Int
        public let stepsTotal: Int
        public let distractionsBlocked: Int
        public let endedEarly: Bool
    }
    @Published public var completedSession: CompletedSession?
    /// The "Why are you pausing?" page: Pause asks first, and the timer keeps running until the student confirms.
    @Published public var isPauseReasonPresented = false
    /// The start-session pop-up on the Focus page (a centered overlay, not a system sheet).
    @Published public var isSessionSetupPresented = false
    public enum PauseReason: String, CaseIterable, Sendable {
        case needBreak = "Need a break"
        case interrupted = "Interrupted"
        case lostFocus = "Lost focus"
        case finished = "Finished early"
        case other = "Other"
    }
    /// Distractions the Shield closed in the current session.
    public private(set) var sessionDistractions = 0
    /// The length the student picked; adaptive time stays within twice this.
    @Published public private(set) var plannedTotalSeconds: Int = 25 * 60
    /// Adaptive time: each check-in re-estimates the time left from how far into the goal the student is.
    @Published public var isAdaptiveTimeOn: Bool = UserDefaults.standard.bool(forKey: "focus.adaptiveTime") {
        didSet { UserDefaults.standard.set(isAdaptiveTimeOn, forKey: "focus.adaptiveTime") }
    }
    /// What the last check-in changed, shown under the timer.
    @Published public private(set) var lastTimeAdjustment: String?
    @Published public var isTimerActive: Bool = false {
        didSet {
            guard isTimerActive != oldValue else { return }
            sessionEndDate = isTimerActive ? Date().addingTimeInterval(TimeInterval(timerSecondsRemaining)) : nil
            updateSessionIntegrations()
            if isTimerActive {
                saveRunningSession()
                // A session started from Home moves to Focus at once; a countdown page that's showing stays up.
                if selectedTab == "dashboard" || selectedTab == "new" {
                    let countdown = isCountdownPresented
                    selectedTab = "focus"
                    isCountdownPresented = countdown
                }
            } else {
                forgetRunningSession()
            }
        }
    }
    /// Focus history, saved on this Mac per account (`stats-<user id>.json`), so it survives relaunches.
    public struct FocusStats: Codable, Equatable {
        /// Keyed by `yyyy-MM-dd` (`ScreenUsageTracker.dayKey`).
        public var focusSecondsByDay: [String: Int] = [:]
        public var sessionsByDay: [String: Int] = [:]
        /// Times each workspace app was chosen for a session that actually started.
        public var appUsageCounts: [String: Int] = [:]
        /// Distractions the Shield closed during sessions (apps quit and blocked tabs), per day.
        public var distractionsByDay: [String: Int] = [:]
        /// How often each pause reason was chosen. Optional so stats saved before it existed still load.
        public var pauseReasons: [String: Int]?
        /// What the student typed for "Other", newest last (kept to the last 50).
        public var otherPauseNotes: [String]?
    }
    @Published public private(set) var stats = FocusStats()
    private var lastStatsSave = Date.distantPast

    private static var todayKey: String { ScreenUsageTracker.dayKey(Date()) }
    /// This week's day keys, Monday first.
    private var weekKeys: [String] {
        let monday = HabitMath.weekStart(Date())
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: monday).map(ScreenUsageTracker.dayKey) }
    }
    public var totalFocusSecondsToday: Int { stats.focusSecondsByDay[Self.todayKey] ?? 0 }
    public var sessionsStartedToday: Int { stats.sessionsByDay[Self.todayKey] ?? 0 }
    /// Focus seconds for each day of this week, Monday first.
    public var focusSecondsThisWeek: [Int] { weekKeys.map { stats.focusSecondsByDay[$0] ?? 0 } }
    /// The timer page's checklist of small steps for the current session. Saved only on this Mac, per account:
    /// `~/Library/Application Support/LockenTestApp/milestones-<user id>.json`.
    @Published public private(set) var milestones: [TestMilestone] = []
    /// True while a new session's milestones are being created.
    @Published public private(set) var isCreatingMilestones = false
    /// Who wrote the current steps, or why the AI couldn't, shown under the milestones heading.
    @Published public private(set) var milestonesNote: String?
    /// The signed-in account whose milestones and notes are loaded.
    private var accountUserID: String?
    private var milestonesTask: Task<Void, Never>?

    // Notes: the user's own, newest first. Saved only on this Mac, per account (`notes-<user id>.json`).
    @Published public private(set) var notes: [TestProjectNote] = []
    /// The note open in the editor on the Notes & Reminders page.
    @Published public var selectedNoteId: UUID?

    /// The workspace app chosen most often for sessions that actually started.
    public var mostUsedApp: String? {
        stats.appUsageCounts.max(by: { $0.value < $1.value })?.key
    }

    /// Distractions the Shield really blocked this week (apps quit and tabs closed), Monday first.
    public var distractionAttemptsByDay: [Int] { weekKeys.map { stats.distractionsByDay[$0] ?? 0 } }
    public var distractionAttemptsThisWeek: Int { distractionAttemptsByDay.reduce(0, +) }

    /// Called by the Shield each time it closes something during a session.
    public func recordDistractions(_ count: Int) {
        guard count > 0 else { return }
        stats.distractionsByDay[Self.todayKey, default: 0] += count
        sessionDistractions += count
        saveRunningSession()
        saveStats()
    }

    private func saveStats() {
        lastStatsSave = Date()
        // Day-by-day history is kept for one year; older days are dropped.
        if let cutoffDate = Calendar.current.date(byAdding: .day, value: -366, to: Date()) {
            let cutoff = ScreenUsageTracker.dayKey(cutoffDate)
            stats.focusSecondsByDay = stats.focusSecondsByDay.filter { $0.key >= cutoff }
            stats.sessionsByDay = stats.sessionsByDay.filter { $0.key >= cutoff }
            stats.distractionsByDay = stats.distractionsByDay.filter { $0.key >= cutoff }
        }
        save(stats, to: "stats")
    }

    // Readiness Factor: derived from real milestone completion + habit consistency,
    // mirroring the production formula's shape (a base score adjusted by live signals).
    /// Today's momentum from real activity only: focus time against a one-hour target, milestones done, and habits
    /// checked off today. Each part counts only when it has data; nil when there's nothing to measure yet.
    public var computedReadinessScore: Int? {
        var parts: [Double] = []
        if totalFocusSecondsToday > 0 { parts.append(min(1, Double(totalFocusSecondsToday) / 3600)) }
        if !milestones.isEmpty {
            parts.append(Double(milestones.filter { $0.isDone }.count) / Double(milestones.count))
        }
        let habitStore = HabitStore.shared
        let today = Date()
        let dueToday = habitStore.activeHabits.filter { HabitMath.isScheduled($0, on: today) }
        if !dueToday.isEmpty {
            parts.append(Double(dueToday.filter { habitStore.isDone($0, on: today) }.count) / Double(dueToday.count))
        }
        guard !parts.isEmpty else { return nil }
        return Int((parts.reduce(0, +) / Double(parts.count) * 100).rounded())
    }

    public var readinessStateLabel: String {
        guard let score = computedReadinessScore else { return "No activity yet" }
        if score >= 80 { return "\(score)% Strong" }
        if score >= 50 { return "\(score)% Building" }
        if score > 0 { return "\(score)% Getting started" }
        return "0% Not started"
    }

    private var timerCancellable: AnyCancellable?

    public init() {
        setupTimer()
        AppBlockingManager.shared.onBlock = { [weak self] count in self?.recordDistractions(count) }
        // A closed YouTube video opens the "is it for school?" check instead of leaving the student stuck.
        AppBlockingManager.shared.onYouTubeBlocked = { url in VideoCheckManager.shared.present(url: url) }
        refreshAppleCalendarStatus()
        // Keep the lists live when events or reminders change in Calendar/Reminders (or sync in).
        eventStoreObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAppleCalendarStatus() }
        }
    }

    /// Asks macOS for full calendar and reminders access (shows the system prompt the first time).
    public func connectAppleCalendar() async {
        let eventsGranted = (try? await eventStore.requestFullAccessToEvents()) ?? false
        _ = try? await eventStore.requestFullAccessToReminders()
        eventStore = EKEventStore()
        UserDefaults.standard.set(eventsGranted, forKey: appleCalendarLinkedKey)
        refreshAppleCalendarStatus()
    }

    /// Stops Locken using the calendar; the macOS permission itself can only be revoked in System Settings.
    public func disconnectAppleCalendar() {
        UserDefaults.standard.set(false, forKey: appleCalendarLinkedKey)
        refreshAppleCalendarStatus()
    }

    public func refreshAppleCalendarStatus() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            appleCalendarStatus = UserDefaults.standard.bool(forKey: appleCalendarLinkedKey) ? .connected : .disconnected
        case .denied, .restricted, .writeOnly:
            appleCalendarStatus = .denied
        default:
            appleCalendarStatus = .disconnected
        }
        if appleCalendarStatus == .connected {
            loadAppleCalendarData()
        } else {
            upcomingEvents = []
        }
        // Reminders have their own permission and show on the Notes & Reminders page even without the calendar.
        loadReminders()
    }

    /// Asks macOS for Reminders access (shows the system prompt the first time).
    public func connectReminders() async {
        _ = try? await eventStore.requestFullAccessToReminders()
        eventStore = EKEventStore()
        loadReminders()
    }

    /// Reloads reminders and lists from the Reminders app.
    public func refreshReminders() {
        loadReminders()
    }

    /// Ticks a reminder off in the Reminders app, or back on.
    public func setReminderCompleted(id: String, _ completed: Bool) {
        guard let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else { return }
        reminder.isCompleted = completed
        if commit(reminder) {
            if completed { openReminders.removeAll { $0.id == id } } else { completedReminders.removeAll { $0.id == id } }
            loadReminders()
        }
    }

    /// Adds a reminder with just a title, to `listID` or the default list.
    public func addReminder(title: String, listID: String? = nil) {
        var draft = ReminderDraft(listID: listID ?? defaultReminderListID ?? "", title: title)
        draft.hasDate = false
        saveReminder(draft)
    }

    /// Creates or updates a reminder in the Reminders app from the editor. Returns false if it couldn't be saved.
    @discardableResult
    public func saveReminder(_ draft: ReminderDraft) -> Bool {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, hasReminderAccess else { return false }

        let reminder: EKReminder
        if let id = draft.reminderID {
            guard let existing = eventStore.calendarItem(withIdentifier: id) as? EKReminder else {
                reminderError = "That reminder no longer exists in Reminders."
                loadReminders()
                return false
            }
            reminder = existing
        } else {
            reminder = EKReminder(eventStore: eventStore)
        }
        guard let list = eventStore.calendar(withIdentifier: draft.listID) ?? writableDefaultList() else {
            reminderError = "There's no Reminders list to save into. Create one in the Reminders app first."
            return false
        }

        reminder.title = title
        let notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        reminder.notes = notes.isEmpty ? nil : notes
        reminder.calendar = list
        reminder.priority = draft.priority.ekValue

        let calendar = Calendar.current
        if draft.hasDate {
            // Date-only reminders are "floating" (no time zone), like the Reminders app's own.
            reminder.dueDateComponents = calendar.dateComponents(
                draft.hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day],
                from: draft.date
            )
        } else {
            reminder.dueDateComponents = nil
        }

        for alarm in reminder.alarms ?? [] { reminder.removeAlarm(alarm) }
        if draft.hasDate && draft.hasAlert {
            // Date-only reminders alert at 9:00, as in the Reminders app.
            let fireDate = draft.hasTime ? draft.date : (calendar.date(bySettingHour: 9, minute: 0, second: 0, of: draft.date) ?? draft.date)
            reminder.addAlarm(EKAlarm(absoluteDate: fireDate))
        }

        for rule in reminder.recurrenceRules ?? [] { reminder.removeRecurrenceRule(rule) }
        if draft.hasDate, let frequency = draft.repeats.frequency {
            reminder.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: frequency, interval: 1, end: nil))
        }

        let link = draft.url.trimmingCharacters(in: .whitespacesAndNewlines)
        if link.isEmpty {
            reminder.url = nil
        } else {
            reminder.url = URL(string: link.contains("://") ? link : "https://\(link)")
        }

        guard commit(reminder) else { return false }
        loadReminders()
        return true
    }

    public func deleteReminder(id: String) {
        guard let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else { return }
        do {
            try eventStore.remove(reminder, commit: true)
            reminderError = nil
            openReminders.removeAll { $0.id == id }
            completedReminders.removeAll { $0.id == id }
        } catch {
            reminderError = "Couldn't delete the reminder: \(error.localizedDescription)"
        }
    }

    /// Creates a new list in the Reminders app, in the same account as the default list.
    @discardableResult
    public func createReminderList(title: String) -> String? {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, hasReminderAccess else { return nil }
        let source = eventStore.defaultCalendarForNewReminders()?.source
            ?? eventStore.sources.first { $0.sourceType == .calDAV }
            ?? eventStore.sources.first { $0.sourceType == .local }
        guard let source else {
            reminderError = "Couldn't find a Reminders account to add the list to."
            return nil
        }
        let list = EKCalendar(for: .reminder, eventStore: eventStore)
        list.title = name
        list.source = source
        do {
            try eventStore.saveCalendar(list, commit: true)
            reminderError = nil
            loadReminders()
            return list.calendarIdentifier
        } catch {
            reminderError = "Couldn't create the list: \(error.localizedDescription)"
            return nil
        }
    }

    private func writableDefaultList() -> EKCalendar? {
        eventStore.defaultCalendarForNewReminders()
            ?? eventStore.calendars(for: .reminder).first { $0.allowsContentModifications }
    }

    private func commit(_ reminder: EKReminder) -> Bool {
        do {
            try eventStore.save(reminder, commit: true)
            reminderError = nil
            return true
        } catch {
            reminderError = "Couldn't save to Reminders: \(error.localizedDescription)"
            return false
        }
    }

    /// Adds an event to the default calendar. Only called after the student confirms it on the Assistant tab.
    public func addCalendarEvent(title: String, start: Date, minutes: Int) throws {
        guard appleCalendarStatus == .connected, let calendar = eventStore.defaultCalendarForNewEvents else {
            throw EKError(.calendarIsImmutable)
        }
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = start
        event.endDate = start.addingTimeInterval(TimeInterval(minutes * 60))
        event.calendar = calendar
        try eventStore.save(event, span: .thisEvent, commit: true)
        loadAppleCalendarData()
    }

    private func loadAppleCalendarData() {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        if let end = calendar.date(byAdding: .day, value: 7, to: startOfToday) {
            let now = Date()
            let predicate = eventStore.predicateForEvents(withStart: startOfToday, end: end, calendars: nil)
            upcomingEvents = eventStore.events(matching: predicate)
                .filter { $0.endDate > now }
                .sorted { $0.startDate < $1.startDate }
                .prefix(200)
                .map { event in
                    AppleCalendarEvent(
                        // Recurring events share an identifier, so pair it with the occurrence's start.
                        id: "\(event.eventIdentifier ?? UUID().uuidString)-\(event.startDate.timeIntervalSince1970)",
                        title: event.title ?? "Untitled",
                        start: event.startDate,
                        end: event.endDate,
                        isAllDay: event.isAllDay,
                        calendarTitle: event.calendar.title,
                        color: Color(nsColor: event.calendar.color ?? .systemGray)
                    )
                }
        }

    }

    private func loadReminders() {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        hasReminderAccess = status == .fullAccess
        isReminderAccessDenied = status == .denied || status == .restricted || status == .writeOnly
        guard hasReminderAccess else {
            openReminders = []
            completedReminders = []
            reminderLists = []
            return
        }

        reminderLists = eventStore.calendars(for: .reminder)
            .map { ReminderList(id: $0.calendarIdentifier, title: $0.title, color: Color(nsColor: $0.color ?? .systemGray)) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        defaultReminderListID = writableDefaultList()?.calendarIdentifier

        let open = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        eventStore.fetchReminders(matching: open) { [weak self] reminders in
            let items = (reminders ?? []).map(Self.appleReminder)
                .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
            Task { @MainActor in self?.openReminders = items }
        }

        guard showsCompletedReminders else {
            completedReminders = []
            return
        }
        let monthAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())
        let done = eventStore.predicateForCompletedReminders(withCompletionDateStarting: monthAgo, ending: nil, calendars: nil)
        eventStore.fetchReminders(matching: done) { [weak self] reminders in
            let items = (reminders ?? []).map(Self.appleReminder)
                .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
            Task { @MainActor in self?.completedReminders = Array(items.prefix(100)) }
        }
    }

    nonisolated private static func appleReminder(_ reminder: EKReminder) -> AppleReminder {
        let components = reminder.dueDateComponents
        return AppleReminder(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "Untitled",
            notes: reminder.notes ?? "",
            due: components.flatMap { Calendar.current.date(from: $0) },
            hasDueTime: components?.hour != nil,
            listID: reminder.calendar.calendarIdentifier,
            listTitle: reminder.calendar.title,
            color: Color(nsColor: reminder.calendar.color ?? .systemGray),
            priority: ReminderPriority(ekValue: reminder.priority),
            repeats: ReminderRepeat(reminder.recurrenceRules?.first?.frequency),
            hasAlert: !(reminder.alarms ?? []).isEmpty,
            url: reminder.url?.absoluteString ?? "",
            isCompleted: reminder.isCompleted,
            completedAt: reminder.completionDate
        )
    }

    private func setupTimer() {
        timerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, self.isTimerActive, let end = self.sessionEndDate else { return }
                let previous = self.timerSecondsRemaining
                let remaining = max(0, Int(end.timeIntervalSinceNow.rounded(.up)))
                if remaining < previous {
                    self.isApplyingTick = true
                    self.timerSecondsRemaining = remaining
                    self.isApplyingTick = false
                    self.stats.focusSecondsByDay[Self.todayKey, default: 0] += previous - remaining
                    // Saved every 30 seconds while the timer runs, and whenever it stops.
                    if Date().timeIntervalSince(self.lastStatsSave) >= 30 { self.saveStats() }
                    // Check-ins follow the session clock: every 30 min, or halfway through a session of 30 min or less.
                    // Every second passed is checked, so a check-in isn't skipped when ticks arrive late.
                    let total = self.timerTotalSeconds
                    let before = total - previous, after = total - remaining
                    if after > before {
                        for elapsed in (before + 1)...after {
                            CheckInWindowManager.shared.sessionTick(elapsedSeconds: elapsed, totalSeconds: total)
                        }
                    }
                }
                if remaining == 0 { self.completeSession() }
            }
    }

    /// Starts or stops the system integrations with the session: Focus (Do Not Disturb, once its two
    /// shortcuts exist), the distraction blocker (only while the Focus Shield is on) and notch check-ins.
    private func updateSessionIntegrations() {
        if isTimerActive {
            CheckInWindowManager.shared.startSession()
            if isShieldActive {
                AppBlockingManager.shared.start()
            } else {
                AppBlockingManager.shared.stop()
            }
            Task {
                let focus = FocusModeManager.shared
                await focus.refreshSetupState()
                if focus.setupState == .ready { await focus.activate() }
            }
        } else {
            saveStats()
            CheckInWindowManager.shared.endSession()
            AppBlockingManager.shared.stop()
            Task { await FocusModeManager.shared.deactivate() }
        }
    }

    /// Ends the session as done (the countdown reached zero, or "Finished early") and shows the celebration.
    public func completeSession(endedEarly: Bool = false) {
        guard isTimerActive || isGoalDefined else { return }
        let minutes = (timerTotalSeconds - timerSecondsRemaining) / 60
        isTimerActive = false
        // Finished: the next session needs its own goal (and its own videos).
        isGoalDefined = false
        AppBlockingManager.shared.allowedVideoIDs = []
        // Habits set to "done after a focus session" tick themselves.
        HabitStore.shared.recordFocusSession(minutes: minutes)
        completedSession = CompletedSession(
            goal: focusGoal,
            minutes: minutes,
            stepsDone: milestones.filter(\.isDone).count,
            stepsTotal: milestones.count,
            distractionsBlocked: sessionDistractions,
            endedEarly: endedEarly
        )
    }

    /// Closes the celebration and readies the timer for the next session.
    public func dismissCelebration() {
        completedSession = nil
        resetTimer()
        isCountdownPresented = false
    }

    /// Pauses once the student has said why. "Finished early" ends the session as done instead.
    /// Checks a typed "Other" pause reason reads like a real reason, not one letter or a keyboard mash.
    /// Returns what's wrong in plain words, or nil when it's fine. Runs on this Mac only.
    public nonisolated static func otherPauseReasonProblem(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let letters = trimmed.lowercased().filter(\.isLetter)
        if letters.count < 6 { return "Write a few words about why you're pausing." }
        if Set(letters).count < 4 { return "That doesn't look like a reason. Say what's going on." }
        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
        let vowelShare = Double(letters.filter { vowels.contains($0) }.count) / Double(letters.count)
        if vowelShare < 0.1 || vowelShare > 0.8 { return "That doesn't look like a reason. Say what's going on." }
        // Keyboard rows or the alphabet typed in order ("asdfgh", "qwerty", "abcdef").
        let runs = ["qwertyuiop", "asdfghjkl", "zxcvbnm", "abcdefghijklmnopqrstuvwxyz", "poiuytrewq", "lkjhgfdsa", "mnbvcxz"]
        let words = trimmed.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        let isKeyboardRun: (String) -> Bool = { word in word.count >= 3 && runs.contains(where: { $0.contains(word) }) }
        if isKeyboardRun(String(letters)) || words.allSatisfy(isKeyboardRun) {
            return "That doesn't look like a reason. Say what's going on."
        }
        // Real words: at least one word of 3+ letters that has a vowel, and no long consonant pile-ups.
        guard words.contains(where: { $0.count >= 3 && $0.contains(where: { vowels.contains($0) }) }) else {
            return "Write a few words about why you're pausing."
        }
        var consonantRun = 0
        for ch in letters {
            consonantRun = vowels.contains(ch) ? 0 : consonantRun + 1
            if consonantRun >= 6 { return "That doesn't look like a reason. Say what's going on." }
        }
        // The same character typed over and over ("aaaaaa", "hahahahaha" is fine as words, "jjjjjj" isn't).
        if trimmed.lowercased().contains(where: { ch in ch.isLetter && trimmed.lowercased().contains(String(repeating: ch, count: 4)) }) {
            return "That doesn't look like a reason. Say what's going on."
        }
        return nil
    }

    public func confirmPause(_ reason: PauseReason, note: String? = nil) {
        if reason == .other, Self.otherPauseReasonProblem(note ?? "") != nil { return }
        isPauseReasonPresented = false
        var reasons = stats.pauseReasons ?? [:]
        reasons[reason.rawValue, default: 0] += 1
        stats.pauseReasons = reasons
        if reason == .other, let note {
            let clean = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
            stats.otherPauseNotes = Array(((stats.otherPauseNotes ?? []) + [clean]).suffix(50))
        }
        if reason == .finished {
            completeSession(endedEarly: true)
        } else {
            isTimerActive = false
        }
        saveStats()
    }

    public func toggleTimer(workspaceApp: String? = nil) {
        // Pausing asks why first (after commitment mode's short wait); the timer keeps running until the
        // student confirms on that page.
        if isTimerActive {
            requestStop(.pause)
            return
        }
        if !isTimerActive {
            // A new session only begins once its goal is defined; from a menu or button, open the setup instead.
            guard isGoalDefined else {
                selectedTab = "dashboard"
                return
            }
            stats.sessionsByDay[Self.todayKey, default: 0] += 1
            if let app = workspaceApp {
                stats.appUsageCounts[app, default: 0] += 1
            }
            saveStats()
            isCountdownPresented = true
        }
        isTimerActive.toggle()
        // Focus mode just switched on.
        if isTimerActive { FocusSound.playOn() }
    }

    /// Sets the goal and a fresh countdown of `minutes`, then starts the timer (or keeps it running).
    /// A new session first plays the papers transition unless `playIntro` is false (Reduce Motion).
    public func startFocus(goal: String, minutes: Int, playIntro: Bool = true) {
        focusGoal = goal
        isGoalDefined = true
        timerTotalSeconds = minutes * 60
        timerSecondsRemaining = minutes * 60
        plannedTotalSeconds = minutes * 60
        lastTimeAdjustment = nil
        if !isTimerActive {
            sessionDistractions = 0
            completedSession = nil
            createMilestones(goal: goal, minutes: minutes, workspaceApp: nil)
            if playIntro { beginSessionIntro(workspaceApp: nil); return }
            toggleTimer()
        }
        isCountdownPresented = true
    }

    /// Starts a fresh countdown of `minutes` for `goal` (a Canvas assignment or the user's own goal).
    /// A new session first plays the papers transition unless `playIntro` is false (Reduce Motion).
    public func startSession(goal: String, minutes: Int, workspaceApp: String? = nil, playIntro: Bool = true) {
        focusGoal = goal
        isGoalDefined = true
        timerTotalSeconds = minutes * 60
        timerSecondsRemaining = minutes * 60
        plannedTotalSeconds = minutes * 60
        lastTimeAdjustment = nil
        if !isTimerActive {
            sessionDistractions = 0
            completedSession = nil
            createMilestones(goal: goal, minutes: minutes, workspaceApp: workspaceApp)
            if playIntro { beginSessionIntro(workspaceApp: workspaceApp); return }
            toggleTimer(workspaceApp: workspaceApp)
        }
    }

    /// Replaces the checklist with steps for a new session's goal: written by the AI when a key is set in
    /// Settings, otherwise a simple plan by time. Steps the user adds while this runs are kept.
    private func createMilestones(goal: String, minutes: Int, workspaceApp: String?) {
        milestonesTask?.cancel()
        milestones = []
        isCreatingMilestones = true
        let context = AITaskFormatter.Context(
            sessionMinutes: minutes,
            workspaceApp: workspaceApp,
            upcomingAssignments: CanvasAPIManager.shared.assignments
        )
        milestonesNote = nil
        milestonesTask = Task {
            let steps: [String]
            let note: String?
            do {
                steps = try await AITaskFormatter.shared.milestones(for: goal, context: context)
                note = AITaskFormatter.shared.provider.map { "Written by \($0.displayName) for your goal." }
            } catch {
                steps = Self.plannedMilestones(goal: goal, minutes: minutes)
                // Say why the AI didn't write them, unless AI is simply turned off.
                let reason = (error as? AITaskFormatter.FormatterError).flatMap { $0 == .disabled ? nil : $0.errorDescription }
                note = reason.map { "Planned by time. \($0)" }
            }
            guard !Task.isCancelled else { return }
            milestonesNote = note
            milestones = steps.map { TestMilestone(text: $0) } + milestones
            isCreatingMilestones = false
            saveMilestones()
        }
    }

    /// Steps for when no AI is available: plan, work on the goal (with a halfway check on long sessions), wrap up.
    nonisolated static func plannedMilestones(goal: String, minutes: Int) -> [String] {
        let subject = goal.count > 40 ? goal.prefix(38).trimmingCharacters(in: .whitespaces) + "…" : goal
        let edge = max(2, minutes / 10)
        var steps = ["Plan (first \(edge) min): decide what done looks like"]
        if minutes >= 50 {
            steps += [
                "Work on \(subject)",
                "Halfway (\(minutes / 2) min): check progress, adjust the plan",
                "Keep going on \(subject)",
            ]
        } else {
            steps.append("Work on \(subject)")
        }
        steps.append("Wrap up (last \(edge) min): check your work, note next steps")
        return steps
    }

    private func beginSessionIntro(workspaceApp: String?) {
        introWorkspaceApp = workspaceApp
        isSessionIntroPlaying = true
    }

    /// Ends the papers transition and starts the timer, so the countdown begins when the timer page appears.
    public func finishSessionIntro(presentCountdown: Bool = true) {
        guard isSessionIntroPlaying else { return }
        isSessionIntroPlaying = false
        let app = introWorkspaceApp
        introWorkspaceApp = nil
        if !isTimerActive { toggleTimer(workspaceApp: app) }
        if !presentCountdown { isCountdownPresented = false }
    }

    // MARK: Commitment mode

    /// What a student is trying to do to a running session.
    public enum CommitmentAction: Equatable {
        case pause, end, quit, shieldOff

        /// Seconds to wait before the action unlocks: a short breath for a pause, longer to give up the session.
        var waitSeconds: Int { self == .pause ? 10 : 20 }
    }

    /// With commitment mode on (the default), pausing, ending early or quitting Locken during a running session
    /// first shows a short countdown, so stopping is a decision rather than a reflex.
    @Published public var isCommitmentModeOn: Bool = UserDefaults.standard.object(forKey: "focus.commitmentMode") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isCommitmentModeOn, forKey: "focus.commitmentMode")
        }
    }
    /// The stop waiting behind the commitment countdown, shown by `CommitmentGateView`.
    @Published public var commitmentRequest: CommitmentAction?

    /// Pause, end or quit: straight away when no session is running or commitment mode is off, otherwise after
    /// the countdown.
    public func requestStop(_ action: CommitmentAction) {
        guard isTimerActive, isCommitmentModeOn else {
            performStop(action)
            return
        }
        commitmentRequest = action
    }

    /// The countdown finished and the student still chose to stop.
    public func confirmCommitment() {
        guard let action = commitmentRequest else { return }
        commitmentRequest = nil
        performStop(action)
    }

    /// The student chose to keep focusing.
    public func cancelCommitment() {
        commitmentRequest = nil
    }

    private func performStop(_ action: CommitmentAction) {
        switch action {
        case .pause:
            if isTimerActive { isPauseReasonPresented = true }
        case .end:
            completeSession(endedEarly: true)
        case .quit:
            AppQuit.isAllowed = true
            NSApplication.shared.terminate(nil)
        case .shieldOff:
            isShieldActive = false
        }
    }

    // MARK: Surviving a force quit

    /// The running session, saved per account (`session-<user id>.json`) so that a force quit, crash or restart
    /// doesn't end it: the next launch picks it up with the time it has left. Removed when the session stops.
    private struct SavedSession: Codable {
        var goal: String
        var endDate: Date
        var totalSeconds: Int
        var plannedSeconds: Int
        var shieldOn: Bool
        var distractions: Int
    }

    private func saveRunningSession() {
        guard isTimerActive, let end = sessionEndDate else { return }
        save(SavedSession(goal: focusGoal, endDate: end, totalSeconds: timerTotalSeconds, plannedSeconds: plannedTotalSeconds,
                          shieldOn: isShieldActive, distractions: sessionDistractions), to: "session")
    }

    /// The session stopped (paused, ended, reset): nothing to restore.
    private func forgetRunningSession() {
        if let url = accountFileURL("session") { try? FileManager.default.removeItem(at: url) }
    }

    /// Locken is quitting the normal way (through commitment mode, or with it off): the session ends with it.
    public func endRunningSessionForQuit() {
        forgetRunningSession()
    }

    /// Picks up a session that was running when Locken was force-quit, crashed or the Mac restarted, if it still
    /// has time left. The Shield, check-ins and Focus start again.
    private func restoreRunningSession() {
        guard !isTimerActive, let saved = load(SavedSession.self, from: "session") else { return }
        let remaining = Int(saved.endDate.timeIntervalSinceNow.rounded(.down))
        guard remaining >= 5 else {
            forgetRunningSession()
            return
        }
        focusGoal = saved.goal
        isGoalDefined = true
        plannedTotalSeconds = saved.plannedSeconds
        timerTotalSeconds = max(saved.totalSeconds, remaining)
        sessionDistractions = saved.distractions
        isShieldActive = saved.shieldOn
        completedSession = nil
        timerSecondsRemaining = remaining
        isTimerActive = true
    }

    public func resetTimer() {
        isTimerActive = false
        AppBlockingManager.shared.allowedVideoIDs = []
        timerTotalSeconds = plannedTotalSeconds
        timerSecondsRemaining = plannedTotalSeconds
        lastTimeAdjustment = nil
    }

    // MARK: Adaptive time

    /// Called with each check-in's answer. With adaptive time on, the time left becomes what the rest of the
    /// goal should take at the pace so far.
    public func applyCheckIn(progress: Int) {
        guard isAdaptiveTimeOn else { return }
        let elapsed = timerTotalSeconds - timerSecondsRemaining
        guard let remaining = Self.adaptedRemaining(
            elapsed: elapsed, remaining: timerSecondsRemaining, planned: plannedTotalSeconds, progress: progress
        ) else { return }
        let before = timerSecondsRemaining
        timerSecondsRemaining = remaining
        timerTotalSeconds = elapsed + remaining
        if remaining == 0 {
            lastTimeAdjustment = "You said you're done, so the session ended."
        } else if remaining != before {
            lastTimeAdjustment = "Adjusted at your \(progress)% check-in: \(remaining / 60) min left (was \(before / 60))."
        }
    }

    /// Time left after a check-in, or nil to leave it alone (0% gives no pace to go on). Pace so far: `elapsed`
    /// bought `progress` percent, so the rest needs elapsed × (100 − p) / p. Kept to at least 5 minutes and to at
    /// most twice the planned length overall (3 hours at most), in whole minutes. 100% means done: 0 ends it.
    nonisolated public static func adaptedRemaining(elapsed: Int, remaining: Int, planned: Int, progress: Int) -> Int? {
        guard elapsed > 0 else { return nil }
        if progress >= 100 { return 0 }
        guard progress > 0 else { return nil }
        let needed = Double(elapsed) * Double(100 - progress) / Double(progress)
        let longestTotal = min(planned * 2, 180 * 60)
        let upper = max(longestTotal - elapsed, 5 * 60)
        let clamped = min(max(needed, 5 * 60), Double(upper))
        return Int((clamped / 60).rounded()) * 60
    }

    public func toggleMilestone(id: UUID) {
        if let idx = milestones.firstIndex(where: { $0.id == id }) {
            milestones[idx].isDone.toggle()
            saveMilestones()
        }
    }

    public func addMilestone(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        milestones.append(TestMilestone(text: trimmed, isDone: false))
        saveMilestones()
    }

    public func removeMilestone(id: UUID) {
        milestones.removeAll { $0.id == id }
        saveMilestones()
    }

    /// Loads (or starts) the milestone file for this account, so accounts on one Mac never share milestones.
    /// Loads this account's milestones and notes, so accounts on one Mac never share them.
    /// Forgets the loaded account (after it's deleted): stops the timer and stops every save for it.
    public func deactivateAccount() {
        if isTimerActive { resetTimer() }
        milestonesTask?.cancel()
        accountUserID = nil
        milestones = []
        notes = []
        stats = FocusStats()
        selectedNoteId = nil
    }

    /// What the app calls the student (the dashboard greeting and profile card). Saved per account on this Mac;
    /// starts from the sign-in provider's name, or the first part of the email, and can be changed in Settings.
    @Published public var displayName: String = "" {
        didSet {
            guard let accountUserID, displayName != oldValue else { return }
            UserDefaults.standard.set(displayName, forKey: "profile.displayName-\(accountUserID)")
        }
    }

    /// Picks a starting name when an account has none saved yet: the provider's name, else the email's first part.
    public nonisolated static func defaultDisplayName(email: String, providerName: String?) -> String {
        if let providerName, let first = providerName.split(separator: " ").first { return String(first.prefix(40)) }
        let local = email.split(separator: "@").first.map(String.init) ?? ""
        let firstPart = local.split(whereSeparator: { $0 == "." || $0 == "_" || $0 == "-" || $0 == "+" }).first.map(String.init) ?? ""
        let letters = firstPart.filter(\.isLetter)
        guard !letters.isEmpty else { return "" }
        return letters.prefix(1).uppercased() + letters.dropFirst().lowercased()
    }

    public func activateAccount(userID: String) {
        guard accountUserID != userID else { return }
        accountUserID = userID
        if let saved = UserDefaults.standard.string(forKey: "profile.displayName-\(userID)") {
            displayName = saved
        } else {
            let user = AuthManager.shared.user
            displayName = Self.defaultDisplayName(email: user?.email ?? "", providerName: user?.name)
        }
        milestonesTask?.cancel()
        isCreatingMilestones = false
        milestones = load([TestMilestone].self, from: "milestones") ?? []
        notes = load([TestProjectNote].self, from: "notes") ?? []
        stats = load(FocusStats.self, from: "stats") ?? FocusStats()
        selectedNoteId = nil
        restoreRunningSession()
    }

    private func accountFileURL(_ name: String) -> URL? {
        guard let userID = accountUserID else { return nil }
        let safe = userID.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LockenTestApp", isDirectory: true)
            .appendingPathComponent("\(name)-\(safe).json")
    }

    private func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let url = accountFileURL(name), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, to name: String) {
        guard let url = accountFileURL(name) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
        } catch {
            print("TestAppStateManager: couldn't save \(name): \(error)")
        }
    }

    private func saveMilestones() { save(milestones, to: "milestones") }

    // MARK: Notes

    /// Starts a blank note at the top of the list and opens it.
    public func addNote() {
        let note = TestProjectNote()
        notes.insert(note, at: 0)
        selectedNoteId = note.id
        save(notes, to: "notes")
    }

    public func updateNote(id: UUID, title: String, body: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }),
              notes[index].title != title || notes[index].body != body else { return }
        notes[index].title = title
        notes[index].body = body
        notes[index].updatedAt = Date()
        // Most recently edited first.
        notes.insert(notes.remove(at: index), at: 0)
        save(notes, to: "notes")
    }

    public func deleteNote(id: UUID) {
        notes.removeAll { $0.id == id }
        if selectedNoteId == id { selectedNoteId = nil }
        save(notes, to: "notes")
    }
}


// MARK: - Focus mode sound

/// The sound when focus mode switches on, like AirPods' noise cancellation turning on: a soft rise of air into two rising chime
/// notes (E5, then A5) with a short tail. Synthesised here, so there's no audio file; about 1.4 s, quiet, and it follows the Mac's
/// output volume and mute.
@MainActor
enum FocusSound {
    private static var player: AVAudioPlayer?
    nonisolated private static let sampleRate = 44_100.0

    static func playOn() {
        guard let data = wav(from: samples()), let sound = try? AVAudioPlayer(data: data) else { return }
        sound.volume = 0.6
        sound.prepareToPlay()
        sound.play()
        player = sound // kept until the next one, so it isn't cut off
    }

    /// Mono samples, peak 0.5, ending in silence.
    nonisolated static func samples() -> [Float] {
        let rate = sampleRate
        let count = Int(rate * 1.4)
        var dry = [Float](repeating: 0, count: count)

        // The air: noise through a band-pass filter whose centre rises from 350 Hz to 3.5 kHz while it swells and fades.
        var generator = SystemRandomNumberGenerator()
        var low = 0.0, band = 0.0
        for i in 0..<count {
            let t = Double(i) / rate
            guard t < 0.9 else { break }
            let centre = 350 + 3150 * pow(min(t / 0.6, 1), 1.6)
            let f = 2 * sin(Double.pi * centre / rate)
            let noise = Double.random(in: -1...1, using: &generator)
            let high = noise - low - 0.35 * band
            band += f * high
            low += f * band
            let rise = min(t / 0.45, 1)
            let swell = rise * rise * (3 - 2 * rise)
            let fade = t < 0.55 ? 1 : max(0, 1 - (t - 0.55) / 0.35)
            dry[i] += Float(band * swell * fade * 0.55)
        }

        // The two notes: sine with a soft second and third harmonic, a quick attack and a long, smooth decay.
        for (start, frequency, level) in [(0.18, 659.26, 0.34), (0.34, 880.0, 0.30)] {
            let first = Int(start * rate)
            for i in first..<count {
                let t = Double(i - first) / rate
                let attack = min(t / 0.008, 1)
                let envelope = attack * exp(-t / 0.3)
                let phase = 2 * Double.pi * frequency * t
                let tone = sin(phase) + 0.22 * sin(2 * phase) + 0.07 * sin(3 * phase)
                dry[i] += Float(tone * envelope * level)
            }
        }

        // A short tail: three quiet echoes.
        var mixed = dry
        for (delay, level) in [(0.11, 0.30), (0.19, 0.18), (0.29, 0.10)] {
            let shift = Int(delay * rate)
            for i in shift..<count { mixed[i] += dry[i - shift] * Float(level) }
        }

        // Peak 0.5 and a 60 ms fade at the very end.
        let peak = max(mixed.map { abs($0) }.max() ?? 1, 0.0001)
        let fadeLength = Int(0.06 * rate)
        for i in 0..<count {
            var gain = 0.5 / peak
            if i > count - fadeLength { gain *= Float(count - i) / Float(fadeLength) }
            mixed[i] *= gain
        }
        return mixed
    }

    /// 16-bit mono PCM in a WAV container.
    nonisolated static func wav(from samples: [Float]) -> Data? {
        guard !samples.isEmpty else { return nil }
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = samples.count * 2
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + bytes)); data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate) * 2); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(UInt32(bytes))
        for sample in samples { append(Int16(max(-1, min(1, sample)) * 32767)) }
        return data
    }
}
