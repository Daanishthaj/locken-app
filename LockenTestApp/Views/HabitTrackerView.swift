import SwiftUI

// MARK: - Habit Tracker

/// One calm page: a Today strip, the week matrix (with past weeks and per-habit history when those features
/// are on), and a sheet to add or edit habits. Everything is saved on this Mac by `HabitStore`.
struct HabitTrackerView: View {
    @ObservedObject private var store = HabitStore.shared

    @State private var weekOffset = 0
    @State private var expandedID: UUID?
    @State private var editing: HabitDraft?
    @State private var pendingDelete: Habit?

    private let accent = SquircleTokens.accentColor(for: "analytics")
    private static let dayLetters = ["M", "T", "W", "T", "F", "S", "S"]

    private var weekDays: [Date] {
        let monday = Calendar.current.date(byAdding: .day, value: weekOffset * 7, to: HabitMath.weekStart(Date()))!
        return (0..<7).map { Calendar.current.date(byAdding: .day, value: $0, to: monday)! }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Spacing.l) {
                header

                if !store.features.hasOnboarded {
                    HabitSetupCard()
                } else if store.activeHabits.isEmpty {
                    emptyState
                } else {
                    if store.features.today { todayCard }
                    weekCard
                }
            }
            .lockenPage()
        }
        .gradualBlurBottom()
        .sheet(item: $editing) { draft in
            HabitEditorSheet(draft: draft, features: store.features) { saved in
                if store.habits.contains(where: { $0.id == saved.id }) { store.update(saved) } else { store.add(saved) }
                if saved.hasReminder, store.features.reminders {
                    Task { _ = await HabitReminders.requestPermissionIfNeeded() }
                }
            }
        }
        .confirmationDialog(
            "Delete \u{201C}\(pendingDelete?.name ?? "")\u{201D}?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
        ) {
            Button("Delete Habit and History", role: .destructive) {
                if let pendingDelete { store.delete(pendingDelete) }
                pendingDelete = nil
            }
        } message: {
            Text("This removes its streaks and history from this Mac. To keep the history, archive it instead.")
        }
    }

    // MARK: Header

    private var header: some View {
        // Centered title; the page's one main action sits under it.
        PageHeader(title: "Habit Tracker", subtitle: summaryLine) {
            if store.features.hasOnboarded {
                Button { editing = HabitDraft() } label: {
                    Label("New Habit", systemImage: "plus")
                        .font(.appFont(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .borderGlowButton(accent: accent, isProminent: true)
                }
                .buttonStyle(.plain)
                .padding(.top, Spacing.xs)
            }
        }
    }

    private var summaryLine: String {
        guard !store.activeHabits.isEmpty else { return "Build routines that stick. Everything stays on this Mac." }
        let rates = store.weeklyRates()
        let now = Int((rates.thisWeek * 100).rounded())
        guard rates.lastWeek > 0 else { return "This week \(now)% of habits done" }
        let change = Int(((rates.thisWeek - rates.lastWeek) * 100).rounded())
        let trend = change == 0 ? "same as last week" : change > 0 ? "up \(change)% from last week" : "down \(-change)% from last week"
        return "This week \(now)% \u{00B7} \(trend)"
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(accent)
            Text("No habits yet")
                .font(.appFont(size: 16, weight: .bold))
                .foregroundColor(.white)
            Text("Start with one small thing you want to do most days.")
                .font(.appFont(size: 13))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .luxuryObsidianCard(cornerRadius: SquircleTokens.radiusLarge)
    }

    // MARK: Today

    private var todayCard: some View {
        let today = Date()
        let due = store.activeHabits.filter { HabitMath.isScheduled($0, on: today) }
        let doneCount = due.filter { store.isDone($0, on: today) }.count
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("TODAY")
                    .font(.appFont(size: 11, weight: .bold))
                    .tracking(1.0)
                    .foregroundColor(.white.opacity(0.55))
                Text(today.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.appFont(size: 12))
                    .foregroundColor(.white.opacity(0.55))
            }

            HStack(alignment: .top, spacing: 28) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.08), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: due.isEmpty ? 0 : CGFloat(doneCount) / CGFloat(due.count))
                        .stroke(accent, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.3), value: doneCount)
                    VStack(spacing: 2) {
                        Text("\(doneCount)/\(due.count)")
                            .font(.appFont(size: 24, weight: .bold))
                            .foregroundColor(.white)
                        Text("done")
                            .font(.appFont(size: 11))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .frame(width: 104, height: 104)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(doneCount) of \(due.count) habits done today")

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14, alignment: .leading)], alignment: .leading, spacing: 14) {
                    ForEach(due) { habit in
                        todayPill(habit)
                    }
                }
            }
        }
        .padding(24)
        .luxuryObsidianCard(cornerRadius: SquircleTokens.radiusLarge)
    }

    @ViewBuilder
    private func todayPill(_ habit: Habit) -> some View {
        if habit.hasAmountGoal && !store.isAutoTracked(habit) {
            amountPill(habit)
        } else {
            checkPill(habit)
        }
    }

    /// Amount goal: tap to add one, minus to take one back; done once it reaches the goal.
    private func amountPill(_ habit: Habit) -> some View {
        let goal = habit.goalAmount ?? 1
        let value = store.amount(habit, on: Date())
        let done = value >= goal
        let unit = habit.goalUnit.map { " \($0)" } ?? ""
        return HStack(spacing: 14) {
            Button { store.setAmount(habit, on: Date(), to: value + 1) } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.08), lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: CGFloat(min(value, goal)) / CGFloat(goal))
                            .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: done ? "checkmark" : habit.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(done ? accent : .white.opacity(0.8))
                    }
                    .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(habit.name)
                            .font(.appFont(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(value) of \(goal)\(unit)\(done ? " \u{00B7} goal reached" : "")")
                            .font(.appFont(size: 11))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(habit.name), \(value) of \(goal)\(unit)")
            .accessibilityHint("Adds one")

            HStack(spacing: 6) {
                stepButton("minus", label: "Remove one") { store.setAmount(habit, on: Date(), to: value - 1) }
                    .disabled(value == 0)
                    .opacity(value == 0 ? 0.35 : 1)
                stepButton("plus", label: "Add one") { store.setAmount(habit, on: Date(), to: value + 1) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minHeight: 68)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(done ? accent.opacity(0.12) : Color.white.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(done ? accent.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1))
        )
        .contextMenu { Button("Edit\u{2026}") { editing = HabitDraft(habit) } }
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func checkPill(_ habit: Habit) -> some View {
        let done = store.isDone(habit, on: Date())
        let auto = store.isAutoTracked(habit)
        return Button { store.toggle(habit, on: Date()) } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(done ? accent : Color.white.opacity(0.07))
                    Image(systemName: done ? "checkmark" : habit.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(done ? .black : .white.opacity(0.8))
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(habit.name)
                        .font(.appFont(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(auto ? autoStatus(habit, done: done) : done ? "Done" : "Tap when done")
                        .font(.appFont(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: 68)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(done ? accent.opacity(0.12) : Color.white.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(done ? accent.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Auto-tracked habits tick themselves; block taps without greying them out.
        .allowsHitTesting(!auto)
        .contextMenu { Button("Edit\u{2026}") { editing = HabitDraft(habit) } }
        .accessibilityLabel(habit.name)
        .accessibilityValue(done ? "Done" : auto ? autoStatus(habit, done: done) : "Not done")
    }

    private func autoStatus(_ habit: Habit, done: Bool) -> String {
        switch habit.autoTrack {
        case .manual:
            return ""
        case .focusSession(let minutes):
            return done ? "Auto \u{00B7} done by a focus session" : "Auto \u{00B7} finish a \(minutes)-min focus session"
        case .socialUnder(let limit):
            guard let minutes = store.socialMinutes(on: Date()) else { return "Auto \u{00B7} under \(limit) min of social media" }
            return minutes < Double(limit)
                ? "Auto \u{00B7} \(Int(minutes)) of \(limit) min \u{00B7} on track"
                : "Auto \u{00B7} over the \(limit)-min limit today"
        }
    }

    // MARK: Week

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text(weekTitle)
                    .font(.appFont(size: 11, weight: .bold))
                    .tracking(1.0)
                    .foregroundColor(.white.opacity(0.55))
                if store.features.history {
                    weekArrow("chevron.left", label: "Previous week") { weekOffset -= 1 }
                    weekArrow("chevron.right", label: "Next week") { weekOffset += 1 }
                        .disabled(weekOffset >= 0)
                        .opacity(weekOffset >= 0 ? 0.3 : 1)
                    if weekOffset != 0 {
                        Button("This week") { weekOffset = 0 }
                            .buttonStyle(.plain)
                            .font(.appFont(size: 11, weight: .semibold))
                            .foregroundColor(accent)
                    }
                }
                Spacer()
                HStack(spacing: 8) {
                    ForEach(Array(weekDays.enumerated()), id: \.offset) { index, day in
                        let isToday = Calendar.current.isDateInToday(day)
                        VStack(spacing: 1) {
                            Text(Self.dayLetters[index])
                                .font(.appFont(size: 10, weight: .bold))
                            Text("\(Calendar.current.component(.day, from: day))")
                                .font(.appFont(size: 9))
                        }
                        .foregroundColor(isToday ? accent : .white.opacity(0.45))
                        .frame(width: 24)
                    }
                }
                .padding(.trailing, 12)
            }

            ForEach(store.activeHabits) { habit in
                VStack(spacing: 0) {
                    habitRow(habit)
                    if store.features.history && expandedID == habit.id {
                        HabitDetailPanel(habit: habit, accent: accent)
                            .padding(.top, 10)
                            .transition(.opacity)
                    }
                }
                .padding(14)
                .innerObsidianCard(cornerRadius: 12)
                .contextMenu {
                    Button("Edit\u{2026}") { editing = HabitDraft(habit) }
                    Button("Archive") { store.archive(habit) }
                    Divider()
                    Button("Delete\u{2026}", role: .destructive) { pendingDelete = habit }
                }
            }
        }
        .padding(Spacing.l)
        .luxuryObsidianCard(cornerRadius: SquircleTokens.radiusLarge)
    }

    private var weekTitle: String {
        guard weekOffset != 0, let first = weekDays.first, let last = weekDays.last else { return "THIS WEEK" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: first)) \u{2013} \(formatter.string(from: last))".uppercased()
    }

    private func weekArrow(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func habitRow(_ habit: Habit) -> some View {
        let streak = store.currentStreak(habit)
        let best = store.bestStreak(habit)
        let unit: String = { if case .timesPerWeek = habit.schedule { return "wk" } else { return "day" } }()
        return HStack {
            Button {
                guard store.features.history else { return }
                withAnimation(.easeOut(duration: 0.2)) { expandedID = expandedID == habit.id ? nil : habit.id }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: habit.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(accent)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(habit.name)
                            .font(.appFont(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        HStack(spacing: 6) {
                            if streak > 0 {
                                Label("\(streak)-\(unit) streak", systemImage: "flame.fill")
                                    .labelStyle(.titleAndIcon)
                            } else {
                                Text("No streak yet")
                            }
                            Text("\u{00B7} best \(best) \u{00B7} \(goalText(habit)) \u{00B7} \(scheduleText(habit))")
                        }
                        .font(.appFont(size: 11))
                        .foregroundColor(SquircleTokens.smokedAmber.opacity(0.9))
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(store.features.history ? "Shows streak history" : "")

            Button { editing = HabitDraft(habit) } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .help("Edit habit and goal")
            .accessibilityLabel("Edit \(habit.name)")
            .padding(.trailing, 6)

            HStack(spacing: 8) {
                ForEach(Array(weekDays.enumerated()), id: \.offset) { index, day in
                    dayCell(habit, day: day, letter: Self.dayLetters[index])
                }
            }
            .padding(.trailing, 8)
        }
    }

    private func dayCell(_ habit: Habit, day: Date, letter: String) -> some View {
        let isFuture = Calendar.current.startOfDay(for: day) > Calendar.current.startOfDay(for: Date())
        let scheduled = HabitMath.isScheduled(habit, on: day)
        let done = store.isDone(habit, on: day)
        let isToday = Calendar.current.isDateInToday(day)
        let partial = !done && habit.hasAmountGoal && store.amount(habit, on: day) > 0
        return Button { store.toggle(habit, on: day) } label: {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(done ? accent : partial ? accent.opacity(0.35) : Color.white.opacity(isFuture ? 0.02 : scheduled ? 0.06 : 0.03))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(isToday && !done ? accent.opacity(0.6) : .clear, lineWidth: 1))
                .overlay {
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.black)
                    } else if !scheduled && !isFuture {
                        Circle().fill(Color.white.opacity(0.15)).frame(width: 3, height: 3)
                    }
                }
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .disabled(isFuture || store.isAutoTracked(habit))
        .accessibilityLabel("\(habit.name), \(day.formatted(date: .abbreviated, time: .omitted))")
        .accessibilityValue(done ? "Done" : isFuture ? "Upcoming" : scheduled ? "Not done" : "Rest day")
    }

    /// The goal in words: an amount, an automatic target, or just checking it off.
    private func goalText(_ habit: Habit) -> String {
        if store.isAutoTracked(habit) {
            switch habit.autoTrack {
            case .focusSession(let minutes): return "Goal: \(minutes)-min focus session"
            case .socialUnder(let minutes): return "Goal: under \(minutes) min social"
            case .manual: break
            }
        }
        if let goal = habit.goalAmount, goal > 0 {
            return "Goal: \(goal)\(habit.goalUnit.map { " \($0)" } ?? "") a day"
        }
        return "Goal: check off"
    }

    private func scheduleText(_ habit: Habit) -> String {
        switch habit.schedule {
        case .daily: return "Every day"
        case .timesPerWeek(let n): return "\(n)\u{00D7} a week"
        case .weekdays(let days):
            if days.sorted() == [1, 2, 3, 4, 5] { return "Weekdays" }
            let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            return days.sorted().map { names[$0 - 1] }.joined(separator: ", ")
        }
    }
}

// MARK: - History (inline, per habit)

private struct HabitDetailPanel: View {
    @ObservedObject private var store = HabitStore.shared
    let habit: Habit
    let accent: Color

    var body: some View {
        let unit: String = { if case .timesPerWeek = habit.schedule { return "weeks" } else { return "days" } }()
        HStack(alignment: .top, spacing: 26) {
            stat("\(store.currentStreak(habit))", "Current streak (\(unit))")
            stat("\(store.bestStreak(habit))", "Best streak (\(unit))")
            stat("\(Int((store.completionRate(habit) * 100).rounded()))%", "Last 30 days")
            Spacer(minLength: 0)
            heatMap
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.18)))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.appFont(size: 22, weight: .bold))
                .foregroundColor(.white)
            Text(label)
                .font(.appFont(size: 10))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    /// 12 weeks as columns, Monday at the top, like a contribution graph.
    private var heatMap: some View {
        let calendar = Calendar.current
        let thisMonday = HabitMath.weekStart(Date())
        let today = calendar.startOfDay(for: Date())
        return VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 3) {
                ForEach((0..<12).reversed(), id: \.self) { weeksBack in
                    let monday = calendar.date(byAdding: .day, value: -7 * weeksBack, to: thisMonday)!
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { offset in
                            let day = calendar.date(byAdding: .day, value: offset, to: monday)!
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(color(for: day, today: today))
                                .frame(width: 10, height: 10)
                        }
                    }
                }
            }
            Text("Last 12 weeks")
                .font(.appFont(size: 10))
                .foregroundColor(.white.opacity(0.55))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Last 12 weeks: \(Int((store.completionRate(habit, days: 84) * 100).rounded())) percent done")
    }

    private func color(for day: Date, today: Date) -> Color {
        if day > today { return .clear }
        if store.isDone(habit, on: day) { return accent }
        return HabitMath.isScheduled(habit, on: day) ? Color.white.opacity(0.08) : Color.white.opacity(0.03)
    }
}

// MARK: - Add / edit

/// Editable copy of a habit, used by the sheet.
struct HabitDraft: Identifiable {
    var habit: Habit
    var id: UUID { habit.id }

    init(_ habit: Habit = Habit(name: "", symbol: "sparkles", category: "Focus")) {
        self.habit = habit
    }
}

private struct HabitEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var habit: Habit
    let features: HabitFeatures
    let onSave: (Habit) -> Void

    private let accent = SquircleTokens.accentColor(for: "analytics")
    private let isNew: Bool

    private static let symbols = [
        "sparkles", "brain.head.profile", "book.fill", "pencil.and.outline", "rectangle.stack.fill", "figure.run",
        "dumbbell.fill", "drop.fill", "leaf.fill", "moon.stars.fill", "iphone.slash", "hand.raised.fill",
    ]
    private static let categories = ["Focus", "Discipline", "Academics", "Recovery", "Health"]
    private static let scheduleOptions = ["Every day", "Weekdays", "Pick days", "Times a week"]
    private static let trackingOptions = ["Manual", "Focus session", "Social media limit"]

    @State private var scheduleChoice: String
    @State private var pickedDays: Set<Int>
    @State private var timesPerWeek: Int
    @State private var trackingChoice: String
    @State private var focusMinutes: Int
    @State private var socialMinutes: Int
    @State private var remind: Bool
    @State private var reminderTime: Date
    @State private var goalChoice: String
    @State private var goalAmount: Int
    @State private var goalUnit: String
    private static let goalOptions = ["Check off", "Reach an amount"]

    init(draft: HabitDraft, features: HabitFeatures, onSave: @escaping (Habit) -> Void) {
        let habit = draft.habit
        _habit = State(initialValue: habit)
        self.features = features
        self.onSave = onSave
        isNew = habit.name.isEmpty

        switch habit.schedule {
        case .daily:
            _scheduleChoice = State(initialValue: "Every day")
            _pickedDays = State(initialValue: [1, 2, 3, 4, 5])
            _timesPerWeek = State(initialValue: 3)
        case .weekdays(let days):
            _scheduleChoice = State(initialValue: days.sorted() == [1, 2, 3, 4, 5] ? "Weekdays" : "Pick days")
            _pickedDays = State(initialValue: Set(days))
            _timesPerWeek = State(initialValue: 3)
        case .timesPerWeek(let n):
            _scheduleChoice = State(initialValue: "Times a week")
            _pickedDays = State(initialValue: [1, 2, 3, 4, 5])
            _timesPerWeek = State(initialValue: n)
        }
        switch habit.autoTrack {
        case .manual:
            _trackingChoice = State(initialValue: "Manual")
            _focusMinutes = State(initialValue: 60)
            _socialMinutes = State(initialValue: 30)
        case .focusSession(let m):
            _trackingChoice = State(initialValue: "Focus session")
            _focusMinutes = State(initialValue: m)
            _socialMinutes = State(initialValue: 30)
        case .socialUnder(let m):
            _trackingChoice = State(initialValue: "Social media limit")
            _focusMinutes = State(initialValue: 60)
            _socialMinutes = State(initialValue: m)
        }
        _goalChoice = State(initialValue: habit.hasAmountGoal ? "Reach an amount" : "Check off")
        _goalAmount = State(initialValue: habit.goalAmount ?? 10)
        _goalUnit = State(initialValue: habit.goalUnit ?? "")
        _remind = State(initialValue: habit.hasReminder)
        let time = Calendar.current.date(bySettingHour: habit.reminderHour ?? 20, minute: habit.reminderMinute ?? 0, second: 0, of: Date()) ?? Date()
        _reminderTime = State(initialValue: time)
    }

    private var canSave: Bool {
        !habit.name.trimmingCharacters(in: .whitespaces).isEmpty && !(scheduleChoice == "Pick days" && pickedDays.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(isNew ? "New Habit" : "Edit Habit")
                .font(.appFont(size: 18, weight: .bold))
                .foregroundColor(.white)

            section("NAME") {
                TextField("e.g. Read 20 pages", text: $habit.name)
                    .textFieldStyle(.plain)
                    .font(.appFont(size: 14))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
            }

            section("ICON") {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 8), count: 6), alignment: .leading, spacing: 8) {
                    ForEach(Self.symbols, id: \.self) { symbol in
                        Button { habit.symbol = symbol } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(habit.symbol == symbol ? .black : .white.opacity(0.8))
                                .frame(width: 34, height: 34)
                                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(habit.symbol == symbol ? accent : Color.white.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(symbol)
                        .accessibilityAddTraits(habit.symbol == symbol ? .isSelected : [])
                    }
                }
            }

            section("CATEGORY") {
                JellyRadioPicker(items: Self.categories, selection: $habit.category, label: "Category")
            }

            section("SCHEDULE") {
                JellyRadioPicker(items: Self.scheduleOptions, selection: $scheduleChoice, label: "Schedule")
                if scheduleChoice == "Pick days" {
                    HStack(spacing: 6) {
                        ForEach(1...7, id: \.self) { day in
                            let on = pickedDays.contains(day)
                            Button {
                                if on { pickedDays.remove(day) } else { pickedDays.insert(day) }
                            } label: {
                                Text(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][day - 1])
                                    .font(.appFont(size: 11, weight: .semibold))
                                    .foregroundColor(on ? .black : .white.opacity(0.75))
                                    .frame(width: 40, height: 28)
                                    .background(Capsule().fill(on ? accent : Color.white.opacity(0.06)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else if scheduleChoice == "Times a week" {
                    Stepper("\(timesPerWeek) times a week", value: $timesPerWeek, in: 1...6)
                        .font(.appFont(size: 13))
                        .foregroundColor(.white)
                }
            }

            if !(features.autoTracking && trackingChoice != "Manual") {
                section("DAILY GOAL") {
                    JellyRadioPicker(items: Self.goalOptions, selection: $goalChoice, label: "Daily goal")
                    if goalChoice == "Reach an amount" {
                        HStack(spacing: 12) {
                            Stepper("Goal: \(goalAmount)", value: $goalAmount, in: 1...1000)
                                .font(.appFont(size: 13))
                                .foregroundColor(.white)
                                .fixedSize()
                            TextField("unit, e.g. pages", text: $goalUnit)
                                .textFieldStyle(.plain)
                                .font(.appFont(size: 13))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.06)))
                                .frame(maxWidth: 180)
                        }
                    }
                }
            }

            if features.autoTracking {
                section("TRACKING") {
                    JellyRadioPicker(items: Self.trackingOptions, selection: $trackingChoice, label: "Tracking")
                    if trackingChoice == "Focus session" {
                        Stepper("Done after a \(focusMinutes)-min focus session", value: $focusMinutes, in: 15...180, step: 15)
                            .font(.appFont(size: 13)).foregroundColor(.white)
                    } else if trackingChoice == "Social media limit" {
                        Stepper("Done when social media stays under \(socialMinutes) min", value: $socialMinutes, in: 5...180, step: 5)
                            .font(.appFont(size: 13)).foregroundColor(.white)
                    }
                }
            }

            if features.reminders {
                section("REMINDER") {
                    HStack {
                        Toggle("Remind me", isOn: $remind)
                            .toggleStyle(GlassSwitchToggleStyle())
                            .font(.appFont(size: 13))
                            .foregroundColor(.white)
                        Spacer()
                        if remind {
                            DatePicker("", selection: $reminderTime, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.appFont(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .keyboardShortcut(.cancelAction)
                Button(action: save) {
                    Text(isNew ? "Add Habit" : "Save")
                        .font(.appFont(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .borderGlowButton(accent: accent, isProminent: true)
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.5)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
        .background(SquircleTokens.obsidianCard)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.appFont(size: 10, weight: .bold))
                .tracking(1.0)
                .foregroundColor(.white.opacity(0.5))
            content()
        }
    }

    private func save() {
        var result = habit
        result.name = habit.name.trimmingCharacters(in: .whitespaces)
        switch scheduleChoice {
        case "Weekdays": result.schedule = .weekdays([1, 2, 3, 4, 5])
        case "Pick days": result.schedule = .weekdays(pickedDays.sorted())
        case "Times a week": result.schedule = .timesPerWeek(timesPerWeek)
        default: result.schedule = .daily
        }
        if features.autoTracking {
            switch trackingChoice {
            case "Focus session": result.autoTrack = .focusSession(minMinutes: focusMinutes)
            case "Social media limit": result.autoTrack = .socialUnder(minutes: socialMinutes)
            default: result.autoTrack = .manual
            }
        }
        if goalChoice == "Reach an amount" && result.autoTrack == .manual {
            result.goalAmount = goalAmount
            let unit = goalUnit.trimmingCharacters(in: .whitespaces)
            result.goalUnit = unit.isEmpty ? nil : unit
        } else {
            result.goalAmount = nil
            result.goalUnit = nil
        }
        if features.reminders {
            if remind {
                let parts = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
                result.reminderHour = parts.hour
                result.reminderMinute = parts.minute
            } else {
                result.reminderHour = nil
                result.reminderMinute = nil
            }
        }
        onSave(result)
        dismiss()
    }
}
