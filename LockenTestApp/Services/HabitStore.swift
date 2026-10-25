import Foundation

// MARK: - Model

struct Habit: Identifiable, Codable, Equatable {
    enum Schedule: Codable, Equatable {
        case daily
        /// ISO weekdays, 1 = Monday … 7 = Sunday.
        case weekdays([Int])
        case timesPerWeek(Int)
    }

    enum AutoTrack: Codable, Equatable {
        case manual
        /// Done when a focus session of at least this many minutes finishes that day.
        case focusSession(minMinutes: Int)
        /// Done when that day's social-media time (Analytics tracker) stays under this many minutes.
        case socialUnder(minutes: Int)
    }

    var id = UUID()
    var name: String
    var symbol: String
    var category: String
    var schedule: Schedule = .daily
    var autoTrack: AutoTrack = .manual
    var reminderHour: Int?
    var reminderMinute: Int?
    /// Days the habit was done, as "yyyy-MM-dd".
    var completions: Set<String> = []
    var createdAt = Date()
    var archived = false
    /// Optional daily amount goal ("20 pages", "8 glasses"); nil means a simple check-off.
    var goalAmount: Int?
    var goalUnit: String?
    /// Amount logged per day ("yyyy-MM-dd" → count) for amount goals.
    var progress: [String: Int]?

    var hasReminder: Bool { reminderHour != nil && reminderMinute != nil }
    var hasAmountGoal: Bool { (goalAmount ?? 0) > 0 }
}

/// Which parts of the Habit Tracker the user turned on (chosen at first sign-in, editable in Settings).
struct HabitFeatures: Codable, Equatable {
    var today = true
    var history = true
    var autoTracking = true
    var reminders = true
    var hasOnboarded = false
}

// MARK: - Store

/// Habits for the signed-in account, saved only on this Mac:
/// `~/Library/Application Support/LockenTestApp/habits-<user id>.json`.
@MainActor
final class HabitStore: ObservableObject {
    static let shared = HabitStore()

    @Published private(set) var userID: String?
    @Published private(set) var habits: [Habit] = []
    @Published private(set) var features = HabitFeatures()

    var activeHabits: [Habit] { habits.filter { !$0.archived } }

    private struct StoredFile: Codable {
        var features: HabitFeatures
        var habits: [Habit]
    }

    private init() {}

    // MARK: Account

    /// Loads (or starts) the habit file for this account. Different accounts on one Mac never share habits.
    /// Forgets the loaded account (after it's deleted), so nothing is written for it again.
    func deactivate() {
        userID = nil
        habits = []
        features = HabitFeatures()
    }

    func activate(userID: String) {
        guard self.userID != userID else { return }
        self.userID = userID
        if let url = fileURL(for: userID), let data = try? Data(contentsOf: url),
           let stored = try? JSONDecoder().decode(StoredFile.self, from: data) {
            features = stored.features
            habits = stored.habits
        } else {
            features = HabitFeatures()
            habits = []
        }
        HabitReminders.reschedule(for: self)
    }

    func completeOnboarding(features chosen: HabitFeatures, seedExamples: Bool) {
        var features = chosen
        features.hasOnboarded = true
        self.features = features
        if seedExamples && habits.isEmpty { habits = Self.examples() }
        save()
    }

    func setFeatures(_ newValue: HabitFeatures) {
        var updated = newValue
        updated.hasOnboarded = true
        features = updated
        save()
    }

    // MARK: Editing

    func add(_ habit: Habit) {
        habits.append(habit)
        save()
    }

    func update(_ habit: Habit) {
        guard let index = habits.firstIndex(where: { $0.id == habit.id }) else { return }
        habits[index] = habit
        save()
    }

    func archive(_ habit: Habit) {
        guard let index = habits.firstIndex(where: { $0.id == habit.id }) else { return }
        habits[index].archived = true
        save()
    }

    func delete(_ habit: Habit) {
        habits.removeAll { $0.id == habit.id }
        save()
    }

