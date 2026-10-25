import SwiftUI
import AppKit
import QuartzCore

// MARK: - 1. Dashboard & Workspace View (Reference Layout)
public struct TestDashboardView: View {
    @ObservedObject var state = TestAppStateManager.shared
    @State private var greetingAppeared: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Feature flag: keeps the original static-annotation dashboard (below)
    // fully intact and reachable by flipping this to false — the interactive
    // liquid-glass expand/collapse behavior is additive, not a replacement.
    @State private var isInteractiveMode: Bool = true
    @State private var expandedAnnotation: String? = nil

    // Anchors are deliberately staggered to a unique x AND y each — not a
    // symmetric 2-column/2-row grid — and pulled in closer to the sphere.
    private let annotations: [DashboardAnnotation] = [
        DashboardAnnotation(label: "Focus", anchor: UnitPoint(x: 0.26, y: 0.14), target: UnitPoint(x: 0.32, y: 0.32)),
        DashboardAnnotation(label: "Habits", anchor: UnitPoint(x: 0.74, y: 0.28), target: UnitPoint(x: 0.68, y: 0.32)),
        DashboardAnnotation(label: "Sessions", anchor: UnitPoint(x: 0.22, y: 0.72), target: UnitPoint(x: 0.32, y: 0.68)),
        DashboardAnnotation(label: "Momentum", anchor: UnitPoint(x: 0.78, y: 0.88), target: UnitPoint(x: 0.68, y: 0.68))
    ]

    /// A calm home (2026-10-19): the greeting, the 3D orb, one card to start a session, the daily summary
    /// and today's habits. It opens at the top, with the greeting and the whole ring in view.
    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Spacing.l) {
                greetingHeader
                orbitalSphereStage
                SimpleHomeView()
            }
            .lockenPage(maxWidth: PageWidth.reading)
        }
        .gradualBlurBottom()
        .overlay {
            if state.isSessionSetupPresented {
                SessionSetupModal()
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Orbital Sphere Stage (sole dashboard visual, with annotation callouts)
    private var orbitalSphereStage: some View {
        GeometryReader { geo in
            ZStack {
                if isInteractiveMode {
                    // Stays in the hierarchy while a metric card is open: tearing the SceneKit scene down
                    // and rebuilding it on every open/close made opening a card lag.
                    // The 3D orb (three.js) in the tab's colors.
                    ReactBitsWebView(
                        page: .orb,
                        props: ["colors": {
                            let accent = SquircleTokens.accentColor(for: state.selectedTab)
                            // Darker than the accent, so the ring sits quietly on the black page.
                            let colors = [accent.darkened(0.55).hexRGB, accent.darkened(0.4).hexRGB, accent.darkened(0.15).hexRGB]
                            return (try? JSONSerialization.data(withJSONObject: colors)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
                        }()]
                    )
                    .accessibilityHidden(true)
                        .frame(width: min(geo.size.width, geo.size.height),
                               height: min(geo.size.width, geo.size.height))
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        .opacity(expandedAnnotation == nil ? 1 : 0)
                        .accessibilityHidden(expandedAnnotation != nil)

                    if let expanded = expandedAnnotation {
                        expandedMetricCard(for: expanded)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    } else {
                        ForEach(annotations) { annotation in
                            InteractiveAnnotationGlassBox(
                                annotation: annotation,
                                containerSize: geo.size,
                                accent: SquircleTokens.accentColor(for: state.selectedTab),
                                onTap: {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                                        expandedAnnotation = annotation.label
                                    }
                                }
                            )
                        }
                    }
                } else {
                    // Original static-annotation dashboard — unchanged, kept fully
                    // reachable by setting isInteractiveMode to false.
                    // The 3D orb (three.js) in the tab's colors.
                    ReactBitsWebView(
                        page: .orb,
                        props: ["colors": {
                            let accent = SquircleTokens.accentColor(for: state.selectedTab)
                            // Darker than the accent, so the ring sits quietly on the black page.
                            let colors = [accent.darkened(0.55).hexRGB, accent.darkened(0.4).hexRGB, accent.darkened(0.15).hexRGB]
                            return (try? JSONSerialization.data(withJSONObject: colors)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
                        }()]
                    )
                    .accessibilityHidden(true)
                        .frame(width: min(geo.size.width, geo.size.height),
                               height: min(geo.size.width, geo.size.height))
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)

                    ForEach(annotations) { annotation in
                        AnnotationConnectorView(
                            annotation: annotation,
                            containerSize: geo.size,
                            accent: SquircleTokens.accentColor(for: state.selectedTab)
                        )
                    }
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.82), value: expandedAnnotation)
        }
        .frame(height: 460)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Interactive Mode: Expanded Metric Card
    @ViewBuilder
    private func expandedMetricCard(for label: String) -> some View {
        let accent = SquircleTokens.accentColor(for: state.selectedTab)

        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(label)
                    .font(.appFont(size: 24, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button(action: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                        expandedAnnotation = nil
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(9)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            Group {
                switch label {
                case "Focus": focusMetricContent(accent: accent)
                case "Habits": habitsMetricContent(accent: accent)
                case "Sessions": sessionsMetricContent(accent: accent)
                case "Momentum": momentumMetricContent(accent: accent)
                default: EmptyView()
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassBox(accent: accent, cornerRadius: 28, tintOpacity: 0.07)
        .magicBentoCard(cornerRadius: 28)
    }

    // Real milestone-completion ratio as "efficiency", and this week's saved focus time per day.
    private func focusMetricContent(accent: Color) -> some View {
        let efficiency = state.milestones.isEmpty ? 0 : Int((Double(state.milestones.filter { $0.isDone }.count) / Double(state.milestones.count)) * 100)
        let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let todayIndex = (Calendar.current.component(.weekday, from: Date()) + 5) % 7
        let weekSeconds = state.focusSecondsThisWeek

        return VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(efficiency)%")
                    .font(.appFont(size: 40, weight: .bold))
                    .foregroundColor(.white)
                Text("milestone efficiency")
                    .font(.appFont(size: 12))
                    .foregroundColor(.white.opacity(0.55))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("FOCUS HOURS THIS WEEK")
                    .font(.appFont(size: 10, weight: .bold))
                    .tracking(1.0)
                    .foregroundColor(.white.opacity(0.55))

                // Bars scale to the full height GeometryReader is given,
                // rather than a fixed 120pt box, so the chart fills the card.
                GeometryReader { geo in
                    let barAreaHeight = geo.size.height - 20
                    HStack(alignment: .bottom, spacing: 12) {
                        ForEach(0..<7, id: \.self) { index in
                            let hours = Double(weekSeconds[index]) / 3600.0
                            let barHeight = max(4, min(1.0, hours / 4.0) * barAreaHeight)
                            VStack(spacing: 6) {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(index == todayIndex ? accent : hours > 0 ? accent.opacity(0.5) : Color.white.opacity(0.10))
                                    .frame(height: barHeight)
                                Text(days[index])
                                    .font(.appFont(size: 9, weight: .medium))
                                    .foregroundColor(.white.opacity(0.55))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
    }

    private func habitsMetricContent(accent: Color) -> some View {
        let habitStore = HabitStore.shared
        let percentage = Int((habitStore.weeklyRates().thisWeek * 100).rounded())
        let topStreak = habitStore.activeHabits.map { habitStore.currentStreak($0) }.max() ?? 0

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(percentage)%")
                    .font(.appFont(size: 40, weight: .bold))
                    .foregroundColor(.white)
                Text("this week")
                    .font(.appFont(size: 12))
                    .foregroundColor(.white.opacity(0.55))
            }
            ProgressView(value: Double(percentage), total: 100)
                .tint(accent)
            Text("\(habitStore.activeHabits.count) habits tracked \u{2022} top streak \(topStreak) days")
                .font(.appFont(size: 12))
                .foregroundColor(.white.opacity(0.6))
        }
    }

    private func sessionsMetricContent(accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(state.sessionsStartedToday)")
                    .font(.appFont(size: 40, weight: .bold))
                    .foregroundColor(.white)
                Text("sessions started today")
                    .font(.appFont(size: 12))
                    .foregroundColor(.white.opacity(0.55))
            }
            ProgressView(value: min(Double(state.sessionsStartedToday), 5), total: 5)
                .tint(accent)
            Text("Goal: 5 focus sessions today")
                .font(.appFont(size: 11))
                .foregroundColor(.white.opacity(0.55))
        }
    }

    private func momentumMetricContent(accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(state.readinessStateLabel)
                .font(.appFont(size: 30, weight: .bold))
                .foregroundColor(.white)
            ProgressView(value: Double(state.computedReadinessScore ?? 0), total: 100)
                .tint(accent)
            Text(state.computedReadinessScore == nil
                 ? "Start a focus session, tick a milestone or check off a habit to see today's momentum."
                 : "Today's focus time (out of an hour), milestones done and habits checked off.")
                .font(.appFont(size: 11))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    // MARK: - Top Greeting Header
    private var greetingHeader: some View {
        VStack(alignment: .center, spacing: 5) {
            HStack(spacing: 6) {
                Text("What's up next,")
                    .editorialSerif(size: 28, weight: .semibold)
                    .foregroundColor(.white)
                    .opacity(greetingAppeared ? 1 : 0)
                    .offset(y: greetingAppeared ? 0 : 4)
                    .animation(.easeOut(duration: 0.45), value: greetingAppeared)
                if state.displayName.isEmpty {
                    Text("today?")
                        .scriptAccent(size: 30)
                        .foregroundColor(SquircleTokens.accentColor(for: state.selectedTab))
                        .opacity(greetingAppeared ? 1 : 0)
                        .offset(y: greetingAppeared ? 0 : 4)
                        .animation(.easeOut(duration: 0.45).delay(0.1), value: greetingAppeared)
                } else {
                    // The name writes itself like a signature the first time the dashboard shows after sign-in.
                    SignatureText(
                        text: "\(state.displayName)?",
                        size: 30,
                        delay: 0.25,
                        playKey: AuthManager.shared.user?.id ?? "local",
                        waitsForIntro: true
                    )
                    .foregroundColor(SquircleTokens.accentColor(for: state.selectedTab))
                }
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(state.isLocalOnlyMode ? SquircleTokens.mintAccent : Color.gray)
                    .frame(width: 7, height: 7)
                Text(state.isLocalOnlyMode ? "Saved on this Mac" : "Synced to your account")
                    .font(.appFont(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            greetingAppeared = true
        }
    }

    // MARK: - Quick Session Setup & Duration Pills

}

// MARK: - Dashboard Sphere Annotation Model
private struct DashboardAnnotation: Identifiable {
    let id = UUID()
    let label: String
    /// Label position as a fraction of the stage size.
    let anchor: UnitPoint
    /// Where the connector line ends, near the sphere's surface, as a fraction of the stage size.
    let target: UnitPoint
}

// MARK: - Annotation Label + Connector Line (conceptual callout, not a stat/metric)
private struct AnnotationConnectorView: View {
    let annotation: DashboardAnnotation
    let containerSize: CGSize
    let accent: Color

    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    private var anchorPoint: CGPoint {
        CGPoint(x: containerSize.width * annotation.anchor.x, y: containerSize.height * annotation.anchor.y)
    }
    private var targetPoint: CGPoint {
        CGPoint(x: containerSize.width * annotation.target.x, y: containerSize.height * annotation.target.y)
    }
    private var isEmphasized: Bool { isHovered || isFocused }

    var body: some View {
        ZStack {
            Path { path in
                path.move(to: anchorPoint)
                path.addLine(to: targetPoint)
            }
            .stroke(
                Color.white.opacity(isEmphasized ? 0.55 : 0.22),
                style: StrokeStyle(lineWidth: isEmphasized ? 1.2 : 0.8)
            )

            Circle()
                .fill(accent.opacity(isEmphasized ? 1.0 : 0.75))
                .frame(width: 6, height: 6)
                .shadow(color: accent.opacity(isEmphasized ? 0.9 : 0.5), radius: isEmphasized ? 6 : 3)
                .position(targetPoint)

            Button(action: {}) {
                Text(annotation.label)
                    .font(.appFont(size: 12, weight: isEmphasized ? .bold : .medium))
                    .foregroundColor(.white.opacity(isEmphasized ? 1.0 : 0.75))
                    .shadow(color: accent.opacity(isEmphasized ? 0.6 : 0), radius: 6)
            }
            .buttonStyle(.plain)
            .focused($isFocused)
            .onHover { isHovered = $0 }
            .position(anchorPoint)
            .animation(.easeOut(duration: 0.2), value: isEmphasized)
        }
    }
}

// MARK: - Interactive Mode: Tappable Liquid Glass Annotation Box
// Replaces the plain text + connector line with a prominent rounded glass
// card in the same anchor position; tapping expands it into the central
// metric view (see `expandedMetricCard` on TestDashboardView).
private struct InteractiveAnnotationGlassBox: View {
    let annotation: DashboardAnnotation
    let containerSize: CGSize
    let accent: Color
    let onTap: () -> Void

    @State private var isHovered = false

    private var anchorPoint: CGPoint {
        CGPoint(x: containerSize.width * annotation.anchor.x, y: containerSize.height * annotation.anchor.y)
    }

    var body: some View {
        Button(action: onTap) {
            Text(annotation.label)
                .font(.appFont(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .glassBox(accent: accent, cornerRadius: 16, tintOpacity: isHovered ? 0.22 : 0.08)
                .glassRimLight(cornerRadius: 16)
                .scaleEffect(isHovered ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .position(anchorPoint)
        .animation(.easeOut(duration: 0.2), value: isHovered)
    }
}

// MARK: - Workspace Application Selector Pill
// MARK: - 2. Notes & Reminders
public struct TestProjectStudioView: View {
    private let accent = SquircleTokens.accentColor(for: "artifacts")

    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Spacing.l) {
                PageHeader(title: "Notes & Reminders", subtitle: "Your notes, and every reminder from the Reminders app.")

                // Two balanced columns inside the centered page.
                HStack(alignment: .top, spacing: Spacing.l) {
                    NotesColumn(accent: accent)
                        .frame(minWidth: 360, maxWidth: .infinity)
                    RemindersColumn(accent: accent)
                        .frame(minWidth: 380, maxWidth: .infinity)
                }
            }
            .lockenPage()
        }
        .gradualBlurBottom()
    }
}

private func notesSectionLabel(_ title: String, count: Int? = nil) -> some View {
    HStack(spacing: 8) {
        Text(title)
            .font(.appFont(size: 11, weight: .bold))
            .tracking(1.0)
            .foregroundColor(.white.opacity(0.55))
        if let count, count > 0 {
            Text("\(count)")
                .font(.appFont(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.55))
        }
    }
}

// MARK: Notes

private struct NotesColumn: View {
    @ObservedObject private var state = TestAppStateManager.shared
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                notesSectionLabel("NOTES", count: state.notes.count)
                Spacer()
                Button { state.addNote() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("New Note")
                            .font(.appFont(size: 12, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .borderGlowButton(accent: accent, isProminent: true)
                }
                .buttonStyle(.plain)
            }

            if let id = state.selectedNoteId, let note = state.notes.first(where: { $0.id == id }) {
                NoteEditor(note: note, accent: accent)
                    .id(id)
            }

            let others = state.notes.filter { $0.id != state.selectedNoteId }
            if state.notes.isEmpty {
                Text("No notes yet. Use New Note to write one.")
                    .font(.appFont(size: 12))
                    .foregroundColor(.white.opacity(0.55))
                    .padding(.vertical, 6)
            } else {
                ForEach(others) { note in
                    Button { state.selectedNoteId = note.id } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(note.title.isEmpty ? "Untitled" : note.title)
                                .font(.appFont(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            if !note.body.isEmpty {
                                Text(note.body)
                                    .font(.appFont(size: 12))
                                    .foregroundColor(.white.opacity(0.65))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            Text("Edited \(note.updatedAt.formatted(.relative(presentation: .named)))")
                                .font(.appFont(size: 11))
                                .foregroundColor(.white.opacity(0.55))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .innerObsidianCard(cornerRadius: 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the note")
                }
            }

            AppleNotesSection()
        }
        .padding(Spacing.l)
        .luxuryObsidianCard(cornerRadius: SquircleTokens.radiusLarge)
    }
}

/// Apple Notes under Locken's own notes: connect once, then the most recently edited notes are listed and open
/// in the Notes app. Read through Apple Events; nothing is copied to disk or sent anywhere.
private struct AppleNotesSection: View {
    @ObservedObject private var service = AppleNotesService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionDivider().padding(.vertical, 4)

            HStack(spacing: 10) {
                notesSectionLabel("APPLE NOTES", count: service.isConnected ? service.notes.count : nil)
                Spacer()
                if service.isConnected {
                    if service.isLoading {
                        LogoTraceLoader(size: 16, strokeWidth: 9)
                    }
                    Button { service.refresh() } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .disabled(service.isLoading)
                    .help("Refresh Apple Notes")
                    .accessibilityLabel("Refresh Apple Notes")
                    Button("Disconnect") { service.disconnect() }
                        .buttonStyle(.plain)
                        .font(.appFont(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                } else {
                    Button("Connect") { service.connect() }
                        .buttonStyle(.plain)
                        .font(.appFont(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .accessibilityLabel("Connect Apple Notes")
                }
            }

            if !service.isConnected {
                Text("Show your notes from the Notes app here. They're read on this Mac and never leave it. macOS will ask you to allow Locken to use Notes.")
                    .font(.appFont(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            } else if let error = service.errorMessage {
                Text(error)
                    .font(.appFont(size: 11))
                    .foregroundColor(SquircleTokens.textGold)
                    .fixedSize(horizontal: false, vertical: true)
            } else if service.notes.isEmpty && !service.isLoading {
                Text("No notes in Apple Notes.")
                    .font(.appFont(size: 12))
                    .foregroundColor(.white.opacity(0.55))
            }

            ForEach(service.notes) { note in
                Button { service.open(note) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Text(note.title.isEmpty ? "Untitled" : note.title)
                                .font(.appFont(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.forward.app")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white.opacity(0.45))
                                .accessibilityHidden(true)
                        }
                        if !note.preview.isEmpty {
                            Text(note.preview)
                                .font(.appFont(size: 12))
                                .foregroundColor(.white.opacity(0.65))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        Text("Edited \(note.modified.formatted(.relative(presentation: .named)))")
                            .font(.appFont(size: 11))
                            .foregroundColor(.white.opacity(0.55))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .innerObsidianCard(cornerRadius: 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the note in the Notes app")
            }
        }
    }
}

/// Edits one note in place; every change is saved as you type.
private struct NoteEditor: View {
    @ObservedObject private var state = TestAppStateManager.shared
    let note: TestProjectNote
    let accent: Color

    @State private var title: String
    @State private var text: String
    @FocusState private var isTitleFocused: Bool

    init(note: TestProjectNote, accent: Color) {
        self.note = note
        self.accent = accent
        _title = State(initialValue: note.title)
        _text = State(initialValue: note.body)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Title", text: $title)
                .textFieldStyle(.plain)
                .font(.appFont(size: 16, weight: .bold))
                .foregroundColor(.white)
                .focused($isTitleFocused)

            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .font(.appFont(size: 13))
                .foregroundColor(.white.opacity(0.85))
                .frame(minHeight: 160)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Write something…")
                            .font(.appFont(size: 13))
                            .foregroundColor(.white.opacity(0.55))
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }

            HStack {
                Button(role: .destructive) { state.deleteNote(id: note.id) } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.appFont(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                Spacer()
                Button(action: close) {
                    Text("Done")
                        .font(.appFont(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .borderGlowButton(accent: accent, isProminent: false)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(14)
        .innerObsidianCard(cornerRadius: 12)
        .onAppear { if note.title.isEmpty && note.body.isEmpty { isTitleFocused = true } }
        .onChange(of: title) { save() }
        .onChange(of: text) { save() }
    }

    private func save() {
        state.updateNote(id: note.id, title: title, body: text)
    }

    /// Closes the editor; a note left completely empty is thrown away.
    private func close() {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            state.deleteNote(id: note.id)
        } else {
            state.selectedNoteId = nil
        }
    }
}

// MARK: Reminders

private struct RemindersColumn: View {
    @ObservedObject private var state = TestAppStateManager.shared
    @ObservedObject private var formatter = AITaskFormatter.shared
    @ObservedObject private var ageGate = AgeGate.shared
    let accent: Color

    /// AI is on and allowed for this account (an unknown age is asked for when the digest runs).
    private var showsDigest: Bool {
        state.hasReminderAccess && formatter.isEnabled && ageGate.meetsAIMinimum != false && !state.openReminders.isEmpty
    }
    @State private var newReminder = ""
    /// nil shows every list.
    @State private var listFilter: String?
    @State private var editorDraft: TestAppStateManager.ReminderDraft?
    @State private var isNamingNewList = false
    @State private var newListName = ""

    private typealias Reminder = TestAppStateManager.AppleReminder

    private var visibleOpen: [Reminder] {
        state.openReminders.filter { listFilter == nil || $0.listID == listFilter }
    }

    private var visibleCompleted: [Reminder] {
        state.completedReminders.filter { listFilter == nil || $0.listID == listFilter }
    }

    private var filterTitle: String {
        state.reminderLists.first { $0.id == listFilter }?.title ?? "All Lists"
    }

    /// The list new reminders go into: the filtered list, otherwise the default one.
    private var targetListID: String {
        listFilter ?? state.defaultReminderListID ?? state.reminderLists.first?.id ?? ""
    }

    /// Overdue, today, upcoming, then undated — like the Reminders app's smart lists.
    private var groups: [(title: String, items: [Reminder])] {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now
        var overdue: [Reminder] = [], today: [Reminder] = [], upcoming: [Reminder] = [], undated: [Reminder] = []
        for reminder in visibleOpen {
            guard let due = reminder.due else {
                undated.append(reminder)
                continue
            }
            if reminder.hasDueTime ? due < now : due < startOfToday {
                overdue.append(reminder)
            } else if due < startOfTomorrow {
                today.append(reminder)
            } else {
                upcoming.append(reminder)
            }
        }
        return [("Overdue", overdue), ("Today", today), ("Upcoming", upcoming), ("No date", undated), ("Completed", visibleCompleted)]
            .filter { !$0.items.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                notesSectionLabel("REMINDERS", count: state.hasReminderAccess ? visibleOpen.count : nil)
                Spacer()
                if state.hasReminderAccess { listMenu }
            }

            if state.hasReminderAccess {
                // Makes it clear this is the Reminders app itself, even when there's nothing to show.
                HStack(spacing: 6) {
                    Circle().fill(SquircleTokens.mintAccent).frame(width: 6, height: 6)
                    Text("Connected to Apple Reminders")
                        .font(.appFont(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                    Spacer()
                    Button("Open Reminders") {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") {
                            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.appFont(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
                }
                .accessibilityElement(children: .contain)
            }

            if showsDigest {
                RemindersDigestPanel(accent: accent)
            }

            if state.hasReminderAccess {
                addField

                Toggle(isOn: $state.showsCompletedReminders) {
                    Text("Show completed (last 30 days)")
                        .font(.appFont(size: 11))
                        .foregroundColor(.white.opacity(0.55))
                }
                .toggleStyle(.checkbox)

                if let error = state.reminderError {
                    Text(error)
                        .font(.appFont(size: 11))
                        .foregroundColor(SquircleTokens.textGold)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if visibleOpen.isEmpty && visibleCompleted.isEmpty {
                    Text(listFilter == nil ? "Nothing left to do. You're all caught up." : "Nothing in \(filterTitle).")
                        .font(.appFont(size: 12))
                        .foregroundColor(.white.opacity(0.55))
                        .padding(.vertical, 6)
                }

                ForEach(groups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.title.uppercased())
                            .font(.appFont(size: 10, weight: .bold))
                            .tracking(0.8)
                            .foregroundColor(group.title == "Overdue" ? Self.overdueColor : .white.opacity(0.4))
                        ForEach(group.items) { reminder in
                            row(reminder, isOverdue: group.title == "Overdue")
                        }
                    }
                }
            } else {
                accessCard
            }
        }
        .padding(Spacing.l)
        .luxuryObsidianCard(cornerRadius: SquircleTokens.radiusLarge)
        .onAppear { state.refreshReminders() }
        .sheet(item: $editorDraft) { draft in
            ReminderEditorSheet(draft: draft, accent: accent)
        }
        .alert("New List", isPresented: $isNamingNewList) {
            TextField("List name", text: $newListName)
            Button("Cancel", role: .cancel) { newListName = "" }
            Button("Create") {
                if let id = state.createReminderList(title: newListName) { listFilter = id }
                newListName = ""
            }
        } message: {
            Text("Adds a list to the Reminders app.")
        }
    }

    private static let overdueColor = Color(red: 0.96, green: 0.52, blue: 0.52)

    private var listMenu: some View {
        Menu {
            Button("All Lists") { listFilter = nil }
            Divider()
            ForEach(state.reminderLists) { list in
                Button(list.title) { listFilter = list.id }
            }
            Divider()
            Button("New List…") { isNamingNewList = true }
        } label: {
            Text(filterTitle)
                .font(.appFont(size: 12, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Reminders list")
    }

    private var addField: some View {
        HStack(spacing: 10) {
            TextField("Add a reminder…", text: $newReminder)
                .textFieldStyle(.plain)
                .font(.appFont(size: 13))
                .foregroundColor(.white)
                .onSubmit(addReminder)
            // Full options (date, time, repeat, alert, priority…) for a new reminder.
            Button {
                editorDraft = TestAppStateManager.ReminderDraft(listID: targetListID, title: newReminder)
                newReminder = ""
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("New reminder with details")
            .accessibilityLabel("New reminder with details")
            Button(action: addReminder) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(accent)
            }
            .buttonStyle(.plain)
            .disabled(newReminder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Add reminder")
        }
        .padding(12)
        .innerObsidianCard(cornerRadius: 12)
    }

    private func row(_ reminder: Reminder, isOverdue: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button { state.setReminderCompleted(id: reminder.id, !reminder.isCompleted) } label: {
                Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundColor(reminder.isCompleted ? reminder.color : .white.opacity(0.4))
            }
            .buttonStyle(.plain)
            .help(reminder.isCompleted ? "Mark as not completed" : "Mark as completed")
            .accessibilityLabel(reminder.isCompleted ? "Mark \(reminder.title) as not completed" : "Complete \(reminder.title)")

            // The rest of the row opens the reminder's details.
            Button { editorDraft = TestAppStateManager.ReminderDraft(reminder) } label: {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            if reminder.priority != .none {
                                Text(String(repeating: "!", count: reminder.priority == .high ? 3 : reminder.priority == .medium ? 2 : 1))
                                    .font(.appFont(size: 13, weight: .bold))
                                    .foregroundColor(reminder.color)
                            }
                            Text(reminder.title)
                                .font(.appFont(size: 13, weight: .semibold))
                                .foregroundColor(reminder.isCompleted ? .white.opacity(0.45) : .white)
                                .strikethrough(reminder.isCompleted)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !reminder.notes.isEmpty {
                            Text(reminder.notes)
                                .font(.appFont(size: 11))
                                .foregroundColor(.white.opacity(0.55))
                                .lineLimit(1)
                        }
                        HStack(spacing: 6) {
                            Circle()
                                .fill(reminder.color)
                                .frame(width: 6, height: 6)
                            Text(subtitle(for: reminder))
                                .font(.appFont(size: 11))
                                .foregroundColor(isOverdue ? Self.overdueColor : .white.opacity(0.5))
                                .lineLimit(1)
                            if reminder.repeats != .never {
                                Image(systemName: "repeat")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.45))
                            }
                            if reminder.hasAlert {
                                Image(systemName: "bell.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.45))
                            }
                            if !reminder.url.isEmpty {
                                Image(systemName: "link")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.45))
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the reminder's details")
        }
        .padding(12)
        .innerObsidianCard(cornerRadius: 12)
        .contextMenu {
            Button("Edit…") { editorDraft = TestAppStateManager.ReminderDraft(reminder) }
            Button(reminder.isCompleted ? "Mark as Not Completed" : "Mark as Completed") {
                state.setReminderCompleted(id: reminder.id, !reminder.isCompleted)
            }
            Divider()
            Button("Delete", role: .destructive) { state.deleteReminder(id: reminder.id) }
        }
    }

    private func subtitle(for reminder: Reminder) -> String {
        guard let due = reminder.due else { return reminder.listTitle }
        let date = reminder.hasDueTime
            ? due.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
            : due.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return "\(reminder.listTitle) · \(date)"
    }

    private var accessCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(state.isReminderAccessDenied ? "Locken can't see your reminders" : "See all your reminders here")
                .font(.appFont(size: 13, weight: .semibold))
                .foregroundColor(.white)
            Text(state.isReminderAccessDenied
                 ? "Turn on Locken in System Settings › Privacy & Security › Reminders."
                 : "Shows every reminder from the Reminders app. Tick them off, edit them or add new ones right here.")
                .font(.appFont(size: 12))
                .foregroundColor(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            Button {
                if state.isReminderAccessDenied {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
                        NSWorkspace.shared.open(url)
                    }
                } else {
                    Task { await state.connectReminders() }
                }
            } label: {
                Text(state.isReminderAccessDenied ? "Open System Settings" : "Connect Reminders")
                    .font(.appFont(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .borderGlowButton(accent: accent, isProminent: true)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .innerObsidianCard(cornerRadius: 12)
    }

    private func addReminder() {
        guard !newReminder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        state.addReminder(title: newReminder, listID: targetListID)
        newReminder = ""
    }
}

/// Every option the Reminders app has that EventKit exposes: title, notes, list, date and time, repeat,
/// alert, priority and link. Saves straight to the Reminders app.
private struct ReminderEditorSheet: View {
    @ObservedObject private var state = TestAppStateManager.shared
    @Environment(\.dismiss) private var dismiss
    @State var draft: TestAppStateManager.ReminderDraft
    let accent: Color
    @State private var confirmingDelete = false

    private var canSave: Bool { !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(draft.reminderID == nil ? "New Reminder" : "Reminder Details")
                .font(.appFont(size: 16, weight: .bold))
                .foregroundColor(.white)

            TextField("Title", text: $draft.title)
                .textFieldStyle(.plain)
                .font(.appFont(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .padding(10)
                .background(fieldBackground)

            TextEditor(text: $draft.notes)
                .scrollContentBackground(.hidden)
                .font(.appFont(size: 13))
                .foregroundColor(.white.opacity(0.85))
                .frame(height: 64)
                .padding(6)
                .background(fieldBackground)
                .overlay(alignment: .topLeading) {
                    if draft.notes.isEmpty {
                        Text("Notes")
                            .font(.appFont(size: 13))
                            .foregroundColor(.white.opacity(0.55))
                            .padding(.leading, 11)
                            .padding(.top, 6)
                            .allowsHitTesting(false)
                    }
                }

            field("List") {
                Picker("List", selection: $draft.listID) {
                    ForEach(state.reminderLists) { list in
                        Text(list.title).tag(list.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }

            field("Date") {
                Toggle("", isOn: $draft.hasDate.animation(.easeOut(duration: 0.15)))
                    .toggleStyle(GlassSwitchToggleStyle())
                    .labelsHidden()
                if draft.hasDate {
                    DatePicker("", selection: $draft.date, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.field)
                }
            }

            field("Time") {
                Toggle("", isOn: $draft.hasTime.animation(.easeOut(duration: 0.15)))
                    .toggleStyle(GlassSwitchToggleStyle())
                    .labelsHidden()
                    .disabled(!draft.hasDate)
                if draft.hasDate && draft.hasTime {
                    DatePicker("", selection: $draft.date, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.field)
                }
            }

            field("Repeat") {
                if draft.hasDate {
                    JellyRadioPicker(
                        items: TestAppStateManager.ReminderRepeat.allCases.map(\.rawValue),
                        selection: Binding(
                            get: { draft.repeats.rawValue },
                            set: { draft.repeats = TestAppStateManager.ReminderRepeat(rawValue: $0) ?? .never }
                        ),
                        label: "Repeat"
                    )
                } else {
                    hint("Set a date to repeat")
                }
            }

            field("Alert") {
                Toggle("", isOn: $draft.hasAlert)
                    .toggleStyle(GlassSwitchToggleStyle())
                    .labelsHidden()
                    .disabled(!draft.hasDate)
                hint(draft.hasDate ? (draft.hasTime ? "Notify at the due time" : "Notify at 9:00 AM that day") : "Set a date for an alert")
            }

            field("Priority") {
                JellyRadioPicker(
                    items: TestAppStateManager.ReminderPriority.allCases.map(\.rawValue),
                    selection: Binding(
                        get: { draft.priority.rawValue },
                        set: { draft.priority = TestAppStateManager.ReminderPriority(rawValue: $0) ?? .none }
                    ),
                    label: "Priority"
                )
            }

            field("Link") {
                TextField("https://", text: $draft.url)
                    .textFieldStyle(.plain)
                    .font(.appFont(size: 13))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(fieldBackground)
            }

            if let error = state.reminderError {
                Text(error)
                    .font(.appFont(size: 11))
                    .foregroundColor(SquircleTokens.textGold)
            }

            HStack {
                if draft.reminderID != nil {
                    Button(role: .destructive) { confirmingDelete = true } label: {
                        Label("Delete", systemImage: "trash")
                            .font(.appFont(size: 12))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    if state.saveReminder(draft) { dismiss() }
                } label: {
                    Text("Save")
                        .font(.appFont(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 7)
                        .borderGlowButton(accent: accent, isProminent: true)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.45)
            }
        }
        .padding(24)
        .frame(width: 580)
        .background(SquircleTokens.bgBottom(for: "artifacts"))
        .onAppear { state.reminderError = nil }
        .confirmationDialog("Delete this reminder from Reminders?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                if let id = draft.reminderID { state.deleteReminder(id: id) }
                dismiss()
            }
        }
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.appFont(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 64, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.appFont(size: 11))
            .foregroundColor(.white.opacity(0.55))
    }
}

// MARK: - 4. Customize & Settings View
public struct TestSettingsView: View {
    @ObservedObject var state = TestAppStateManager.shared
    @ObservedObject private var formatter = AITaskFormatter.shared
    @State private var apiKeyInput: String = ""
    @State private var apiKeyError: String?
    @State private var confirmingAccountDeletion = false
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var ageGate = AgeGate.shared
    @State private var birthMonth: Int?
    @State private var birthYear: Int?

    private var aiSubtitle: String {
        switch formatter.provider {
        case .claude: return "Claude · \(AITaskFormatter.claudeModel)"
        case .openAI: return "ChatGPT · \(AITaskFormatter.openAIModels[0])"
        case .gemini: return "Gemini · newest Flash model your key can use"
        case nil: return "Rewrites vague session goals into specific ones"
        }
    }

    private func saveAPIKey() {
        do {
            try formatter.saveAPIKey(apiKeyInput)
            apiKeyInput = ""
            apiKeyError = nil
        } catch {
            apiKeyError = error.localizedDescription
        }
    }

    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Spacing.l) {
                PageHeader(title: "Settings", subtitle: "Connections, security, focus tools and your account.")

                // Two columns when the window is wide enough (same width as every other page), otherwise one column,
                // so Settings never pushes the window wider than it is.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: Spacing.l) {
                        appColumn.frame(minWidth: 0, maxWidth: .infinity, alignment: .top)
                        securityColumn.frame(minWidth: 0, maxWidth: .infinity, alignment: .top)
                    }
                    VStack(alignment: .leading, spacing: Spacing.l) {
                        appColumn
                        securityColumn
                    }
                }
            }
            // Same width and margins as every other page.
            .lockenPage(maxWidth: PageWidth.wide)
        }
        .gradualBlurBottom()
    }

    @ViewBuilder private var appColumn: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
                Text("Locken")
                    .font(.appFont(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .accessibilityAddTraits(.isHeader)

                CommitmentModeToggle()
                    .padding(Spacing.l)
                    .innerObsidianCard(cornerRadius: 16)
                    .scrollReveal()

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Intelligent Rephrase")
                                .font(.appFont(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                            Text(aiSubtitle)
                                .font(.appFont(size: 11))
                                .foregroundColor(.white.opacity(0.50))
                        }
                        Spacer()
                        Toggle("", isOn: $formatter.isEnabled)
                            .toggleStyle(GlassSwitchToggleStyle())
                            .accessibilityLabel("Intelligent Rephrase")
                    }

                    if formatter.isEnabled && ageGate.meetsAIMinimum == nil {
                        aiAgeQuestion
                    } else if formatter.isEnabled && ageGate.meetsAIMinimum == false {
                        aiAgeRestricted
                    } else if formatter.isEnabled {
                        // Privacy: say exactly what leaves the Mac, and to whom.
                        Text("When you rephrase a goal or start a session, its goal, length and workspace app, plus your upcoming Canvas assignment titles, are sent to \(formatter.provider?.displayName ?? "the AI service you add a key for") to write the rewrite and milestones. A reminders or week digest sends your open reminders' titles, due dates and lists, or this week's event and assignment titles and times, only when you press its button. Nothing else is shared.")
                            .font(.appFont(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)

                        if let provider = formatter.provider {
                            HStack(spacing: 8) {
                                Image(systemName: "key.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.5))
                                Text("\(provider.displayName) API key saved in your Keychain")
                                    .font(.appFont(size: 12))
                                    .foregroundColor(.white.opacity(0.75))
                                Spacer()
                                Button("Remove") { formatter.removeAPIKey() }
                                    .buttonStyle(.plain)
                                    .font(.appFont(size: 12, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        } else {
                            HStack(spacing: 8) {
                                SecureField("Paste a Claude, ChatGPT (OpenAI) or Gemini API key", text: $apiKeyInput)
                                    .textFieldStyle(.plain)
                                    .font(.appFont(size: 12))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.white.opacity(0.04))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .onSubmit(saveAPIKey)
                                Button(action: saveAPIKey) {
                                    Text("Save")
                                        .font(.appFont(size: 12, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .borderGlowButton(accent: SquircleTokens.accentColor(for: "customize"), isProminent: true)
                                }
                                .buttonStyle(.plain)
                                .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                            if let apiKeyError {
                                Text(apiKeyError)
                                    .font(.appFont(size: 11))
                                    .foregroundColor(SquircleTokens.textGold)
                            }
                        }
                    }
                }
                .padding(Spacing.l)
                .innerObsidianCard(cornerRadius: 16)
                .scrollReveal()

                FocusSetupCard()
                    .scrollReveal()

                AssistantHotkeyCard()
                    .scrollReveal()

                OtherMediaCard()
                    .scrollReveal()

                LaunchAtLoginCard()
                    .scrollReveal()

                BlockedAppsCard()
                    .scrollReveal()

                HabitFeaturesCard()
                    .scrollReveal()

                UpdatesCard()
                    .scrollReveal()

                FeedbackCard()
                    .scrollReveal()
        }
    }

    @ViewBuilder private var securityColumn: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
                // Everything about security and privacy, together.
                Text("Security & privacy")
                    .font(.appFont(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .accessibilityAddTraits(.isHeader)

                // Sign-out revokes the session on the server, then clears the Keychain.
                AccountSecurityCard()
                    .scrollReveal()

                TwoFactorCard()
                    .scrollReveal()

                CalendarConnectionsCard()
                    .scrollReveal()

                PermissionsCard()
                    .scrollReveal()

                LocalDataCard()
                    .scrollReveal()

                LegalCard()
                    .scrollReveal()

                // Account deletion (App Store 5.1.1(v), GDPR): server first, then this Mac's data for the account.
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Delete Account")
                                .font(.appFont(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                            Text("Permanently deletes your Locken account and everything this Mac keeps for it.")
                                .font(.appFont(size: 11))
                                .foregroundColor(.white.opacity(0.55))
                        }
                        Spacer()
                        Button(role: .destructive) { confirmingAccountDeletion = true } label: {
                            Text("Delete Account…")
                                .quietAction()
                                .foregroundColor(Color(red: 0.96, green: 0.52, blue: 0.52))
                        }
                        .buttonStyle(.plain)
                        .disabled(auth.isWorking)
                    }
                    if let error = auth.errorMessage {
                        Text(error)
                            .font(.appFont(size: 11))
                            .foregroundColor(SquircleTokens.textGold)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Spacing.l)
                .innerObsidianCard(cornerRadius: 16)
                .scrollReveal()
                .confirmationDialog("Delete your Locken account?", isPresented: $confirmingAccountDeletion) {
                    Button("Delete Account", role: .destructive) {
                        Task { _ = await auth.deleteAccount() }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This permanently deletes your account and synced data, plus this Mac's notes, habits, milestones, stats and Canvas link for it. It can't be undone.")
                }
        }
    }

    /// AI providers' terms require 18+. Asked once per account on this Mac, the same neutral way as sign-up.
    private var aiAgeQuestion: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Enter your date of birth to use AI features.")
                .font(.appFont(size: 12))
                .foregroundColor(.white.opacity(0.75))
            HStack(spacing: 10) {
                BirthMonthYearPicker(month: $birthMonth, year: $birthYear)
                Spacer()
                Button {
                    if let birthMonth, let birthYear { ageGate.save(month: birthMonth, year: birthYear) }
                } label: {
                    Text("Save")
                        .font(.appFont(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .borderGlowButton(accent: SquircleTokens.accentColor(for: "customize"), isProminent: true)
                }
                .buttonStyle(.plain)
                .disabled(birthMonth == nil || birthYear == nil)
            }
        }
    }

    private var aiAgeRestricted: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AI features are for people 18 and older, because Claude's and Gemini's terms require it. Everything else in Locken works without them.")
                .font(.appFont(size: 11))
                .foregroundColor(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            // A key saved before the age check stays removable.
            if let provider = formatter.provider {
                HStack {
                    Text("\(provider.displayName) API key saved in your Keychain")
                        .font(.appFont(size: 12))
                        .foregroundColor(.white.opacity(0.75))
                    Spacer()
                    Button("Remove") { formatter.removeAPIKey() }
                        .buttonStyle(.plain)
                        .font(.appFont(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
    }
}

// MARK: - 5. Focus Session View (Wine Burgundy & Restrained Rose)
public struct TestFocusSessionView: View {
    @ObservedObject var state = TestAppStateManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Held in @State (not @StateObject) so scroll updates re-render only the split wrappers, never this whole tab.
    @State private var split = FocusSplitDriver()
    @State private var cardsHeight: CGFloat = 0
    @State private var headerHeight: CGFloat = 96
    @State private var hover = FocusHoverTracker()

    /// A session is running, or paused partway: the page is only its timer (left) and its steps (right). The hero and
    /// everything about starting a session (your own goal, Canvas, videos) are out of the way until it ends.
    private var hasSession: Bool {
        state.isTimerActive || (state.isGoalDefined && state.timerSecondsRemaining > 0 && state.timerSecondsRemaining < state.timerTotalSeconds)
    }

    public var body: some View {
        Group {
            if hasSession { sessionBody } else { setupBody }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: hasSession)
        // The start-session pop-up, centered over this page (not the whole window) and faded in smoothly.
        .overlay {
            if state.isSessionSetupPresented {
                SessionSetupModal()
                    .transition(.opacity)
            }
        }
    }

    /// The timer's clock dial on the left half, the session's steps on the right half.
    private var sessionBody: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                header
                HStack(alignment: .top, spacing: 24) {
                    FocusTimerCard(showsDial: true)
                    FocusMilestonesCard()
                }
            }
            .lockenPage(maxWidth: PageWidth.wide)
        }
        .gradualBlurBottom()
    }

    private var setupBody: some View {
        GeometryReader { geometry in
            // A centered column, capped like every other page, with equal margins on both sides.
            let contentWidth = min(max(geometry.size.width - PageWidth.margin * 2, 0), PageWidth.wide)
            let layout = FocusSplitLayout(
                contentWidth: contentWidth,
                sideInset: (geometry.size.width - contentWidth) / 2,
                fullHeight: geometry.size.height,
                topInset: headerHeight
            )

            ZStack(alignment: .topLeading) {
                // DitherVeil (React Bits) — pinned behind the scroll view, so scrolling works anywhere on the page;
                // hover still reaches it through its tracking areas.
                // Web views draw above SwiftUI overlays, so the hero hides while the start pop-up is open (otherwise its
                // pixels show through the dimmed backdrop).
                FocusSplitHero(driver: split, hover: hover, layout: layout)
                    .opacity(state.isSessionSetupPresented ? 0 : 1)
                    .animation(.easeOut(duration: 0.15), value: state.isSessionSetupPresented)

                ScrollView(showsIndicators: false) {
                    // Exact scroll length: the pin distance plus only what the settled cards overflow, so the
                    // cards come to rest under the header instead of scrolling on up beneath it.
                    Color.clear
                        .frame(width: layout.contentWidth, height: layout.contentHeight(cardsHeight: cardsHeight))
                        .overlay(alignment: .top) {
                            FocusSplitColumn(driver: split, layout: layout) {
                                VStack(spacing: 24) {
                                    FocusTimerCard()
                                    FocusOwnGoalCard()
                                    CanvasAssignmentsCard()
                                    SessionVideosCard()
                                }
                                .frame(width: layout.columnWidth)
                                .onGeometryChange(for: CGFloat.self) { proxy in
                                    proxy.size.height
                                } action: { newHeight in
                                    cardsHeight = newHeight
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                }
                .onScrollGeometryChange(for: CGFloat.self) { scroll in
                    scroll.contentOffset.y
                } action: { _, offset in
                    split.update(offset: offset, reduceMotion: reduceMotion)
                }

                // Cards that scroll up under the header fade out instead of overlapping the title.
                .mask {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: headerHeight)
                        Color.black
                    }
                }
                // And the page blurs toward its bottom edge while there is more to scroll to, like the other pages (after the
                // mask, so the band itself isn't masked).
                .gradualBlurBottom()

                // The header ignores the pointer so the scroll view underneath takes wheel events here too.
                header
                    .frame(width: layout.contentWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.top, PageWidth.margin)
                    .padding(.bottom, Spacing.m)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { newHeight in
                        headerHeight = newHeight
                    }
                    .allowsHitTesting(false)
            }
            // The hero sits behind the scroll view, so track the pointer here and forward it (see FocusSplitHero).
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): hover.location = location
                case .ended: hover.location = nil
                }
            }
        }
    }

    private var header: some View {
            PageHeader(title: "Focus Enclave", subtitle: "Deep work session with an optional distraction shield.") {
                Label(
                    state.isShieldActive ? "Shield Engaged" : "Shield Paused",
                    systemImage: state.isShieldActive ? "shield.fill" : "shield.slash"
                )
                .font(.appFont(size: 12, weight: .bold))
                .foregroundStyle(
                    state.isShieldActive ? SquircleTokens.readableAccent(for: "focus") : .white.opacity(0.55),
                    .white.opacity(0.85)
                )
            }
    }
}

private struct FocusTimerCard: View {
    @ObservedObject var state = TestAppStateManager.shared
    /// With a session: the clock dial, the time inside its ring. Without one: the plain time.
    var showsDial = false

    /// Nothing to resume yet: no goal has been set (first launch, or the last session finished).
    private var needsSetup: Bool { !state.isGoalDefined && !state.isTimerActive }

    private var formattedTime: String {
        let minutes = state.timerSecondsRemaining / 60
        let seconds = state.timerSecondsRemaining % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var body: some View {
            // Countdown Timer Card
            VStack(spacing: 12) {
                if showsDial {
                    // The dial is 368 pt across; a narrower column gets a smaller one.
                    ViewThatFits(in: .horizontal) {
                        FocusDial()
                        FocusDial(ringDiameter: 230)
                    }
                } else {
                    Text(formattedTime)
                        .font(.appFont(size: 54, weight: .bold))
                        .foregroundColor(.white)
                        .tracking(2.0)

                    Text(needsSetup ? "No goal set yet" : state.focusGoal)
                        .font(.appFont(size: 14, weight: .bold))
                        .foregroundColor(needsSetup ? .white.opacity(0.45) : SquircleTokens.readableAccent(for: "focus"))
                }

                HStack(spacing: 16) {
                    Button(action: {
                        // Without a goal there's nothing to resume: set one up here instead of leaving the page.
                        if needsSetup {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.9)) { state.isSessionSetupPresented = true }
                            return
                        }
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                            state.toggleTimer()
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: state.isTimerActive ? "pause.fill" : "play.fill")
                            Text(state.isTimerActive ? "Pause Focus" : needsSetup ? "Start Focus" : "Resume Focus")
                                .font(.appFont(size: 15, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .borderGlowButton(accent: SquircleTokens.accentColor(for: "focus"), isProminent: true)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                            state.resetTimer()
                        }
                    }) {
                        Text("Reset")
                            .quietAction()
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 6)

                if let adjustment = state.lastTimeAdjustment {
                    Text(adjustment)
                        .font(.appFont(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }

                AdaptiveTimeToggle()
                    .padding(.top, 6)
            }
            .padding(Spacing.l)
            .frame(maxWidth: .infinity)
            .luxuryObsidianCard(cornerRadius: SquircleTokens.radiusLarge)
        }
}

/// Start a session on a goal the student types, the same way a Canvas assignment row starts one:
/// type it, set a time limit, start. Hidden while a session is running.
private struct FocusOwnGoalCard: View {
    @ObservedObject private var state = TestAppStateManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var goal = ""
    @State private var focusMinutes = 25

    private let accent = SquircleTokens.accentColor(for: "focus")
    private var trimmedGoal: String { goal.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        if !state.isTimerActive {
            VStack(alignment: .leading, spacing: 14) {
                Text("YOUR OWN GOAL")
                    .font(.appFont(size: 11, weight: .bold))
                    .tracking(1.0)
                    .foregroundColor(.white.opacity(0.55))

                TextField("e.g. Write the introduction for my history paper", text: $goal, axis: .vertical)
                    .lineLimit(1...3)
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
                    .onSubmit(start)
                    .accessibilityLabel("Your own goal")

                if !trimmedGoal.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("TIME LIMIT")
                                .font(.appFont(size: 10, weight: .bold))
                                .tracking(1.0)
                                .foregroundColor(.white.opacity(0.55))
                            Spacer()
                            Text("\(focusMinutes) min")
                                .font(.appFont(size: 13, weight: .bold))
                                .foregroundColor(.white)
                                .contentTransition(.numericText(value: Double(focusMinutes)))
                        }

                        Slider(
                            value: Binding(get: { Double(focusMinutes) }, set: { focusMinutes = Int($0) }),
                            in: 5...180,
                            step: 5
                        )
                        .tint(accent)
                        .accessibilityLabel("Time limit in minutes")
                        .accessibilityValue("\(focusMinutes) minutes")

                        HStack {
                            Spacer()
                            Button(action: start) {
                                HStack(spacing: 8) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 11, weight: .bold))
                                    Text("Start \(focusMinutes) min focus")
                                        .font(.appFont(size: 13, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 9)
                                .borderGlowButton(accent: accent, isProminent: true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Start \(focusMinutes) minute focus on your goal")
                        }
                    }
                    .transition(.opacity)
                }
            }
            .padding(Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .luxuryObsidianCard(cornerRadius: SquircleTokens.radiusLarge)
            .animation(.easeOut(duration: 0.2), value: trimmedGoal.isEmpty)
        }
    }

    private func start() {
        guard !trimmedGoal.isEmpty else { return }
        state.startFocus(goal: trimmedGoal, minutes: focusMinutes, playIntro: !reduceMotion)
        goal = ""
    }
}

private struct FocusMilestonesCard: View {
    @ObservedObject var state = TestAppStateManager.shared
    @State private var newMilestoneText: String = ""

    var body: some View {
            // Session Milestones List
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Steps for this session")
                        .font(.appFont(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Text(state.isCreatingMilestones
                         ? "Creating steps for this session…"
                         : state.milestones.isEmpty
                         ? "Steps for your session appear here when it starts. Add your own below."
                         : "\(state.milestones.filter(\.isDone).count) of \(state.milestones.count) done")
                        .font(.appFont(size: 12))
                        .foregroundColor(.white.opacity(0.55))
                    if let note = state.milestonesNote, !state.isCreatingMilestones {
                        Text(note)
                            .font(.appFont(size: 11))
                            .foregroundColor(.white.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if state.isCreatingMilestones {
                    LogoTraceLoader(size: 16, strokeWidth: 9)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }

                ForEach(state.milestones) { milestone in
                    HStack(spacing: 12) {
                        // The whole row ticks the milestone, not just the circle.
                        Button(action: { state.toggleMilestone(id: milestone.id) }) {
                            HStack(spacing: 12) {
                                Image(systemName: milestone.isDone ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 16))
                                    .foregroundColor(milestone.isDone ? SquircleTokens.mintAccent : .white.opacity(0.40))

                                Text(milestone.text)
                                    .font(.appFont(size: 13))
                                    .foregroundColor(milestone.isDone ? .white.opacity(0.45) : .white)
                                    .strikethrough(milestone.isDone)
                                    .multilineTextAlignment(.leading)

                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(milestone.text)
                        .accessibilityAddTraits(milestone.isDone ? .isSelected : [])
                        .help(milestone.isDone ? "Mark as not done" : "Mark as done")

                        Button(action: { state.removeMilestone(id: milestone.id) }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white.opacity(0.35))
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(milestone.text)")
                        .help("Remove milestone")
                    }
                    .padding(14)
                    .innerObsidianCard(cornerRadius: 12)
                    // No scrollReveal here: this card isn't in a scroll view, so the rows would stay invisible.
                }

                // Quick Add Milestone
                HStack {
                    TextField("Add new milestone...", text: $newMilestoneText)
                        .onSubmit(addMilestone)
                        .textFieldStyle(.plain)
                        .font(.appFont(size: 13))
                        .foregroundColor(.white)

                    Button(action: addMilestone) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(SquircleTokens.accentColor(for: "focus"))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add milestone")
                    .help("Add milestone")
                    .disabled(newMilestoneText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(12)
                .innerObsidianCard(cornerRadius: 12)
            }
            .padding(Spacing.l)
            .luxuryObsidianCard(cornerRadius: SquircleTokens.radiusLarge)
        }

    private func addMilestone() {
        guard !newMilestoneText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        state.addMilestone(text: newMilestoneText)
        newMilestoneText = ""
    }
}

// MARK: - Focus split: GSAP-style pin + scrub with Lenis-style smoothing, natively
// Equivalent of Lenis ({ lerp }) feeding gsap.timeline({ scrollTrigger: { pin: true, scrub } }): one smoothed scroll
// offset drives everything. For the first `pinDistance` points the cards stay pinned while scrolling plays the
// timeline; afterwards they scroll (still smoothed). The timeline is sequenced so the columns part before the cards
// rise, and each phase uses a cubic ease-in-out (GSAP power2.inOut).
@MainActor
private final class FocusSplitDriver: ObservableObject {
    /// The scroll view's real offset.
    @Published private(set) var rawOffset: CGFloat = 0
    /// The offset everything is drawn at — eases toward `rawOffset` like Lenis.
    @Published private(set) var smoothOffset: CGFloat = 0

    private var displayLink: CADisplayLink?
    private var displayTick: DisplayTick?
    private var lastTick = Date()
    /// Exponential catch-up time constant (≈ Lenis lerp 0.065 at 60fps).
    private let smoothing: Double = 0.25

    var progress: CGFloat { min(max(smoothOffset / FocusSplitLayout.pinDistance, 0), 1) }

    func update(offset: CGFloat, reduceMotion: Bool) {
        rawOffset = offset
        if reduceMotion {
            smoothOffset = offset
            return
        }
        guard displayLink == nil, abs(rawOffset - smoothOffset) > 0.25 else { return }
        lastTick = Date()
        // One step per frame the screen draws (a fixed 120 Hz timer ran the page's update twice per frame on a 60 Hz screen).
        let tick = DisplayTick { [weak self] in MainActor.assumeIsolated { self?.tick() } }
        guard let link = (NSScreen.main ?? NSScreen.screens.first)?.displayLink(target: tick, selector: #selector(DisplayTick.fire)) else { return }
        // .common keeps it ticking while the scroll view is tracking the trackpad.
        link.add(to: .main, forMode: .common)
        displayTick = tick
        displayLink = link
    }

    private func tick() {
        let now = Date()
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now
        let step = CGFloat(1 - exp(-dt / smoothing))
        let next = smoothOffset + (rawOffset - smoothOffset) * step
        if abs(rawOffset - next) < 0.25 {
            smoothOffset = rawOffset
            displayLink?.invalidate()
            displayLink = nil
            displayTick = nil
        } else {
            smoothOffset = next
        }
    }
}

/// The target of a display link: calls its closure once per frame.
private final class DisplayTick: NSObject {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func fire() { action() }
}

private struct FocusSplitLayout: Equatable {
    static let pinDistance: CGFloat = 480
    static let columnGap: CGFloat = 24
    static let bottomPadding: CGFloat = 60

    let contentWidth: CGFloat
    /// Margin from the page edge to the centered column, the same on both sides.
    let sideInset: CGFloat
    /// The scroll view's full height (it spans the header area too).
    let fullHeight: CGFloat
    /// Height of the header drawn over the top of the scroll view.
    let topInset: CGFloat

    var viewportHeight: CGFloat { max(fullHeight - topInset, 0) }
    var columnWidth: CGFloat { max((contentWidth - Self.columnGap) / 2, 0) }
    var heroHeight: CGFloat { max(min(600, viewportHeight - 40), 200) }
    /// The cards' resting top, just below the hero.
    var cardsRestTop: CGFloat { topInset + heroHeight + 24 }
    /// Where the cards settle: just under the header.
    var settledTop: CGFloat { topInset + 8 }

    func contentHeight(cardsHeight: CGFloat) -> CGFloat {
        max(fullHeight, cardsHeight + settledTop + Self.bottomPadding) + Self.pinDistance
    }

    /// Cubic ease-in-out (GSAP power2.inOut).
    static func ease(_ p: CGFloat) -> CGFloat {
        p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2
    }

    /// Eased progress of the part of the timeline running from `start` to `end` (both 0…1).
    private static func phase(_ p: CGFloat, _ start: CGFloat, _ end: CGFloat) -> CGFloat {
        ease(min(max((p - start) / (end - start), 0), 1))
    }

    /// Hero ↔ cards separate sideways over the first 45% of the pin…
    static func separation(_ p: CGFloat) -> CGFloat { phase(p, 0, 0.45) }
    /// …and only once they're in their own columns do the cards rise and the hero settle to the middle, so the
    /// two never overlap mid-move.
    static func rise(_ p: CGFloat) -> CGFloat { phase(p, 0.45, 1) }

    /// Horizontal shift from the cards' natural centered position: 0 at rest, flush with the right edge when split.
    func cardsX(_ separation: CGFloat) -> CGFloat { (contentWidth - columnWidth) / 2 * separation }
    /// The cards' drawn top, from resting below the hero to settled under the header.
    func cardsY(_ rise: CGFloat) -> CGFloat { cardsRestTop + (settledTop - cardsRestTop) * rise }
    func heroX(_ separation: CGFloat) -> CGFloat { sideInset + (contentWidth - columnWidth) / 2 * (1 - separation) }
    func heroY(_ rise: CGFloat) -> CGFloat { topInset + max((viewportHeight - heroHeight) / 2, 0) * rise }
}

/// Moves the cards: draws them at the smoothed offset, pinned during the pin, then the timeline's position.
private struct FocusSplitColumn<Content: View>: View {
    @ObservedObject var driver: FocusSplitDriver
    let layout: FocusSplitLayout
    @ViewBuilder let content: Content

    var body: some View {
        let smooth = driver.smoothOffset
        let progress = driver.progress
        // (raw − smooth) swaps the real scroll for the smoothed one; the pin term cancels scrolling during the pin.
        let pin = min(max(smooth, 0), FocusSplitLayout.pinDistance)
        content
            .offset(
                x: layout.cardsX(FocusSplitLayout.separation(progress)),
                y: driver.rawOffset - smooth + pin + layout.cardsY(FocusSplitLayout.rise(progress))
            )
    }
}

/// Pointer location over the Focus tab, kept apart from the tab's own state so mouse moves only re-render the hero.
@MainActor
private final class FocusHoverTracker: ObservableObject {
    @Published var location: CGPoint?
}

/// The pinned DitherVeil hero, sliding from centered-on-top to the middle of the left half.
private struct FocusSplitHero: View {
    @ObservedObject var driver: FocusSplitDriver
    @ObservedObject var hover: FocusHoverTracker
    let layout: FocusSplitLayout

    var body: some View {
        let separation = FocusSplitLayout.separation(driver.progress)
        let rise = FocusSplitLayout.rise(driver.progress)
        let origin = CGPoint(x: layout.heroX(separation), y: layout.heroY(rise))
        let pointer: ReactBitsWebView.PointerForwarding = {
            guard let location = hover.location else { return .outside }
            let local = CGPoint(x: location.x - origin.x, y: location.y - origin.y)
            let inside = (0...layout.columnWidth).contains(local.x) && (0...layout.heroHeight).contains(local.y)
            return inside ? .at(local) : .outside
        }()
        // One fixed size (resizing would re-run DitherVeil's dithering every frame); its image is height-bound,
        // so half width shows it exactly as full width would.
        ReactBitsWebView(
            page: .ditherVeil,
            // White dots at 70% opacity, so the figure sits softly on the Focus page's 15%-violet tile.
            props: ["paperColor": Color.white.hexRGB],
            pointerForwarding: pointer
        )
            .opacity(0.7)
            .frame(width: layout.columnWidth, height: layout.heroHeight)
            .clipShape(RoundedRectangle(cornerRadius: SquircleTokens.radiusLarge, style: .continuous))
            .offset(x: layout.heroX(separation), y: layout.heroY(rise))
            .accessibilityHidden(true)
    }
}

/// The dial's fixed parts: sixty ticks (every fifth one longer) and the faint ring the time shrinks along. Equatable and drawn
/// into one bitmap, so the dial's per-second updates only redraw the marker and the shrinking ring.
private struct FocusDialFace: View, Equatable {
    let ringDiameter: CGFloat
    private var dialRadius: CGFloat { ringDiameter / 2 + 22 }

    var body: some View {
        ZStack {
            ForEach(0..<60, id: \.self) { tick in
                Capsule()
                    .fill(Color.white.opacity(tick % 5 == 0 ? 0.35 : 0.14))
                    .frame(width: tick % 5 == 0 ? 2 : 1, height: tick % 5 == 0 ? 10 : 6)
                    .offset(y: -dialRadius)
                    .rotationEffect(.degrees(Double(tick) * 6))
            }
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 10)
                .frame(width: ringDiameter, height: ringDiameter)
        }
        // The dial's own size, so the ticks (drawn out at the dial's radius) aren't clipped by the bitmap.
        .frame(width: (dialRadius + 12) * 2, height: (dialRadius + 12) * 2)
        .drawingGroup()
    }
}

/// The clock dial: sixty ticks, a ticking marker, the ring that shrinks toward 12 o'clock, and inside it the time as liquid
/// glass over the session's goal. Shown by the full-screen countdown and by the Focus page while a session runs.
private struct FocusDial: View {
    @ObservedObject var state = TestAppStateManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let accent = SquircleTokens.accentColor(for: "focus")
    /// 300 on the full-screen countdown; smaller where the column is narrow.
    var ringDiameter: CGFloat = 300
    private var dialRadius: CGFloat { ringDiameter / 2 + 22 }

    private var remaining: Int { state.timerSecondsRemaining }
    private var isComplete: Bool { remaining == 0 }
    private var progress: Double {
        state.timerTotalSeconds > 0 ? Double(remaining) / Double(state.timerTotalSeconds) : 0
    }
    /// Advances one notch per elapsed second, like a clock's second hand. Never wraps to 0, so the
    /// animation always steps forward instead of spinning back around at each minute.
    private var secondHandAngle: Double {
        Double(max(state.timerTotalSeconds - remaining, 0)) * 6
    }
    private var timeText: String {
        String(format: "%02d:%02d", remaining / 60, remaining % 60)
    }

    /// How far the ring shrinks each second, in points. A long session moves it a fraction of a point a second, which needs no
    /// smoothing; animating it anyway kept the whole page redrawing at the screen's frame rate for the whole session.
    private var ringStep: CGFloat {
        state.timerTotalSeconds > 0 ? .pi * ringDiameter / CGFloat(state.timerTotalSeconds) : 0
    }

    var body: some View {
        ZStack {
            // Clock face (sixty ticks and the faint ring): fixed, so it is drawn once and kept as a bitmap.
            FocusDialFace(ringDiameter: ringDiameter).equatable()

            // Ticking second hand marker
            Circle()
                .fill(accent)
                .frame(width: 7, height: 7)
                .offset(y: -dialRadius)
                .rotationEffect(.degrees(secondHandAngle))
                .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.6), value: secondHandAngle)
                .opacity(isComplete ? 0 : 1)

            // Remaining time, shrinking back toward 12 o'clock
            Circle()
                .trim(from: 0, to: progress)
                .stroke(accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: ringDiameter, height: ringDiameter)
                .animation(reduceMotion || ringStep < 1.5 ? nil : .linear(duration: 1), value: progress)

            VStack(spacing: 10) {
                if isComplete {
                    Text("Session complete")
                        .font(.appFont(size: 30, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    // Liquid-glass digits; moving the pointer over them drops droplets of glass. With Reduce Motion on
                    // the page holds still. Read aloud through the dial's label below, so the page itself is hidden.
                    ReactBitsWebView(
                        page: .fluidGlassTime,
                        props: ["text": timeText, "accent": accent.hexRGB]
                    )
                    .frame(width: 250 * ringDiameter / 300, height: 100 * ringDiameter / 300)
                    .accessibilityHidden(true)
                }
                Text(state.focusGoal)
                    .font(.appFont(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: ringDiameter - 80)
            }
        }
        .frame(width: (dialRadius + 12) * 2, height: (dialRadius + 12) * 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isComplete
            ? "Session complete, \(state.focusGoal)"
            : "\(remaining / 60) minutes \(remaining % 60) seconds remaining, \(state.focusGoal)")
    }
}

// MARK: - Focus Countdown (full page while a session runs)
public struct FocusCountdownView: View {
    @ObservedObject var state = TestAppStateManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let accent = SquircleTokens.accentColor(for: "focus")

    private var remaining: Int { state.timerSecondsRemaining }
    private var isComplete: Bool { remaining == 0 }

    public init() {}

    @State private var confirmingEnd = false

    private var elapsedText: String {
        let elapsed = max(state.timerTotalSeconds - remaining, 0)
        return String(format: "%d:%02d", elapsed / 60, elapsed % 60)
    }

    private var endsAtText: String {
        guard state.isTimerActive, !isComplete else { return isComplete ? "Done" : "Paused" }
        return Date().addingTimeInterval(TimeInterval(remaining)).formatted(date: .omitted, time: .shortened)
    }

    public var body: some View {
        VStack(spacing: 36) {
            // What this session is for, centered over the dial and steps so the page reads as "working on X".
            VStack(spacing: 4) {
                Text(isComplete ? "Finished" : state.isTimerActive ? "Working on" : "Paused on")
                    .font(.appFont(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                Text(state.focusGoal.isEmpty ? "Your session" : state.focusGoal)
                    .scriptAccent(size: 40)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .multilineTextAlignment(.center)

            // The dial and the side column sit side by side, centered on each other.
            HStack(alignment: .center, spacing: 56) {
                timerColumn
                VStack(spacing: 18) {
                    sessionStats
                    // The session's milestones sit beside the timer, created for this session's goal.
                    FocusMilestonesCard()
                }
                .frame(width: 380)
            }
        }
        // One group, centered both ways in the window, within the same width and margins as every other page.
        .frame(maxWidth: PageWidth.wide)
        .padding(PageWidth.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    /// Three small numbers about this session: time spent, distractions closed, when it ends.
    private var sessionStats: some View {
        HStack(spacing: 0) {
            stat("Focused", elapsedText)
            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1, height: 34)
            stat("Blocked", "\(state.sessionDistractions)")
            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1, height: 34)
            stat("Ends", endsAtText)
        }
        .padding(.vertical, 16)
        .innerObsidianCard(cornerRadius: 16)
        .accessibilityElement(children: .combine)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.appFont(size: 20, weight: .bold))
                .monospacedDigit()
                .foregroundColor(.white)
            Text(label)
                .font(.appFont(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }

    private var timerColumn: some View {
        VStack(spacing: 28) {
            FocusDial()

            HStack(spacing: 14) {
                Button(action: { state.isCountdownPresented = false }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .bold))
                        Text("Back")
                    }
                    .quietAction()
                }
                .buttonStyle(.plain)

                if isComplete {
                    Button(action: {
                        state.resetTimer()
                        state.isCountdownPresented = false
                    }) {
                        Text("Done")
                            .font(.appFont(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 10)
                            .borderGlowButton(accent: accent, isProminent: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                            state.toggleTimer()
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: state.isTimerActive ? "pause.fill" : "play.fill")
                            Text(state.isTimerActive ? "Pause" : "Resume")
                                .font(.appFont(size: 15, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .borderGlowButton(accent: accent, isProminent: true)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                            state.resetTimer()
                        }
                    }) {
                        Text("Reset")
                            .quietAction()
                    }
                    .buttonStyle(.plain)

                    // Stop now and count it: the session ends early and is saved like a finished one.
                    // With commitment mode on, its countdown is the confirmation.
                    Button(action: { state.isCommitmentModeOn && state.isTimerActive ? state.requestStop(.end) : (confirmingEnd = true) }) {
                        HStack(spacing: 6) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text("End")
                        }
                        .quietAction()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("End session")
                    .confirmationDialog("End this session now?", isPresented: $confirmingEnd) {
                        Button("End Session", role: .destructive) {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                                state.completeSession(endedEarly: true)
                            }
                        }
                        Button("Keep Going", role: .cancel) {}
                    } message: {
                        Text("Your focused time so far is saved, and the Shield and Do Not Disturb turn off.")
                    }
                }
            }

            SessionProtectionStatus()
        }
    }
}

// MARK: - Session protection (Shield + macOS Focus)

/// Under the timer: what the Shield has closed, and whether macOS Focus is on (or a button to set it up).
private struct SessionProtectionStatus: View {
    @ObservedObject private var state = TestAppStateManager.shared
    @ObservedObject private var blocker = AppBlockingManager.shared
    @ObservedObject private var focus = FocusModeManager.shared
    @State private var showingBlockedApps = false
    private let accent = SquircleTokens.accentColor(for: "focus")

    var body: some View {
        VStack(spacing: 8) {
            if state.isTimerActive {
                Label {
                    Text(shieldText)
                } icon: {
                    Image(systemName: state.isShieldActive ? "shield.fill" : "shield.slash")
                }
                .font(.appFont(size: 12))
                .foregroundColor(.white.opacity(state.isShieldActive ? 0.7 : 0.45))

                if focus.setupState == .ready {
                    Label(focus.isFocusActive ? "Do Not Disturb is on" : "Do Not Disturb turns on while the timer runs",
                          systemImage: "moon.fill")
                        .font(.appFont(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                } else {
                    FocusSetupRow(accent: accent, compact: true)
                }
            }
            Button("Choose blocked apps…") { showingBlockedApps = true }
                .buttonStyle(.plain)
                .font(.appFont(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .padding(.top, 4)
                .accessibilityHint("Pick which apps close during focus sessions")
                .sheet(isPresented: $showingBlockedApps) {
                    VStack(alignment: .trailing, spacing: 12) {
                        Button("Done") { showingBlockedApps = false }
                            .keyboardShortcut(.defaultAction)
                        BlockedAppsCard(accent: accent)
                    }
                    .padding(Spacing.l)
                    .frame(width: 560)
                    .background(SquircleTokens.bgBottom(for: "focus"))
                }

        }
        .multilineTextAlignment(.center)
        .task { await focus.refreshSetupState() }
    }

    private var shieldText: String {
        guard state.isShieldActive else { return "Shield is off, so games and social media stay open" }
        if blocker.quitAppNames.isEmpty { return "Shield on: your blocked apps and social media tabs are closed" }
        return "Shield on · closed \(blocker.quitAppNames.joined(separator: ", "))"
    }
}

/// Settings card for the one-click macOS Focus setup.
/// Which key to hold to talk to the Assistant, in any app.
struct AssistantHotkeyCard: View {
    @ObservedObject private var assistant = VoiceAssistant.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Assistant hotkey")
                    .font(.appFont(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text("Hold this key for a moment, in any app, to talk to Locken. From another app it listens for one question, answers and stops. Press it while Locken is thinking or talking to interrupt.")
                    .font(.appFont(size: 11))
                    .foregroundColor(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            JellyRadioPicker(
                items: VoiceAssistant.HoldKey.allCases.map(\.rawValue),
                selection: Binding(
                    get: { assistant.holdKey.rawValue },
                    set: { assistant.holdKey = VoiceAssistant.HoldKey(rawValue: $0) ?? .leftOption }
                ),
                label: "Assistant hotkey"
            )
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .innerObsidianCard(cornerRadius: 16)
    }
}

/// Opens Locken, hidden, when the student logs in, so Analytics keeps measuring after a restart.
struct LaunchAtLoginCard: View {
    @ObservedObject private var login = LaunchAtLogin.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Open at login")
                    .font(.appFont(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text("Locken starts in the menu bar, with its window hidden, when you log in to this Mac, so Analytics keeps measuring app usage after a restart. Closing the window never stops it. Quitting Locken (\u{2318}Q or Quit in the menu bar) does, until you open Locken again. You can also remove it in System Settings \u{203A} General \u{203A} Login Items.")
                    .font(.appFont(size: 11))
                    .foregroundColor(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Toggle("Open Locken when I log in", isOn: Binding(get: { login.isOn }, set: { login.set($0) }))
                .toggleStyle(GlassSwitchToggleStyle(tint: SquircleTokens.accentColor(for: "customize")))
                .font(.appFont(size: 13, weight: .semibold))
                .foregroundColor(.white)
            if login.needsApproval {
                Text("macOS needs you to allow Locken in System Settings \u{203A} General \u{203A} Login Items to finish.")
                    .font(.appFont(size: 11))
                    .foregroundColor(.white.opacity(0.7))
                Button("Open Login Items") { login.openLoginItems() }
                    .buttonStyle(.plain)
                    .quietAction()
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .innerObsidianCard(cornerRadius: 16)
        .onAppear { login.refresh() }
    }
}

/// Quieter other media while Locken talks, and music from browser tabs in the sidebar card.
struct OtherMediaCard: View {
    @ObservedObject private var assistant = VoiceAssistant.shared
    @ObservedObject private var nowPlaying = NowPlayingService.shared

    private func status(_ browser: NowPlayingService.Player) -> String {
        switch nowPlaying.access[browser] {
        case .granted:
            return nowPlaying.javaScriptOff.contains(browser)
                ? "\(browser.name): turn on Allow JavaScript from Apple Events (\(browser == .safari ? "Develop menu" : "View › Developer"))"
                : "\(browser.name): ready"
        case .denied: return "\(browser.name): Automation is off in System Settings › Privacy & Security"
        default: return "\(browser.name): not allowed yet"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Other media")
                    .font(.appFont(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text("Spotify, Music and browser tabs on YouTube, YouTube Music, Spotify and SoundCloud get quieter while Locken talks, then come back. Browser tabs also show in the sidebar as what's playing.")
                    .font(.appFont(size: 11))
                    .foregroundColor(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Toggle("Lower other media while Locken talks", isOn: $assistant.lowersOtherMedia)
                .toggleStyle(GlassSwitchToggleStyle(tint: SquircleTokens.accentColor(for: "customize")))
                .font(.appFont(size: 13, weight: .semibold))
                .foregroundColor(.white)
            if nowPlaying.runningBrowsers.isEmpty {
                Text("Open a browser to set it up.")
                    .font(.appFont(size: 11))
                    .foregroundColor(.white.opacity(0.55))
            } else {
                ForEach(nowPlaying.runningBrowsers, id: \.self) { browser in
                    Text(status(browser))
                        .font(.appFont(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                }
                Button("Allow browsers") { nowPlaying.connectBrowsers() }
                    .buttonStyle(.plain)
                    .quietAction()
                Text("Locken only reads and changes the volume of tabs on those sites, and puts the volume back. A browser needs its Allow JavaScript from Apple Events switch on for this: it lets apps you've allowed run scripts in that browser's tabs, so leave it off if you'd rather not.")
                    .font(.appFont(size: 11))
                    .foregroundColor(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .innerObsidianCard(cornerRadius: 16)
    }
}

struct FocusSetupCard: View {
    @ObservedObject private var focus = FocusModeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("macOS Focus")
                    .font(.appFont(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text("Turns on Do Not Disturb when a focus session starts and off when it ends.")
                    .font(.appFont(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            FocusSetupRow(accent: SquircleTokens.accentColor(for: "customize"), compact: false)
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .innerObsidianCard(cornerRadius: 16)
        .task { await focus.refreshSetupState() }
    }
}

/// The setup state and button, shared by the Settings card and the timer page.
private struct FocusSetupRow: View {
    @ObservedObject private var focus = FocusModeManager.shared
    @ObservedObject private var state = TestAppStateManager.shared
    let accent: Color
    let compact: Bool

    var body: some View {
        VStack(alignment: compact ? .center : .leading, spacing: 8) {
            switch focus.setupState {
            case .checking:
                LogoTraceLoader(size: 16, strokeWidth: 9)
            case .ready:
                Label("Ready. Do Not Disturb follows your sessions.", systemImage: "checkmark.circle.fill")
                    .font(.appFont(size: 12))
                    .foregroundColor(.white.opacity(0.7))
            case .waitingForAdd(let name):
                HStack(spacing: 8) {
                    LogoTraceLoader(size: 16, strokeWidth: 9)
                    Text("In Shortcuts, click Add Shortcut for \u{201C}\(name)\u{201D}.")
                        .font(.appFont(size: 12))
                        .foregroundColor(.white.opacity(0.75))
                }
            case .notSetUp:
                Text(focus.missingShortcuts.count == 1
                     ? "Almost set up: \u{201C}\(focus.missingShortcuts[0])\u{201D} is missing, so Do Not Disturb can't turn on yet. Click Finish Setup, then Add Shortcut."
                     : compact
                     ? "macOS Focus isn't set up, so notifications can still come through."
                     : "One click: Locken creates two shortcuts and opens them in Shortcuts. Click Add Shortcut on each.")
                    .font(.appFont(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task {
                        await focus.setUp()
                        // Already in a session: turn Focus on now rather than at the next start.
                        if focus.setupState == .ready, state.isTimerActive { await focus.activate() }
                    }
                } label: {
                    Text(focus.missingShortcuts.count == 1 ? "Finish Setup" : "Set Up Focus")
                        .font(.appFont(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .borderGlowButton(accent: accent, isProminent: true)
                }
                .buttonStyle(.plain)
            }
            if let error = focus.lastError {
                Text(error.localizedDescription)
                    .font(.appFont(size: 11))
                    .foregroundColor(SquircleTokens.textGold)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Canvas Assignments (pick an assignment, set a time limit, start the timer)
private struct CanvasAssignmentsCard: View {
    @ObservedObject private var canvas = CanvasAPIManager.shared
    @ObservedObject private var state = TestAppStateManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingLinkSheet = false
    @State private var selectedAssignmentID: String?
    @State private var focusMinutes = 25

    private let accent = SquircleTokens.accentColor(for: "focus")

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if !canvas.isLinked {
                Text("Link Canvas or Google Classroom to see your upcoming assignments here. Pick one, set a time limit, and start focusing.")
                    .font(.appFont(size: 13))
                    .foregroundColor(.white.opacity(0.70))
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: { showingLinkSheet = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "graduationcap.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text("Link Canvas or Classroom")
                            .font(.appFont(size: 13, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .borderGlowButton(accent: accent, isProminent: true)
                }
                .buttonStyle(.plain)
            } else {
                if let error = canvas.errorMessage {
                    Text(error)
                        .font(.appFont(size: 12))
                        .foregroundColor(accent)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if canvas.assignments.isEmpty {
                    Text(canvas.isLoading || canvas.lastSynced == nil ? "Loading assignments…" : "No upcoming assignments.")
                        .font(.appFont(size: 13))
                        .foregroundColor(.white.opacity(0.55))
                } else {
                    ForEach(canvas.assignments) { assignment in
                        assignmentRow(assignment)
                    }
                }

                checkOffFooter
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .luxuryObsidianCard(cornerRadius: SquircleTokens.radiusLarge)
        .sheet(isPresented: $showingLinkSheet) {
            LinkCanvasSheet()
        }
        .task {
            if canvas.isLinked && canvas.lastSynced == nil {
                await canvas.refresh()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("CANVAS ASSIGNMENTS")
                .font(.appFont(size: 11, weight: .bold))
                .tracking(1.0)
                .foregroundColor(.white.opacity(0.55))

            Spacer()

            if canvas.isLinked {
                if canvas.isLoading {
                    LogoTraceLoader(size: 16, strokeWidth: 9)
                }
                Button(action: { Task { await canvas.refresh() } }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.70))
                }
                .buttonStyle(.plain)
                .disabled(canvas.isLoading)
                .help("Refresh assignments")
                .accessibilityLabel("Refresh assignments")

                Button(action: {
                    selectedAssignmentID = nil
                    canvas.unlink()
                }) {
                    Text("Unlink")
                        .font(.appFont(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Unlink Canvas")
            }
        }
    }

    /// Undo for the last check-off, and a way back for everything checked off by hand.
    @ViewBuilder private var checkOffFooter: some View {
        if let last = canvas.lastCheckedOff {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(accent)
                Text("Marked \"\(last.title)\" as done.")
                    .font(.appFont(size: 12))
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(1)
                Spacer()
                Button("Undo") { withAnimation { canvas.undoCheckOff() } }
                    .buttonStyle(.plain)
                    .quietAction()
                    .accessibilityLabel("Undo marking \(last.title) as done")
            }
        } else if canvas.checkedOffCount > 0 {
            HStack {
                Text("\(canvas.checkedOffCount) checked off by hand")
                    .font(.appFont(size: 12))
                    .foregroundColor(.white.opacity(0.55))
                Spacer()
                Button("Show them again") { withAnimation { canvas.restoreCheckedOff() } }
                    .buttonStyle(.plain)
                    .quietAction()
            }
        }
    }

    private func assignmentRow(_ assignment: CanvasAssignment) -> some View {
        let isSelected = selectedAssignmentID == assignment.id

        return VStack(alignment: .leading, spacing: 14) {
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    selectedAssignmentID = isSelected ? nil : assignment.id
                }
            }) {
                HStack(spacing: 12) {
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 15))
                        .foregroundColor(isSelected ? accent : .white.opacity(0.40))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(assignment.title)
                            .font(.appFont(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                        Text(detailLine(for: assignment))
                            .font(.appFont(size: 11))
                            .foregroundColor(.white.opacity(0.55))
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(assignment.title), \(detailLine(for: assignment))")
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            if isSelected {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("TIME LIMIT")
                            .font(.appFont(size: 10, weight: .bold))
                            .tracking(1.0)
                            .foregroundColor(.white.opacity(0.50))
                        Spacer()
                        Text("\(focusMinutes) min")
                            .font(.appFont(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .contentTransition(.numericText(value: Double(focusMinutes)))
                    }

                    Slider(
                        value: Binding(
                            get: { Double(focusMinutes) },
                            set: { focusMinutes = Int($0) }
                        ),
                        in: 5...180,
                        step: 5
                    )
                    .tint(accent)
                    .accessibilityLabel("Time limit in minutes")
                    .accessibilityValue("\(focusMinutes) minutes")

                    HStack {
                        // For work handed in on paper or in person, which Canvas never sees as submitted.
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                selectedAssignmentID = nil
                                canvas.checkOff(assignment)
                            }
                        }) {
                            Label("Mark as done", systemImage: "checkmark.circle")
                                .quietAction()
                        }
                        .buttonStyle(.plain)
                        .help("Hides it here. Use this for work you hand in on paper or in person.")
                        .accessibilityLabel("Mark \(assignment.title) as done")

                        Spacer()
                        Button(action: {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                                // Videos the teacher linked in the assignment stay open during its session.
                                _ = AppBlockingManager.shared.allowVideos(from: assignment.videoIDs.map { "https://youtu.be/\($0)" }.joined(separator: " "))
                                state.startFocus(goal: assignment.title, minutes: focusMinutes, playIntro: !reduceMotion)
                                selectedAssignmentID = nil
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Start \(focusMinutes) min focus")
                                    .font(.appFont(size: 13, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 9)
                            .borderGlowButton(accent: accent, isProminent: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Start \(focusMinutes) minute focus on \(assignment.title)")
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .innerObsidianCard(cornerRadius: 12)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(accent.opacity(isSelected ? 0.55 : 0), lineWidth: 1)
        )
    }

    private func detailLine(for assignment: CanvasAssignment) -> String {
        var parts: [String] = []
        if !assignment.courseName.isEmpty {
            parts.append(assignment.courseName)
        }
        if let due = assignment.dueDate {
            let when = due.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
            parts.append(due < Date() ? "Was due \(when)" : "Due \(when)")
        } else {
            parts.append("No due date")
        }
        return parts.joined(separator: " • ")
    }
}

struct LinkCanvasSheet: View {
    @ObservedObject private var canvas = CanvasAPIManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var method: CanvasAPIManager.LinkMethod
    @State private var schoolAddress = ""
    @State private var accessToken = ""
    @State private var feedURL = ""

    init(method: CanvasAPIManager.LinkMethod = .accessToken) {
        _method = State(initialValue: method)
    }

    private var canSubmit: Bool {
        switch method {
        case .accessToken:
            return !schoolAddress.trimmingCharacters(in: .whitespaces).isEmpty
                && !accessToken.trimmingCharacters(in: .whitespaces).isEmpty
        case .calendarFeed:
            return !feedURL.trimmingCharacters(in: .whitespaces).isEmpty
        case .googleClassroom:
            return GoogleClassroom.isConfigured
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Link Canvas or Google Classroom")
                .font(.appFont(size: 18, weight: .bold))

            Picker("Link with", selection: $method) {
                Text("Access token").tag(CanvasAPIManager.LinkMethod.accessToken)
                Text("Calendar feed").tag(CanvasAPIManager.LinkMethod.calendarFeed)
                Text("Google Classroom").tag(CanvasAPIManager.LinkMethod.googleClassroom)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch method {
            case .accessToken:
                labeledField("Canvas address") {
                    TextField("school.instructure.com", text: $schoolAddress)
                }
                labeledField("Access token") {
                    SecureField("Paste your token", text: $accessToken)
                }
                hint("In Canvas, open Account → Settings → New Access Token, then copy the token.")
            case .calendarFeed:
                labeledField("Calendar feed link") {
                    TextField("https://school.instructure.com/feeds/calendars/…", text: $feedURL)
                }
                hint("In Canvas, open Calendar → Calendar Feed and copy the link.")
            case .googleClassroom:
                hint(GoogleClassroom.isConfigured
                     ? "Opens Google's sign-in in a browser window. Locken can only read your courses, assignments and due dates, and which ones you've handed in. It can't post or change anything. Only one of Canvas and Google Classroom can be linked at a time."
                     : "Google Classroom isn't set up in this version of Locken yet.")
            }

            if let error = canvas.errorMessage {
                Text(error)
                    .font(.appFont(size: 12))
                    .foregroundColor(SquircleTokens.accentColor(for: "focus"))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if canvas.isLoading {
                    LogoTraceLoader(size: 16, strokeWidth: 9)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(method == .googleClassroom ? "Sign in with Google" : "Link") {
                    Task {
                        let linked: Bool
                        switch method {
                        case .accessToken:
                            linked = await canvas.link(schoolAddress: schoolAddress, accessToken: accessToken)
                        case .calendarFeed:
                            linked = await canvas.link(calendarFeedURL: feedURL)
                        case .googleClassroom:
                            linked = await canvas.linkGoogleClassroom()
                        }
                        if linked { dismiss() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit || canvas.isLoading)
            }
        }
        .font(.appFont(size: 13))
        .padding(24)
        .frame(width: 460)
        .onAppear { canvas.clearError() }
        .onChange(of: method) { canvas.clearError() }
    }

    private func labeledField<Field: View>(_ label: String, @ViewBuilder field: () -> Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.appFont(size: 12, weight: .semibold))
            field()
                .textFieldStyle(.roundedBorder)
                .font(.appFont(size: 13))
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.appFont(size: 11))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 7. Calendar Timeline View (Deep Emerald & Muted Mint)
public struct TestCalendarTimelineView: View {
    @ObservedObject var state = TestAppStateManager.shared
    @ObservedObject private var canvas = CanvasAPIManager.shared
    @ObservedObject private var formatter = AITaskFormatter.shared
    @ObservedObject private var ageGate = AgeGate.shared

    /// AI is on and allowed, and there's a week to plan from.
    private var showsWeekDigest: Bool {
        formatter.isEnabled && ageGate.meetsAIMinimum != false && (state.appleCalendarStatus == .connected || canvas.isLinked)
    }

    private var weekDigest: some View {
        WeekDigestPanel(accent: SquircleTokens.accentColor(for: "calendar"))
            .padding(Spacing.s)
            .luxuryObsidianCard(cornerRadius: 16)
    }
    /// "Calendar" (Apple Calendar events) or "Canvas" (Canvas assignments) — chosen with JellyRadio.
    @State private var calendarSource = "Calendar"
    /// The Canvas assignment whose details are open.
    @State private var openAssignment: CanvasAssignment?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsCanvasWeek: Bool { canvas.isLinked && calendarSource == "Canvas" }

    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Spacing.l) {
                PageHeader(title: "Calendar & Coursework", subtitle: "Your Apple Calendar events and Canvas coursework in one place.")

                if state.appleCalendarStatus == .connected {
                    upcomingEventsCard
                    if showsWeekDigest { weekDigest }
                    remindersCard
                } else {
                    // Connections live in Settings.
                    CalendarConnectionRow(
                        icon: "calendar",
                        title: "Apple Calendar & Reminders",
                        detail: "Connect in Settings to see your week here",
                        isConnected: false,
                        buttonTitle: "Open Settings",
                        action: { state.selectedTab = "customize" }
                    )
                    .padding(Spacing.l)
                    .luxuryObsidianCard(cornerRadius: 16)
                    if showsWeekDigest { weekDigest }
                }
            }
            // Full page width: the week grid needs the room more than any other page.
            .lockenPage(maxWidth: PageWidth.wide)
        }
        .gradualBlurBottom()
        // Details of the assignment you clicked, on dark glass like the other pop-ups.
        .overlay {
            if let assignment = openAssignment {
                AssignmentDetailOverlay(assignment: assignment) { openAssignment = nil }
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: openAssignment?.id)
        .onAppear { state.refreshAppleCalendarStatus() }
        .task {
            if canvas.isLinked && canvas.lastSynced == nil {
                await canvas.refresh()
            }
        }
    }

    private var upcomingEventsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(showsCanvasWeek ? "CANVAS · THIS WEEK" : "THIS WEEK")
                        .font(.appFont(size: 10, weight: .bold))
                        .tracking(1.0)
                        .foregroundColor(.white.opacity(0.50))
                    if showsCanvasWeek {
                        Text("\(canvasDueThisWeek.count) due in the next 7 days")
                            .font(.appFont(size: 11))
                            .foregroundColor(.white.opacity(0.60))
                    }
                }
                Spacer()
                if canvas.isLinked {
                    JellyRadioPicker(
                        items: ["Calendar", "Canvas"],
                        selection: Binding(
                            get: { calendarSource },
                            set: { newSource in
                                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .timingCurve(0.77, 0, 0.175, 1, duration: 0.45)) {
                                    calendarSource = newSource
                                }
                            }
                        ),
                        label: "Calendar source"
                    )
                }
            }

            // The Apple Calendar week slides out left as the Canvas week slides in from the right (and back).
            ZStack(alignment: .topLeading) {
                appleWeek
                    .opacity(showsCanvasWeek ? 0 : 1)
                    .offset(x: reduceMotion ? 0 : (showsCanvasWeek ? -40 : 0))
                    .allowsHitTesting(!showsCanvasWeek)
                    .accessibilityHidden(showsCanvasWeek)
                canvasWeek
                    .opacity(showsCanvasWeek ? 1 : 0)
                    .offset(x: reduceMotion ? 0 : (showsCanvasWeek ? 0 : 40))
                    .allowsHitTesting(showsCanvasWeek)
                    .accessibilityHidden(!showsCanvasWeek)
            }
            .clipped()
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .luxuryObsidianCard(cornerRadius: 16)
    }

    private var canvasDueThisWeek: [CanvasAssignment] {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start
        return canvas.assignments.filter { ($0.dueDate ?? .distantPast) >= start && ($0.dueDate ?? .distantPast) < end }
    }

    @ViewBuilder
    private var appleWeek: some View {
        if state.upcomingEvents.isEmpty {
            Text("No events in the next 7 days.")
                .font(.appFont(size: 12))
                .foregroundColor(.white.opacity(0.55))
        } else {
            WeekCalendarGraph(events: state.upcomingEvents)
        }
    }

    @ViewBuilder
    private var canvasWeek: some View {
        if canvasDueThisWeek.isEmpty {
            Text(canvas.isLoading ? "Loading Canvas assignments…" : "Nothing due on Canvas in the next 7 days.")
                .font(.appFont(size: 12))
                .foregroundColor(.white.opacity(0.55))
        } else {
            WeekCalendarGraph(events: [], assignments: canvasDueThisWeek, dueTileHeight: 40, onSelectAssignment: { openAssignment = $0 })
        }
    }

    private var remindersCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("REMINDERS")
                .font(.appFont(size: 10, weight: .bold))
                .tracking(1.0)
                .foregroundColor(.white.opacity(0.50))

            if !state.hasReminderAccess {
                Text("Reminders access is off in System Settings.")
                    .font(.appFont(size: 12))
                    .foregroundColor(.white.opacity(0.55))
            } else if state.openReminders.isEmpty {
                Text("No open reminders.")
                    .font(.appFont(size: 12))
                    .foregroundColor(.white.opacity(0.55))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                    ForEach(state.openReminders.prefix(20)) { reminder in
                        ReminderTile(reminder: reminder)
                    }
                }
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .luxuryObsidianCard(cornerRadius: 16)
    }
}

private struct ReminderTile: View {
    let reminder: TestAppStateManager.AppleReminder

    private var isOverdue: Bool { (reminder.due ?? .distantFuture) < Date() }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(reminder.color)
                    .frame(width: 7, height: 7)
                Text(reminder.listTitle)
                    .font(.appFont(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Text(reminder.title)
                .font(.appFont(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
            Text(dueText)
                .font(.appFont(size: 11, weight: isOverdue ? .semibold : .regular))
                .foregroundColor(isOverdue ? SquircleTokens.readableAccent(for: "focus") : .white.opacity(0.55))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(reminder.color.opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(reminder.color.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var dueText: String {
        guard let due = reminder.due else { return "No due date" }
        let when = due.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
        return isOverdue ? "Overdue · \(when)" : "Due \(when)"
    }
}

/// Week at a glance: seven day columns with events drawn as time-sized tiles in their calendar's color.
/// The time grid covers the whole day, shows 12 hours at a time, scrolls, and opens at the week's earliest event.
private struct WeekCalendarGraph: View {
    typealias Event = TestAppStateManager.AppleCalendarEvent

    static let canvasColor = Color(red: 0.89, green: 0.26, blue: 0.22)

    let events: [Event]
    var assignments: [CanvasAssignment] = []
    /// Height of each Canvas tile, ending at its due time.
    var dueTileHeight: CGFloat = 22
    /// Called when a Canvas tile is clicked.
    var onSelectAssignment: ((CanvasAssignment) -> Void)? = nil

    private let hourHeight: CGFloat = 52
    /// The grid covers the school day only: 7 AM to 5 PM. Anything earlier or later is pinned to the edge.
    private let firstHour = 7
    private let lastHour = 17
    private var hourCount: Int { lastHour - firstHour }
    private let labelWidth: CGFloat = 46
    private let calendar = Calendar.current

    private struct PlacedEvent: Identifiable {
        let event: Event
        let lane: Int
        let lanes: Int
        var id: String { event.id }
    }

    private var days: [Date] {
        let start = calendar.startOfDay(for: Date())
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var timedEvents: [Event] { events.filter { !$0.isAllDay } }


    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Color.clear.frame(width: labelWidth)
                ForEach(days, id: \.self) { day in
                    VStack(spacing: 2) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                            .font(.appFont(size: 9, weight: .bold))
                            .tracking(0.8)
                            .foregroundColor(.white.opacity(0.50))
                        Text(day.formatted(.dateTime.day()))
                            .font(.appFont(size: 16, weight: .bold))
                            .foregroundColor(calendar.isDateInToday(day) ? SquircleTokens.readableAccent(for: "calendar") : .white)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            if events.contains(where: \.isAllDay) {
                HStack(alignment: .top, spacing: 0) {
                    Text("all-day")
                        .font(.appFont(size: 9))
                        .foregroundColor(.white.opacity(0.55))
                        .frame(width: labelWidth, alignment: .leading)
                    ForEach(days, id: \.self) { day in
                        VStack(spacing: 3) {
                            ForEach(events.filter { $0.isAllDay && overlaps($0, day) }) { event in
                                Text(event.title)
                                    .font(.appFont(size: 10, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(RoundedRectangle(cornerRadius: 5).fill(event.color.opacity(0.35)))
                                    .help(event.title)
                            }
                        }
                        .padding(.horizontal, 2)
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                }

                // A clear break between all-day events and the timed grid.
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 2)
                    .padding(.vertical, 6)
            }

            // 7 AM to 5 PM, all on screen at once (no scrolling).
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    ForEach(firstHour..<lastHour, id: \.self) { hour in
                        Text(hourLabel(hour))
                            .font(.appFont(size: 9))
                            .foregroundColor(.white.opacity(0.55))
                            .frame(width: labelWidth, height: hourHeight, alignment: .topLeading)
                            .padding(.top, 2)
                    }
                }
                ForEach(days, id: \.self) { day in
                    dayColumn(day)
                }
            }
            .frame(height: hourHeight * CGFloat(hourCount))
        }
    }

    private func dayColumn(_ day: Date) -> some View {
        let placed = placeEvents(on: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let due = assignments.filter { assignment in
            guard let date = assignment.dueDate else { return false }
            return date >= day && date < dayEnd
        }
        let pointsPerSecond = hourHeight / 3600
        let gridStart = calendar.date(byAdding: .hour, value: firstHour, to: day) ?? day
        let gridEnd = calendar.date(byAdding: .hour, value: lastHour, to: day) ?? dayEnd
        let gridHeight = hourHeight * CGFloat(hourCount)
        /// Vertical position of a moment, pinned to the top or bottom edge when it's outside 7 AM – 5 PM.
        let yFor: (Date) -> CGFloat = { date in
            min(max(CGFloat(date.timeIntervalSince(gridStart)) * pointsPerSecond, 0), gridHeight)
        }
        return GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(0..<hourCount, id: \.self) { index in
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: geometry.size.width, height: 1)
                        .offset(y: CGFloat(index) * hourHeight)
                }
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1, height: geometry.size.height)

                // Events are cut to the 7 AM – 5 PM window; ones entirely outside it aren't drawn.
                ForEach(placed.filter { $0.event.end > gridStart && $0.event.start < gridEnd }) { item in
                    let start = max(item.event.start, gridStart)
                    let end = min(item.event.end, gridEnd)
                    let laneWidth = (geometry.size.width - 4) / CGFloat(item.lanes)
                    let height = max(CGFloat(end.timeIntervalSince(start)) * pointsPerSecond - 2, 16)
                    EventTile(event: item.event, height: height)
                        .frame(width: max(laneWidth - 2, 4), height: height)
                        .offset(x: 2 + CGFloat(item.lane) * laneWidth, y: yFor(start) + 1)
                }

                // Canvas due times, drawn over the events as flags ending at the due moment.
                ForEach(due) { assignment in
                    // A due time after 5 PM (like 11:59 PM) sits at the bottom of that day; before 7 AM, at the top.
                    if let date = assignment.dueDate {
                        CanvasDueFlag(assignment: assignment, height: dueTileHeight, onSelect: onSelectAssignment)
                            .frame(width: geometry.size.width - 4, height: dueTileHeight)
                            .offset(x: 2, y: min(max(yFor(date) - dueTileHeight, 0), gridHeight - dueTileHeight))
                    }
                }

                if calendar.isDateInToday(day), Date() >= gridStart, Date() <= gridEnd {
                    Rectangle()
                        .fill(SquircleTokens.readableAccent(for: "focus"))
                        .frame(width: geometry.size.width, height: 1.5)
                        .offset(y: yFor(Date()))
                }
            }
        }
        .frame(height: hourHeight * CGFloat(hourCount))
        .frame(maxWidth: .infinity)
    }

    /// Timed events on `day`, each given a side-by-side lane so overlapping events don't cover each other.
    private func placeEvents(on day: Date) -> [PlacedEvent] {
        let dayEvents = timedEvents.filter { overlaps($0, day) }.sorted { $0.start < $1.start }
        var laneEnds: [Date] = []
        var lanes: [(Event, Int)] = []
        for event in dayEvents {
            if let free = laneEnds.firstIndex(where: { $0 <= event.start }) {
                laneEnds[free] = event.end
                lanes.append((event, free))
            } else {
                laneEnds.append(event.end)
                lanes.append((event, laneEnds.count - 1))
            }
        }
        return lanes.map { PlacedEvent(event: $0.0, lane: $0.1, lanes: max(laneEnds.count, 1)) }
    }

    private func overlaps(_ event: Event, _ day: Date) -> Bool {
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        return event.start < dayEnd && event.end > day
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(.dateTime.hour())
    }
}

private struct CanvasDueFlag: View {
    let assignment: CanvasAssignment
    var height: CGFloat = 22
    /// Opens the assignment's details.
    var onSelect: ((CanvasAssignment) -> Void)? = nil
    @State private var isHovered = false

    var body: some View {
        Button { onSelect?(assignment) } label: { flag }
            .buttonStyle(.plain)
            .disabled(onSelect == nil)
            .onHover { isHovered = $0 }
    }

    private var flag: some View {
        let time = assignment.dueDate?.formatted(date: .omitted, time: .shortened) ?? ""
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 8, weight: .bold))
                Text(assignment.title)
                    .font(.appFont(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
            if height > 30 {
                Text("Due \(time)\(assignment.courseName.isEmpty ? "" : " · \(assignment.courseName)")")
                    .font(.appFont(size: 9))
                    .opacity(0.85)
                    .lineLimit(1)
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(WeekCalendarGraph.canvasColor.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        // Hover is a faint border only, like the rest of the app.
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.white.opacity(isHovered ? 0.55 : 0), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
        .help("Due \(time) · \(assignment.title)\(assignment.courseName.isEmpty ? "" : " · \(assignment.courseName)") · click for details")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(assignment.title), due \(time)")
        .accessibilityHint("Shows the assignment's details")
    }
}

/// A Canvas assignment's details on dark glass: course, title, when it's due and what it's worth, Canvas's own description,
/// and what you can do with it. The description is shown as plain text only.
private struct AssignmentDetailOverlay: View {
    let assignment: CanvasAssignment
    let close: () -> Void
    @ObservedObject private var state = TestAppStateManager.shared
    @ObservedObject private var canvas = CanvasAPIManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private var dueText: String {
        guard let due = assignment.dueDate else { return "No due date" }
        return due.formatted(.dateTime.weekday(.wide).month(.wide).day().hour().minute())
    }

    /// "in 5 hours", or "Past due" once it has passed.
    private var timeLeft: String? {
        guard let due = assignment.dueDate else { return nil }
        if due < Date() { return "Past due" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: due, relativeTo: Date())
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.appFont(size: 11))
                .foregroundColor(.white.opacity(0.55))
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.appFont(size: 13, weight: .semibold))
                .foregroundColor(.white)
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: close)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        if !assignment.courseName.isEmpty {
                            Text(assignment.courseName.uppercased())
                                .font(.appFont(size: 10, weight: .bold))
                                .tracking(1.0)
                                .foregroundColor(.white.opacity(0.55))
                        }
                        Text(assignment.title)
                            .font(.appFont(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 16)
                    Button("Close", action: close)
                        .buttonStyle(.plain)
                        .quietAction()
                        .keyboardShortcut(.cancelAction)
                }

                VStack(alignment: .leading, spacing: 8) {
                    fact("Due", dueText)
                    if let timeLeft { fact("Time left", timeLeft) }
                    if let points = assignment.points {
                        fact("Points", points.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(points)) : String(format: "%.1f", points))
                    }
                    if !assignment.videoIDs.isEmpty {
                        fact("Videos", "\(assignment.videoIDs.count) linked (they stay open in a session)")
                    }
                }

                Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)

                ScrollView(showsIndicators: false) {
                    Text(assignment.details.isEmpty ? "Canvas didn't send a description for this one." : assignment.details)
                        .font(.appFont(size: 13))
                        .foregroundColor(.white.opacity(assignment.details.isEmpty ? 0.55 : 0.85))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxHeight: 220)

                HStack(spacing: 18) {
                    Button {
                        close()
                        state.startFocus(goal: assignment.title, minutes: 25, playIntro: !reduceMotion)
                    } label: {
                        Text("Start a focus session")
                            .font(.appFont(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 10)
                            .borderGlowButton(accent: SquircleTokens.accentColor(for: "calendar"), isProminent: true)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                    .help("Starts a 25-minute session on this assignment")

                    // Only a web link Canvas gave us opens, and only in the browser.
                    if let url = assignment.htmlURL, url.scheme == "https" {
                        Button("Open in Canvas") { NSWorkspace.shared.open(url) }
                            .buttonStyle(.plain)
                            .quietAction()
                    }
                    Button("Mark done") {
                        canvas.checkOff(assignment)
                        close()
                    }
                    .buttonStyle(.plain)
                    .quietAction()
                    .help("Marks it done in Locken only. Nothing is sent to Canvas.")
                }
            }
            .padding(28)
            .frame(width: 520)
            .background(
                ZStack {
                    SquircleTokens.bgBottom(for: "calendar")
                    RadialGradient(colors: [SquircleTokens.accentColor(for: "calendar").opacity(0.14), .clear],
                                   center: .topLeading, startRadius: 0, endRadius: 480)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 40, y: 20)
            .scaleEffect(shown || reduceMotion ? 1 : 0.97)
            .opacity(shown ? 1 : 0)
            .accessibilityAddTraits(.isModal)
        }
        .onAppear { withAnimation(.spring(response: 0.36, dampingFraction: 0.9)) { shown = true } }
    }
}

private struct EventTile: View {
    let event: TestAppStateManager.AppleCalendarEvent
    let height: CGFloat

    var body: some View {
        let time = "\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))"
        VStack(alignment: .leading, spacing: 1) {
            Text(event.title)
                .font(.appFont(size: 10, weight: .semibold))
                .lineLimit(height > 34 ? 2 : 1)
            if height > 40 {
                Text(time)
                    .font(.appFont(size: 9))
                    .opacity(0.75)
                    .lineLimit(1)
            }
        }
        .foregroundColor(.white)
        .padding(.leading, 7)
        .padding(.trailing, 3)
        .padding(.top, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(event.color.opacity(0.30))
        .overlay(alignment: .leading) {
            Rectangle().fill(event.color).frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .help("\(event.title)\n\(time) · \(event.calendarTitle)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(event.title), \(event.start.formatted(.dateTime.weekday(.wide))) \(time)")
    }
}

// MARK: - Calendar Connections (shown in Settings)
private struct CalendarConnectionsCard: View {
    @ObservedObject private var state = TestAppStateManager.shared
    @ObservedObject private var canvas = CanvasAPIManager.shared
    @ObservedObject private var appleNotes = AppleNotesService.shared
    @State private var showingCanvasSheet = false
    @State private var sheetMethod = CanvasAPIManager.LinkMethod.accessToken

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CONNECTIONS")
                .font(.appFont(size: 10, weight: .bold))
                .tracking(1.0)
                .foregroundColor(.white.opacity(0.50))

            appleCalendarRow

            // Same real Canvas link as the Focus tab's assignments card.
            CalendarConnectionRow(
                icon: "graduationcap.fill",
                title: "Canvas LMS",
                detail: canvas.isLinked && canvas.linkMethod != .googleClassroom ? "Connected" : "Assignments and due dates",
                isConnected: canvas.isLinked && canvas.linkMethod != .googleClassroom,
                buttonTitle: canvas.isLinked && canvas.linkMethod != .googleClassroom ? "Disconnect" : "Connect Canvas",
                action: {
                    if canvas.isLinked && canvas.linkMethod != .googleClassroom {
                        canvas.unlink()
                    } else {
                        sheetMethod = .accessToken
                        showingCanvasSheet = true
                    }
                }
            )

            // The same list of assignments as Canvas, from Google's sign-in. One of the two at a time.
            CalendarConnectionRow(
                icon: "books.vertical.fill",
                title: "Google Classroom",
                detail: canvas.linkMethod == .googleClassroom ? "Connected · read only" : "Assignments and due dates",
                isConnected: canvas.linkMethod == .googleClassroom,
                buttonTitle: canvas.linkMethod == .googleClassroom ? "Disconnect" : "Connect Classroom",
                action: {
                    if canvas.linkMethod == .googleClassroom {
                        canvas.unlink()
                    } else {
                        sheetMethod = .googleClassroom
                        showingCanvasSheet = true
                    }
                }
            )

            // Read-only, through Apple Events; shown on the Notes & Reminders page.
            CalendarConnectionRow(
                icon: "note.text",
                title: "Apple Notes",
                detail: appleNotes.isConnected ? "Connected · read on this Mac only" : "Show your notes next to Locken's",
                isConnected: appleNotes.isConnected,
                buttonTitle: appleNotes.isConnected ? "Disconnect" : "Connect Notes",
                action: {
                    if appleNotes.isConnected { appleNotes.disconnect() } else { appleNotes.connect() }
                }
            )
        }
        .padding(Spacing.l)
        .luxuryObsidianCard(cornerRadius: 16)
        .onAppear { state.refreshAppleCalendarStatus() }
        .sheet(isPresented: $showingCanvasSheet) {
            LinkCanvasSheet(method: sheetMethod)
        }
    }

    @ViewBuilder
    private var appleCalendarRow: some View {
        switch state.appleCalendarStatus {
        case .connected:
            CalendarConnectionRow(
                icon: "calendar",
                title: "Apple Calendar & Reminders",
                detail: "Connected",
                isConnected: true,
                buttonTitle: "Disconnect",
                action: { state.disconnectAppleCalendar() }
            )
        case .denied:
            CalendarConnectionRow(
                icon: "calendar",
                title: "Apple Calendar & Reminders",
                detail: "Access is off in System Settings",
                isConnected: false,
                buttonTitle: "Open Privacy Settings",
                action: {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(url)
                    }
                }
            )
        case .disconnected:
            CalendarConnectionRow(
                icon: "calendar",
                title: "Apple Calendar & Reminders",
                detail: "Events and reminders on this Mac",
                isConnected: false,
                buttonTitle: "Connect Calendar & Reminders",
                action: { Task { await state.connectAppleCalendar() } }
            )
        }
    }
}

private struct CalendarConnectionRow: View {
    let icon: String
    let title: String
    let detail: String
    let isConnected: Bool
    let buttonTitle: String
    let action: () -> Void

    private let accent = SquircleTokens.accentColor(for: "calendar")

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isConnected ? accent : .white.opacity(0.55))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.appFont(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text(detail)
                    .font(.appFont(size: 11))
                    .foregroundColor(isConnected ? accent : .white.opacity(0.55))
            }

            Spacer()

            Button(action: action) {
                Text(buttonTitle)
                    .font(.appFont(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .borderGlowButton(accent: accent, isProminent: !isConnected)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(buttonTitle), \(title)")
        }
    }
}

// MARK: - 8. Analytics & Habits View (Smoked Amber & Slate Navy)
public struct TestAnalyticsView: View {
    public var body: some View {
        HabitTrackerView()
    }
}



// MARK: - Start-session pop-up

/// A centered pop-up over the Focus page: dims the page, eases in with a slight scale, and fades its contents in
/// once they've laid out, so nothing visibly resizes or crops while the web-based controls load.
struct SessionSetupModal: View {
    @ObservedObject private var state = TestAppStateManager.shared
    @ObservedObject private var lineup = WorkspaceLineup.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var contentReady = false

    private func close() {
        withAnimation(.easeOut(duration: 0.18)) { state.isSessionSetupPresented = false }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: close)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Start a focus session")
                        .font(.appFont(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Button("Cancel", action: close)
                        .buttonStyle(.plain)
                        .quietAction()
                        .keyboardShortcut(.cancelAction)
                }
                SessionSetupView(onStart: close, showsCard: false)
                    .opacity(contentReady ? 1 : 0)
            }
            .opacity(lineup.isEditorPresented ? 0 : 1)
            .padding(28)
            .frame(width: 640)
            .background(
                ZStack {
                    SquircleTokens.bgBottom(for: "focus")
                    RadialGradient(colors: [SquircleTokens.accentColor(for: "focus").opacity(0.14), .clear],
                                   center: .topLeading, startRadius: 0, endRadius: 520)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 40, y: 20)
            .scaleEffect(shown || reduceMotion ? 1 : 0.97)
            .opacity(shown ? 1 : 0)
            .accessibilityAddTraits(.isModal)

            WorkspaceLineupOverlay()
        }
        .onAppear {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.9)) { shown = true }
            // Give the logo and the goal switch a moment to lay out before showing them.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.easeOut(duration: 0.2)) { contentReady = true }
            }
        }
    }
}


// MARK: - Simple home: calm, one action

/// Under the app's usual greeting: one card to start a session (with the next Canvas assignment as a quiet
/// suggestion), one plain line about today, and today's habits as a row of chips. No extra boxes or charts.
struct SimpleHomeView: View {
    @ObservedObject private var state = TestAppStateManager.shared
    @ObservedObject private var habits = HabitStore.shared
    @ObservedObject private var canvas = CanvasAPIManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let accent = SquircleTokens.accentColor(for: "dashboard")
    private let habitAccent = SquircleTokens.accentColor(for: "habits")

    private func seconds(_ day: Date) -> Int { state.stats.focusSecondsByDay[ScreenUsageTracker.dayKey(day)] ?? 0 }

    /// Days in a row with any focus time, up to today (or yesterday, if today has none yet).
    private var focusStreak: Int {
        var day = Calendar.current.startOfDay(for: Date())
        if seconds(day) == 0 { day = Calendar.current.date(byAdding: .day, value: -1, to: day)! }
        var streak = 0
        while seconds(day) > 0, streak < 3650 {
            streak += 1
            day = Calendar.current.date(byAdding: .day, value: -1, to: day)!
        }
        return streak
    }

    private var nextAssignment: CanvasAssignment? {
        canvas.assignments.first { ($0.dueDate ?? .distantFuture) > Date() }
    }

    /// Locken's plain background colour (behind every page, and the opening screen).
    static let background = Color(red: 0.055, green: 0.045, blue: 0.055)

    var body: some View {
        // Clearly separate sections: the start card, the daily summary, today's habits.
        VStack(alignment: .leading, spacing: 44) {
            sessionCard
            DailySummaryCarousel()
            if !habits.activeHabits.isEmpty { habitRow }
        }
    }

    /// The one thing to do here: start (or return to) a focus session.
    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: Spacing.l) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(state.isTimerActive ? "Session running" : "Ready when you are")
                        .font(.appFont(size: 11, weight: .bold))
                        .tracking(1.0)
                        .foregroundColor(.white.opacity(0.55))
                        .textCase(.uppercase)
                    Text(state.isTimerActive
                         ? (state.focusGoal.isEmpty ? "Stay with it." : state.focusGoal)
                         : "Pick one thing. Locken closes the distractions.")
                        .font(.appFont(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button {
                    if state.isTimerActive {
                        state.selectedTab = "focus"
                    } else {
                        withAnimation(.easeOut(duration: 0.18)) { state.isSessionSetupPresented = true }
                    }
                } label: {
                    Text(state.isTimerActive ? "Open Session" : "Start Focus")
                        .font(.appFont(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .borderGlowButton(accent: accent, isProminent: true)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }

            if !state.isTimerActive, let next = nextAssignment {
                Divider().overlay(Color.white.opacity(0.08))
                HStack(spacing: 10) {
                    Text("Next due")
                        .font(.appFont(size: 11))
                        .foregroundColor(.white.opacity(0.55))
                    Text(next.title)
                        .font(.appFont(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let due = next.dueDate {
                        Text(due.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                            .font(.appFont(size: 11))
                            .foregroundColor(.white.opacity(0.55))
                            .fixedSize()
                    }
                    Spacer(minLength: 8)
                    Button("Start on this") {
                        state.startFocus(goal: next.title, minutes: 25, playIntro: !reduceMotion)
                    }
                    .buttonStyle(.plain)
                    .quietAction()
                    .help("Starts a 25-minute session on \(next.title)")
                }
            }
        }
        .padding(Spacing.l)
        .luxuryObsidianCard()
    }

    /// Today's habits as chips: tap to tick off.
    private var habitRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Today's habits")
                    .font(.appFont(size: 11, weight: .bold))
                    .tracking(1.0)
                    .foregroundColor(.white.opacity(0.55))
                    .textCase(.uppercase)
                Spacer()
                Button("Habit Tracker") { state.selectedTab = "habits" }
                    .buttonStyle(.plain)
                    .quietAction()
            }
            FlowChips(habits: habits.activeHabits.filter { HabitMath.isScheduled($0, on: Date()) }, store: habits, accent: habitAccent)
        }
    }
}

/// Habit chips that wrap onto new lines as needed.
private struct FlowChips: View {
    let habits: [Habit]
    @ObservedObject var store: HabitStore
    let accent: Color

    var body: some View {
        // Two wide boxes per row, so names fit and it doesn't look stacked.
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], alignment: .leading, spacing: 14) {
            ForEach(habits) { habit in
                let done = store.isDone(habit, on: Date())
                Button { store.toggle(habit, on: Date()) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: done ? "checkmark.circle.fill" : habit.symbol)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(done ? accent : .white.opacity(0.7))
                            .frame(width: 22)
                        Text(habit.name)
                            .font(.appFont(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(done ? 0.5 : 0.9))
                            .strikethrough(done)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 40)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .innerObsidianCard(cornerRadius: 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(habit.name)
                .accessibilityValue(done ? "Done today" : "Not done today")
                .help(done ? "Mark as not done today" : "Mark as done today")
            }
        }
    }
}


// MARK: - Daily summary carousel

/// The last two weeks as a row of day cards that scrolls sideways and snaps to each day, newest on the right.
/// Each card's arrows (or a swipe) move to the day before or after. Real numbers from this Mac only.
private struct DailySummaryCarousel: View {
    @ObservedObject private var state = TestAppStateManager.shared
    @ObservedObject private var habits = HabitStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected: Date?

    private let accent = SquircleTokens.accentColor(for: "dashboard")

    /// The last two weeks, then tomorrow (what's coming up).
    private var days: [Date] {
        let today = Calendar.current.startOfDay(for: Date())
        return (-1..<14).reversed().compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: today) }
    }

    private func key(_ day: Date) -> String { ScreenUsageTracker.dayKey(day) }
    private func minutes(_ day: Date) -> Int { (state.stats.focusSecondsByDay[key(day)] ?? 0) / 60 }

    private func title(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        if Calendar.current.isDateInTomorrow(day) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.wide))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Daily summary")
                .font(.appFont(size: 11, weight: .bold))
                .tracking(1.0)
                .foregroundColor(.white.opacity(0.55))
                .textCase(.uppercase)
            // One day at a time, as wide as the card above; the arrows (or ← →) move between days.
            let day = selected ?? today
            card(day)
                .id(day)
                .transition(.opacity)
                .frame(maxWidth: .infinity)
        }
        .onAppear { selected = today }
        .onKeyPress(.leftArrow) { move(-1, from: selected ?? today); return .handled }
        .onKeyPress(.rightArrow) { move(1, from: selected ?? today); return .handled }
    }

    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    private func move(_ step: Int, from day: Date) {
        guard let index = days.firstIndex(of: day), days.indices.contains(index + step) else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { selected = days[index + step] }
    }

    private func card(_ day: Date) -> some View {
        let index = days.firstIndex(of: day) ?? 0
        let focus = minutes(day)
        let sessions = state.stats.sessionsByDay[key(day)] ?? 0
        let blocked = state.stats.distractionsByDay[key(day)] ?? 0
        let due = habits.activeHabits.filter { HabitMath.isScheduled($0, on: day) && $0.createdAt <= Calendar.current.date(byAdding: .day, value: 1, to: day)! }
        let done = due.filter { habits.isDone($0, on: day) }.count
        let best = days.map(minutes).max() ?? 0

        return VStack(spacing: 14) {
            // Header: arrows either side of the day, like a week switcher.
            HStack {
                arrow("chevron.left", enabled: index > 0) { move(-1, from: day) }
                Spacer()
                VStack(spacing: 2) {
                    Text(day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(.appFont(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                    Text(title(day))
                        .font(.appFont(size: 15, weight: .bold))
                        .foregroundColor(.white)
                }
                Spacer()
                arrow("chevron.right", enabled: index < days.count - 1) { move(1, from: day) }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(0.06)))

            if Calendar.current.isDateInTomorrow(day) {
                tomorrowBody(day, habitsDue: due.count)
            } else {
            HStack(spacing: 0) {
                stat("\(focus)", "min focused")
                stat("\(sessions)", sessions == 1 ? "session" : "sessions")
                stat("\(blocked)", "blocked")
                stat(due.isEmpty ? "–" : "\(done)/\(due.count)", "habits")
            }

            Text(focus == 0 ? (Calendar.current.isDateInToday(day) ? "Nothing focused yet today." : "No focus time this day.")
                 : focus == best ? "Your best day in the last two weeks." : "\(best - focus) min under your best day.")
                .font(.appFont(size: 11))
                .foregroundColor(focus > 0 && focus == best ? accent : .white.opacity(0.55))
            }
        }
        .padding(16)
        .luxuryObsidianCard()
        .accessibilityElement(children: .combine)
    }

    /// Tomorrow: what's due on Canvas and how many habits are planned, so you can plan a session.
    @ViewBuilder private func tomorrowBody(_ day: Date, habitsDue: Int) -> some View {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let dueTomorrow = CanvasAPIManager.shared.assignments.filter { ($0.dueDate ?? .distantPast) >= start && ($0.dueDate ?? .distantPast) < end }
        HStack(spacing: 0) {
            stat("\(dueTomorrow.count)", dueTomorrow.count == 1 ? "assignment due" : "assignments due")
            stat("\(habitsDue)", habitsDue == 1 ? "habit planned" : "habits planned")
        }
        if let first = dueTomorrow.first {
            Text(dueTomorrow.count > 1 ? "\(first.title) and \(dueTomorrow.count - 1) more" : first.title)
                .font(.appFont(size: 11))
                .foregroundColor(.white.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.middle)
        } else {
            Text("Nothing due tomorrow. A good day to get ahead.")
                .font(.appFont(size: 11))
                .foregroundColor(.white.opacity(0.55))
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.appFont(size: 20, weight: .bold)).foregroundColor(.white)
            Text(label).font(.appFont(size: 10)).foregroundColor(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
    }

    private func arrow(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(enabled ? 0.75 : 0.2))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(symbol == "chevron.left" ? "Previous day" : "Next day")
    }
}