    /// Ticks or unticks a day. Future days can't be ticked; auto-tracked habits are checked by the app.
    func toggle(_ habit: Habit, on date: Date) {
        guard let index = habits.firstIndex(where: { $0.id == habit.id }),
              Calendar.current.startOfDay(for: date) <= Calendar.current.startOfDay(for: Date()),
              !isAutoTracked(habits[index]) else { return }
        let key = HabitMath.key(date)
        if let goal = habits[index].goalAmount, goal > 0 {
            // Amount goals: tapping a day fills it to the goal, or clears it.
            setAmount(habits[index], on: date, to: habits[index].completions.contains(key) ? 0 : goal)
            return
        }
        if habits[index].completions.contains(key) {
            habits[index].completions.remove(key)
        } else {
            habits[index].completions.insert(key)
        }
        save()
    }

    /// How much of an amount goal is logged that day.
    func amount(_ habit: Habit, on date: Date) -> Int {
        let key = HabitMath.key(date)
        if let value = habit.progress?[key] { return value }
        return habit.completions.contains(key) ? (habit.goalAmount ?? 0) : 0
    }

    /// Logs an amount for a day; the day counts as done once it reaches the goal.
    func setAmount(_ habit: Habit, on date: Date, to value: Int) {
        guard let index = habits.firstIndex(where: { $0.id == habit.id }), let goal = habits[index].goalAmount,
              Calendar.current.startOfDay(for: date) <= Calendar.current.startOfDay(for: Date()) else { return }
        let key = HabitMath.key(date)
        let clamped = max(0, min(value, 99_999))
        var progress = habits[index].progress ?? [:]
        progress[key] = clamped == 0 ? nil : clamped
        habits[index].progress = progress
        if clamped >= goal {
            habits[index].completions.insert(key)
        } else {
            habits[index].completions.remove(key)
        }
        save()
    }

    // MARK: Auto-tracking

    func isAutoTracked(_ habit: Habit) -> Bool {
        features.autoTracking && habit.autoTrack != .manual
    }

    /// Called when a focus session's countdown finishes.
    func recordFocusSession(minutes: Int) {
        guard features.autoTracking else { return }
        let key = HabitMath.key(Date())
        var changed = false
        for index in habits.indices {
            if case .focusSession(let minimum) = habits[index].autoTrack, minutes >= minimum,
               !habits[index].completions.contains(key) {
                habits[index].completions.insert(key)
                changed = true
            }
        }
        if changed { save() }
    }

    /// Minutes of social media on a day, from the Analytics tracker (nil if Locken wasn't tracking that day).
    func socialMinutes(on date: Date) -> Double? {
        let back = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date),
                                                   to: Calendar.current.startOfDay(for: Date())).day ?? 0
        let usage = ScreenUsageTracker.shared.usage(daysBack: back)
        guard usage.total > 0 else { return nil }
        return usage.seconds(in: .social) / 60
    }

    /// Whether the habit counts as done that day, including auto-tracked results.
    func isDone(_ habit: Habit, on date: Date) -> Bool {
        if habit.completions.contains(HabitMath.key(date)) { return true }
        guard features.autoTracking, case .socialUnder(let limit) = habit.autoTrack else { return false }
        // A social-media limit is only met once the day is over.
        guard Calendar.current.startOfDay(for: date) < Calendar.current.startOfDay(for: Date()),
              let minutes = socialMinutes(on: date) else { return false }
        return minutes < Double(limit)
    }

    // MARK: Stats

    func currentStreak(_ habit: Habit) -> Int {
        HabitMath.currentStreak(habit, today: Date()) { isDone(habit, on: $0) }
    }

    func bestStreak(_ habit: Habit) -> Int {
        HabitMath.bestStreak(habit, today: Date()) { isDone(habit, on: $0) }
    }

    func completionRate(_ habit: Habit, days: Int = 30) -> Double {
        HabitMath.completionRate(habit, days: days, today: Date()) { isDone(habit, on: $0) }
    }

    /// Share of due habit-days done this week (so far) and last week, across all active habits.
    func weeklyRates() -> (thisWeek: Double, lastWeek: Double) {
        let calendar = Calendar.current
        let thisMonday = HabitMath.weekStart(Date())
        let lastMonday = calendar.date(byAdding: .day, value: -7, to: thisMonday)!
        func rate(from monday: Date, through end: Date) -> Double {
            var due = 0, done = 0
            for habit in activeHabits {
                let (d, n) = HabitMath.weekTally(habit, weekStart: monday, through: end) { isDone(habit, on: $0) }
                due += d
                done += n
            }
            return due == 0 ? 0 : Double(done) / Double(due)
        }
        let lastSunday = calendar.date(byAdding: .day, value: 6, to: lastMonday)!
        return (rate(from: thisMonday, through: Date()), rate(from: lastMonday, through: lastSunday))
    }

    // MARK: Storage

    private func fileURL(for userID: String) -> URL? {
        let safe = userID.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LockenTestApp", isDirectory: true)
            .appendingPathComponent("habits-\(safe).json")
    }

    private func save() {
        HabitReminders.reschedule(for: self)
        guard let userID, let url = fileURL(for: userID) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(StoredFile(features: features, habits: habits)).write(to: url, options: .atomic)
        } catch {
            print("HabitStore: couldn't save habits: \(error)")
        }
    }

    /// Starter habits for "Start with examples", with this week's sample ticks as real dates.
    private static func examples() -> [Habit] {
        let monday = HabitMath.weekStart(Date())
        func days(_ pattern: [Bool]) -> Set<String> {
            Set(pattern.enumerated().compactMap { offset, done in
                guard done, let date = Calendar.current.date(byAdding: .day, value: offset, to: monday), date <= Date() else { return nil }
                return HabitMath.key(date)
            })
        }
        return [
            Habit(name: "Deep Focus Block (90m)", symbol: "brain.head.profile", category: "Focus",
                  autoTrack: .focusSession(minMinutes: 90), completions: days([true, true, true, true, true, true, true]), createdAt: monday),
            Habit(name: "Phone in Another Room", symbol: "iphone.slash", category: "Discipline",
                  completions: days([true, true, true, true, true, true, true]), createdAt: monday),
            Habit(name: "Review Lecture Flashcards", symbol: "rectangle.stack.fill", category: "Academics",
                  schedule: .weekdays([1, 2, 3, 4, 5]), completions: days([true, true, false, true, true, false, false]), createdAt: monday),
            Habit(name: "Evening Review by 10 PM", symbol: "moon.stars.fill", category: "Recovery",
                  reminderHour: 21, reminderMinute: 30, completions: days([false, true, true, true, true, true, false]), createdAt: monday),
            Habit(name: "Social Media Under 30 Min", symbol: "hand.raised.fill", category: "Discipline",
                  autoTrack: .socialUnder(minutes: 30), createdAt: monday),
        ]
    }
}

// MARK: - Date math (pure, so it can be tested on its own)

enum HabitMath {
    static func key(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    /// 1 = Monday … 7 = Sunday.
    static func isoWeekday(_ date: Date) -> Int {
        (Calendar.current.component(.weekday, from: date) + 5) % 7 + 1
    }

    static func weekStart(_ date: Date) -> Date {
        let day = Calendar.current.startOfDay(for: date)
        return Calendar.current.date(byAdding: .day, value: -(isoWeekday(day) - 1), to: day)!
    }

    /// Whether the habit is expected on this day (every day counts for "times a week" habits).
    static func isScheduled(_ habit: Habit, on date: Date) -> Bool {
        switch habit.schedule {
        case .daily, .timesPerWeek: return true
        case .weekdays(let days): return days.contains(isoWeekday(date))
        }
    }

    /// Consecutive scheduled days done (or, for "times a week", consecutive weeks that hit the target).
    /// Today doesn't break a streak until it's over.
    static func currentStreak(_ habit: Habit, today: Date, isDone: (Date) -> Bool) -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: today)
        if case .timesPerWeek(let target) = habit.schedule {
            var weeks = 0
            var monday = weekStart(start)
            if weekCount(from: monday, through: start, isDone: isDone) >= target { weeks += 1 }
            for _ in 0..<260 {
                monday = calendar.date(byAdding: .day, value: -7, to: monday)!
                let sunday = calendar.date(byAdding: .day, value: 6, to: monday)!
                guard weekCount(from: monday, through: sunday, isDone: isDone) >= target else { break }
                weeks += 1
            }
            return weeks
        }
        var streak = isScheduled(habit, on: start) && isDone(start) ? 1 : 0
        var day = start
        for _ in 0..<3650 {
            day = calendar.date(byAdding: .day, value: -1, to: day)!
            guard isScheduled(habit, on: day) else { continue }
            guard isDone(day) else { break }
            streak += 1
        }
        return streak
    }

    static func bestStreak(_ habit: Habit, today: Date, isDone: (Date) -> Bool) -> Int {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: today)
        let first = habit.completions.compactMap(date(fromKey:)).min() ?? calendar.startOfDay(for: habit.createdAt)
        var best = 0, run = 0
        if case .timesPerWeek(let target) = habit.schedule {
            var monday = weekStart(first)
            while monday <= end {
                let sunday = calendar.date(byAdding: .day, value: 6, to: monday)!
                let met = weekCount(from: monday, through: min(sunday, end), isDone: isDone) >= target
                if met { run += 1; best = max(best, run) } else if sunday < end { run = 0 }
                monday = calendar.date(byAdding: .day, value: 7, to: monday)!
            }
            return best
        }
        var day = calendar.startOfDay(for: first)
        while day <= end {
            if isScheduled(habit, on: day) {
                if isDone(day) { run += 1; best = max(best, run) } else if day < end { run = 0 }
            }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return best
    }

    /// Done ÷ due over the last `days` days (from when the habit was created).
    static func completionRate(_ habit: Habit, days: Int, today: Date, isDone: (Date) -> Bool) -> Double {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: today)
        let start = max(calendar.date(byAdding: .day, value: -(days - 1), to: end)!, calendar.startOfDay(for: habit.createdAt))
        var due = 0, done = 0
        var day = start
        while day <= end {
            if isScheduled(habit, on: day) {
                if isDone(day) { done += 1 }
                // Today only counts once it's done, so an unfinished today doesn't drag the rate down.
                if day < end || isDone(day) { due += 1 }
            }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        if case .timesPerWeek(let target) = habit.schedule {
            let weeks = max(1, Double(days) / 7)
            return min(1, Double(done) / (Double(target) * weeks))
        }
        return due == 0 ? 0 : Double(done) / Double(due)
    }

    /// (due, done) for one week up to `through`, for the weekly summary.
    static func weekTally(_ habit: Habit, weekStart monday: Date, through end: Date, isDone: (Date) -> Bool) -> (Int, Int) {
        let calendar = Calendar.current
        let last = min(calendar.date(byAdding: .day, value: 6, to: monday)!, calendar.startOfDay(for: end))
        if case .timesPerWeek(let target) = habit.schedule {
            return (target, min(target, weekCount(from: monday, through: last, isDone: isDone)))
        }
        var due = 0, done = 0
        var day = monday
        while day <= last {
            if isScheduled(habit, on: day) {
                due += 1
                if isDone(day) { done += 1 }
            }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return (due, done)
    }

    static func weekCount(from start: Date, through end: Date, isDone: (Date) -> Bool) -> Int {
        var count = 0
        var day = start
        while day <= end {
            if isDone(day) { count += 1 }
            day = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        }
        return count
    }

    static func date(fromKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
