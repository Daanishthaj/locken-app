import SwiftUI

// MARK: - Start Focus Session (Dashboard)

/// The dashboard's session setup card. A session only starts once the user has said what they're working
/// on: a Canvas assignment picked from their account, or a goal they type (which Intelligent Rephrase can
/// sharpen). Then they pick the workspace app and length, and start.
struct SessionSetupView: View {
    @ObservedObject private var state = TestAppStateManager.shared
    @ObservedObject private var canvas = CanvasAPIManager.shared
    @ObservedObject private var formatter = AITaskFormatter.shared
    @ObservedObject private var ageGate = AgeGate.shared

    enum GoalSource: String, CaseIterable {
        case canvas = "Canvas Assignment"
        case manual = "My Own Goal"
    }

    @State private var goalSource: GoalSource = .manual
    @State private var hasChosenDefaultSource = false
    @State private var selectedAssignment: CanvasAssignment?
    @State private var manualGoal = ""
    @State private var isRephrasing = false
    @State private var rephraseError: AITaskFormatter.FormatterError?
    @State private var rephraseTask: Task<Void, Never>?
    @State private var showingAssignmentPicker = false
    @State private var showingLinkSheet = false
    @State private var selectedDurationMinutes = 25
    @State private var selectedWorkspaceApp = "Google Chrome"
    @FocusState private var isGoalFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Called after a session starts, e.g. to close the sheet this card is shown in.
    var onStart: (() -> Void)? = nil
    /// False inside the start-session sheet, which supplies its own background, so there's no card inside a card.
    var showsCard: Bool = true

    /// `logo`: the electric animation's silhouette — a bundled brand SVG where one exists, otherwise an SF Symbol.
    /// `tileName` is the shorter name shown on the tile.
    /// The student's own lineup of work apps (Locken's six until they change it).
    @ObservedObject private var lineup = WorkspaceLineup.shared

    private var accent: Color { SquircleTokens.accentColor(for: state.selectedTab) }
    private var selectedDuration: String { "\(selectedDurationMinutes) min" }
    private var trimmedManualGoal: String { manualGoal.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// What the session is about, or nil until the user has picked or typed something.
    private var definedGoal: String? {
        switch goalSource {
        case .canvas: return selectedAssignment?.title
        case .manual: return trimmedManualGoal.isEmpty ? nil : trimmedManualGoal
        }
    }

    /// Pause is always available; starting needs a goal (and no rephrase still rewriting it).
    private var canPressStart: Bool {
        state.isTimerActive || (definedGoal != nil && !isRephrasing)
    }

    var body: some View {
        // Each question sits in its own panel, so it's clear where one ends and the next begins.
        VStack(alignment: .leading, spacing: showsCard ? Spacing.m : 12) {
            if showsCard {
                // Inside the Dashboard card: dividers, so there's no card inside a card.
                goalSection
                divider
                workspaceSection
                divider
                durationSection
            } else {
                panel { goalSection }
                panel { workspaceSection }
                panel { durationSection }
            }
            footer
                .padding(.top, showsCard ? 0 : 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(showsCard ? Spacing.l : 0)
        .modifier(OptionalCard(enabled: showsCard))
        .sheet(isPresented: $showingLinkSheet) {
            LinkCanvasSheet()
        }
        .onAppear {
            // Students with Canvas linked start on their assignments; everyone else types a goal.
            guard !hasChosenDefaultSource else { return }
            hasChosenDefaultSource = true
            goalSource = canvas.isLinked ? .canvas : .manual
        }
        .task {
            if canvas.isLinked && canvas.lastSynced == nil {
                await canvas.refresh()
            }
        }
        .onDisappear { rephraseTask?.cancel() }
    }

    // MARK: What are you working on?

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                sectionLabel("What are you working on?")
                Spacer()
                JellyRadioPicker(
                    items: GoalSource.allCases.map(\.rawValue),
                    selection: Binding(
                        get: { goalSource.rawValue },
                        set: { goalSource = GoalSource(rawValue: $0) ?? .manual }
                    ),
                    label: "Goal source"
                )
            }

            Group {
                switch goalSource {
                case .canvas: canvasAssignmentField
                case .manual: manualGoalField
                }
            }
            .transition(.opacity)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: goalSource)
        }
        // Switching to "My Own Goal" puts the cursor straight in the goal field.
        .onChange(of: goalSource) { _, source in
            if source == .manual { isGoalFieldFocused = true }
        }
    }

    @ViewBuilder
    private var canvasAssignmentField: some View {
        if !canvas.isLinked {
            HStack(spacing: 12) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Link Canvas to pick an assignment")
                        .font(.appFont(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Uses your Canvas access token or calendar feed, stored in your Keychain.")
                        .font(.appFont(size: 11))
                        .foregroundColor(.white.opacity(0.55))
                }
                Spacer()
                Button { showingLinkSheet = true } label: {
                    Text("Link Canvas")
                        .font(.appFont(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .borderGlowButton(accent: accent, isProminent: true)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(fieldBackground)
        } else {
            Button { showingAssignmentPicker = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(accent)
                    if let assignment = selectedAssignment {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(assignment.title)
                                .font(.appFont(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(Self.subtitle(for: assignment))
                                .font(.appFont(size: 11))
                                .foregroundColor(.white.opacity(0.55))
                                .lineLimit(1)
                        }
                    } else {
                        Text(canvas.isLoading && canvas.assignments.isEmpty ? "Loading your assignments…" : "Choose a Canvas assignment")
                            .font(.appFont(size: 13))
                            .foregroundColor(.white.opacity(0.55))
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.45))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(fieldBackground)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Canvas assignment")
            .accessibilityValue(selectedAssignment?.title ?? "None chosen")
            .popover(isPresented: $showingAssignmentPicker, arrowEdge: .bottom) {
                AssignmentPickerPopover(
                    assignments: canvas.assignments,
                    isLoading: canvas.isLoading,
                    errorMessage: canvas.errorMessage,
                    selection: $selectedAssignment,
                    onRefresh: { Task { await canvas.refresh() } },
                    onChoose: { showingAssignmentPicker = false }
                )
            }
        }
    }

    private var manualGoalField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                TextField("e.g. Write the introduction for my history paper", text: $manualGoal, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.plain)
                    .font(.appFont(size: 14))
                    .foregroundColor(.white)
                    .focused($isGoalFieldFocused)
                    .disabled(isRephrasing)
                    .onChange(of: manualGoal) { rephraseError = nil }
                    .accessibilityLabel("Session goal")

                // Hidden for under-18s (AI providers' terms); an unknown age is asked for in Settings.
                if formatter.isEnabled && ageGate.meetsAIMinimum != false {
                    rephraseButton
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(fieldBackground)

            if let rephraseError {
                HStack(spacing: 8) {
                    Text(rephraseError.localizedDescription)
                        .font(.appFont(size: 11))
                        .foregroundColor(SquircleTokens.textGold)
                        .fixedSize(horizontal: false, vertical: true)
                    if Self.needsSettings(rephraseError) {
                        Button("Open Settings") { state.selectedTab = "customize" }
                            .buttonStyle(.plain)
                            .font(.appFont(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .underline()
                    }
                }
            }
        }
    }

    /// Sparkle button: sends the typed goal to the AI and replaces it with a specific, editable rewrite.
    private var rephraseButton: some View {
        Button(action: rephrase) {
            ZStack {
                if isRephrasing {
                    LogoTraceLoader(size: 16, strokeWidth: 9)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(accent)
                }
            }
            .frame(width: 30, height: 30)
            .background(Circle().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .disabled(trimmedManualGoal.isEmpty || isRephrasing)
        .opacity(trimmedManualGoal.isEmpty ? 0.4 : 1)
        .help("Intelligent Rephrase: turn a vague goal into a specific one")
        .accessibilityLabel("Intelligent Rephrase")
        .accessibilityValue(isRephrasing ? "Rephrasing" : "")
    }

    private func rephrase() {
        let input = trimmedManualGoal
        guard !input.isEmpty, !isRephrasing else { return }
        rephraseError = nil
        isRephrasing = true
        let context = AITaskFormatter.Context(
            sessionMinutes: selectedDurationMinutes,
            workspaceApp: selectedWorkspaceApp,
            upcomingAssignments: canvas.assignments
        )
        rephraseTask = Task {
            do {
                manualGoal = try await formatter.rephrase(input, context: context)
                // Hand the field back so the rewrite can be tweaked before starting.
                isGoalFieldFocused = true
            } catch is CancellationError {
                // The view went away mid-request.
            } catch let error as AITaskFormatter.FormatterError {
                rephraseError = error
            } catch {
                rephraseError = .network(error.localizedDescription)
            }
            isRephrasing = false
        }
    }

    // MARK: Workspace app and duration

    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Where you'll work")

            // Tiles wrap onto a second row instead of scrolling off the edge of the sheet.
            HStack(alignment: .top, spacing: 12) {
                    // The chosen app's logo leads the row. Locken's own six are traced by ElectricLogo; an app the
                    // student added shows its real Finder icon, since a full-colour icon traces as a plain square.
                    Group {
                        if let entry = lineup.apps.first(where: { $0.name == selectedWorkspaceApp }),
                           let path = entry.appPath, entry.brand == nil {
                            AppIconImage(url: URL(fileURLWithPath: path))
                                .frame(width: 38, height: 38)
                                .shadow(color: accent.opacity(0.55), radius: 8)
                                .frame(width: 44, height: 44)
                                .id(path)
                                .transition(.opacity)
                        } else {
                            ReactBitsWebView(
                                page: .electricLogo,
                                props: (lineup.apps
                                    .first { $0.name == selectedWorkspaceApp }
                                    .flatMap { $0.logo.dataURL }
                                    .map { ["src": $0] } ?? [:])
                                    // Traced in the current tab's colour, so it matches the rest of the sheet.
                                    .merging(["color": accent.lightened(0.55).hexRGB, "glowColor": accent.hexRGB]) { $1 }
                            )
                            .frame(width: 44, height: 44)
                        }
                    }
                    .animation(.easeOut(duration: 0.15), value: selectedWorkspaceApp)
                    .accessibilityHidden(true)

                    // Name-only tiles (the electric logo on the left already shows the chosen app's logo), so this
                    // doesn't look like the Canvas / My Own Goal switch above (which stays a JellyRadio).
                    // Each tile is as wide as its name (never cut off); a full row wraps onto a second line.
                    WrapLayout(spacing: 8, rowSpacing: 8) {
                        ForEach(lineup.apps, id: \.name) { option in
                            WorkspaceAppTile(
                                name: option.name,
                                tileName: option.tileName,
                                isSelected: selectedWorkspaceApp == option.name,
                                accent: accent
                            ) {
                                selectedWorkspaceApp = option.name
                            }
                        }
                        EditLineupTile { lineup.presentEditor() }
                    }
                    .padding(.vertical, 6) // room for the selected tile's glow
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Where you'll work")
            }
            .padding(.vertical, 4)
        }
        // If the chosen app leaves the lineup, fall back to the first one.
        .onChange(of: lineup.apps) { _, apps in
            if !apps.contains(where: { $0.name == selectedWorkspaceApp }), let first = apps.first {
                selectedWorkspaceApp = first.name
            }
        }
        .onAppear {
            if !lineup.apps.contains(where: { $0.name == selectedWorkspaceApp }), let first = lineup.apps.first {
                selectedWorkspaceApp = first.name
            }
        }
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                sectionLabel("How long")
                Spacer()
                Text("\(selectedDurationMinutes)")
                    .font(.appFont(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .contentTransition(.numericText(value: Double(selectedDurationMinutes)))
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: selectedDurationMinutes)
                Text("min")
                    .font(.appFont(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .accessibilityHidden(true)
            }

            Slider(
                value: Binding(
                    get: { Double(selectedDurationMinutes) },
                    set: { selectedDurationMinutes = Int($0) }
                ),
                in: 5...120,
                step: 5
            )
            .tint(accent)
            .accessibilityLabel("Session duration in minutes")
            .accessibilityValue("\(selectedDurationMinutes) minutes")

            AdaptiveTimeToggle()
        }
    }

    // MARK: Start

    private var footer: some View {
        HStack(spacing: 10) {
            if !state.isTimerActive && definedGoal == nil {
                Text(goalSource == .canvas ? "Choose an assignment to start" : "Type what you're working on to start")
                    .font(.appFont(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            Button(action: start) {
                HStack(spacing: 8) {
                    Image(systemName: state.isTimerActive ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text(state.isTimerActive ? "Pause" : "Start \(selectedDuration) in \(selectedWorkspaceApp)")
                        .font(.appFont(size: 13, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .borderGlowButton(accent: accent, isProminent: true)
            }
            .buttonStyle(.plain)
            .disabled(!canPressStart)
            .opacity(canPressStart ? 1 : 0.45)
            .accessibilityLabel(state.isTimerActive ? "Pause session" : "Start \(selectedDuration) session in \(selectedWorkspaceApp)")
            .accessibilityHint(canPressStart ? "" : "Choose an assignment or type a goal first")
        }
    }

    private func start() {
        if state.isTimerActive {
            state.toggleTimer()
        } else if let goal = definedGoal {
            if goalSource == .canvas, let assignment = selectedAssignment, !assignment.videoIDs.isEmpty {
                _ = AppBlockingManager.shared.allowVideos(from: assignment.videoIDs.map { "https://youtu.be/\($0)" }.joined(separator: " "))
            }
            state.startSession(goal: goal, minutes: selectedDurationMinutes, workspaceApp: selectedWorkspaceApp, playIntro: !reduceMotion)
            onStart?()
        }
    }

    // MARK: Helpers

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.035))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.13), lineWidth: 1))
            )
    }

    private var divider: some View {
        SectionDivider()
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.appFont(size: 13, weight: .semibold))
            .foregroundColor(.white.opacity(0.75))
    }

    static func subtitle(for assignment: CanvasAssignment) -> String {
        var parts: [String] = []
        if !assignment.courseName.isEmpty { parts.append(assignment.courseName) }
        if let due = assignment.dueDate { parts.append("Due " + due.formatted(date: .abbreviated, time: .shortened)) }
        return parts.joined(separator: " · ")
    }

    private static func needsSettings(_ error: AITaskFormatter.FormatterError) -> Bool {
        switch error {
        case .disabled, .ageUnknown, .missingAPIKey, .unrecognizedKey, .invalidKey: return true
        default: return false
        }
    }
}

// MARK: - Searchable Canvas assignment dropdown

private struct AssignmentPickerPopover: View {
    let assignments: [CanvasAssignment]
    let isLoading: Bool
    let errorMessage: String?
    @Binding var selection: CanvasAssignment?
    let onRefresh: () -> Void
    let onChoose: () -> Void

    @State private var query = ""
    @State private var hoveredID: String?
    @FocusState private var isSearchFocused: Bool

    private var filtered: [CanvasAssignment] {
        let terms = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !terms.isEmpty else { return assignments }
        return assignments.filter {
            $0.title.localizedCaseInsensitiveContains(terms) || $0.courseName.localizedCaseInsensitiveContains(terms)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search assignments or courses", text: $query)
                    .textFieldStyle(.plain)
                    .font(.appFont(size: 13))
                    .focused($isSearchFocused)
                    // Return picks the top match.
                    .onSubmit { if let first = filtered.first { choose(first) } }
                if isLoading {
                    LogoTraceLoader(size: 16, strokeWidth: 9)
                } else {
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Refresh from Canvas")
                    .accessibilityLabel("Refresh assignments")
                }
            }
            .padding(12)

            SectionDivider()

            if let errorMessage {
                Text(errorMessage)
                    .font(.appFont(size: 11))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if filtered.isEmpty {
                Text(emptyMessage)
                    .font(.appFont(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filtered) { assignment in
                            row(assignment)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 300)
            }
        }
        .frame(width: 420)
        .onAppear { isSearchFocused = true }
    }

    private var emptyMessage: String {
        if isLoading { return "Loading your assignments…" }
        if assignments.isEmpty { return "No upcoming assignments. Switch to My Own Goal to type one instead." }
        return "No assignments match \u{201C}\(query)\u{201D}."
    }

    private func row(_ assignment: CanvasAssignment) -> some View {
        let isSelected = selection?.id == assignment.id
        return Button { choose(assignment) } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(assignment.title)
                        .font(.appFont(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(SessionSetupView.subtitle(for: assignment))
                        .font(.appFont(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(isSelected ? 0.12 : hoveredID == assignment.id ? 0.07 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredID = $0 ? assignment.id : (hoveredID == assignment.id ? nil : hoveredID) }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func choose(_ assignment: CanvasAssignment) {
        selection = assignment
        onChoose()
    }
}

// MARK: - Workspace app tile

/// One workspace app, by name, on a tile. The chosen tile gets an accent ring and tint; hovering only brightens
/// the border (no movement). The app's logo is shown by the electric logo at the start of the row.
private struct WorkspaceAppTile: View {
    let name: String
    let tileName: String
    let isSelected: Bool
    let accent: Color
    let action: () -> Void

    @State private var isHovered = false

    private let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    var body: some View {
        Button(action: action) {
            Text(tileName)
                .font(.appFont(size: 15, weight: .bold))
                .foregroundColor(.white.opacity(isSelected ? 1 : 0.75))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 14)
                .frame(minWidth: 64)
                .frame(height: 44)
                .background(shape.fill(isSelected ? accent.opacity(0.16) : Color.white.opacity(0.04)))
                .overlay(shape.strokeBorder(borderColor, lineWidth: isSelected ? 2 : 1))
                .shadow(color: isSelected ? accent.opacity(0.35) : .clear, radius: 10)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isSelected)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var borderColor: Color {
        isSelected ? accent : Color.white.opacity(isHovered ? 0.22 : 0.08)
    }
}

// MARK: - The student's app lineup

/// The apps shown under "Where you'll work". Starts as Locken's six; the student can add any installed app,
/// take any off, and reorder by removing and re-adding. Saved per account on this Mac.
@MainActor
final class WorkspaceLineup: ObservableObject {
    static let shared = WorkspaceLineup()
    static let keyBase = "workspace.lineup"
    /// Enough to choose from while the tiles still fit on one row.
    static let maxApps = 7

    struct Entry: Codable, Hashable {
        let name: String
        let tileName: String
        let bundleID: String?
        var brand: String? = nil
        var symbol: String? = nil
        var appPath: String? = nil

        var logo: WorkspaceAppLogo {
            if let brand { return .brand(brand) }
            if let appPath { return .appIcon(appPath) }
            return .symbol(symbol ?? "app.fill")
        }
    }

    static let defaults: [Entry] = [
        Entry(name: "Google Chrome", tileName: "Chrome", bundleID: "com.google.Chrome", brand: "googlechrome"),
        Entry(name: "Safari", tileName: "Safari", bundleID: "com.apple.Safari", brand: "safari"),
        Entry(name: "Comet", tileName: "Comet", bundleID: "ai.perplexity.comet", brand: "perplexity"),
        Entry(name: "Xcode", tileName: "Xcode", bundleID: "com.apple.dt.Xcode", symbol: "hammer.fill"),
        Entry(name: "Cursor", tileName: "Cursor", bundleID: "com.todesktop.230313mzl4w4u92", brand: "cursor"),
        Entry(name: "VS Code", tileName: "VS Code", bundleID: "com.microsoft.VSCode", symbol: "chevron.left.forwardslash.chevron.right"),
    ]

    @Published private(set) var apps: [Entry] = WorkspaceLineup.defaults
    /// The "Your apps" editor, shown centered over the page (see WorkspaceLineupOverlay).
    @Published private(set) var isEditorPresented = false

    func presentEditor() { withAnimation(.easeOut(duration: 0.18)) { isEditorPresented = true } }
    func dismissEditor() { withAnimation(.easeOut(duration: 0.18)) { isEditorPresented = false } }

    private init() {}

    private var key: String { Self.keyBase + AccountScope.suffix }
    var isFull: Bool { apps.count >= Self.maxApps }
    var isDefault: Bool { apps == Self.defaults }

    func activateAccount() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([Entry].self, from: data), !saved.isEmpty {
            apps = saved
        } else {
            apps = Self.defaults
        }
    }

    func contains(_ app: InstalledApp) -> Bool { apps.contains { $0.bundleID == app.bundleID } }

    func add(_ app: InstalledApp) {
        guard !contains(app), !isFull else { return }
        // Locken's own entries keep their traced brand logo; any other app uses its Finder icon.
        if let known = Self.defaults.first(where: { $0.bundleID == app.bundleID }) {
            apps.append(known)
        } else {
            apps.append(Entry(name: app.name, tileName: app.name, bundleID: app.bundleID, appPath: app.url.path))
        }
        save()
    }

    /// Keeps at least one app, so a session always has somewhere to work.
    func remove(_ entry: Entry) {
        guard apps.count > 1 else { return }
        apps.removeAll { $0 == entry }
        save()
    }

    func reset() {
        apps = Self.defaults
        UserDefaults.standard.removeObject(forKey: key)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(apps) { UserDefaults.standard.set(data, forKey: key) }
    }
}

/// The last tile in the row: opens the lineup editor.
private struct EditLineupTile: View {
    let action: () -> Void
    @State private var isHovered = false
    private let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.75))
                .frame(width: 44, height: 44)
                .background(shape.fill(Color.white.opacity(0.03)))
                .overlay(shape.strokeBorder(Color.white.opacity(isHovered ? 0.26 : 0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .help("Choose your apps")
        .accessibilityLabel("Choose your apps")
    }
}

/// "Your apps", centered over the page with the same look and fade-in as the start-session pop-up.
/// Put it in an `.overlay` on any page that shows session setup.
struct WorkspaceLineupOverlay: View {
    @ObservedObject private var lineup = WorkspaceLineup.shared

    var body: some View {
        if lineup.isEditorPresented {
            ZStack {
                Color.black.opacity(0.65)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { lineup.dismissEditor() }
                    .accessibilityHidden(true)
                WorkspaceLineupEditor()
            }
            .transition(.opacity)
        }
    }
}

/// Pick the apps for "Where you'll work": the current lineup on top (remove with ×), every installed app below.
private struct WorkspaceLineupEditor: View {
    @ObservedObject private var lineup = WorkspaceLineup.shared
    @ObservedObject private var blocker = AppBlockingManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var apps: [InstalledApp] = []
    @State private var search = ""
    @State private var shown = false
    private let accent = SquircleTokens.accentColor(for: "focus")

    private var results: [InstalledApp] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your apps")
                    .font(.appFont(size: 20, weight: .bold))
                    .foregroundColor(.white)
                Text("Up to \(WorkspaceLineup.maxApps) apps show under \u{201C}Where you\u{2019}ll work\u{201D}. Tap an app to add or remove it.")
                    .font(.appFont(size: 12))
                    .foregroundColor(.white.opacity(0.6))
            }

            // The lineup, in order.
            HStack(spacing: 8) {
                ForEach(lineup.apps, id: \.name) { entry in
                    HStack(spacing: 6) {
                        Text(entry.tileName)
                            .font(.appFont(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(1)
                        if lineup.apps.count > 1 {
                            Button { lineup.remove(entry) } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white.opacity(0.6))
                                    .frame(width: 14, height: 14)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(entry.name)")
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(accent.opacity(0.14)))
                    .overlay(Capsule().strokeBorder(accent.opacity(0.6), lineWidth: 1))
                }
                Spacer(minLength: 0)
            }

            SectionDivider()

            TextField("Search apps", text: $search)
                .textFieldStyle(.plain)
                .font(.appFont(size: 13))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
                )
                .accessibilityLabel("Search apps")

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                    ForEach(results) { app in
                        LineupAppTile(
                            app: app,
                            isIn: lineup.contains(app),
                            isBlocked: blocker.isBlocked(bundleID: app.bundleID, builtIn: app.isBuiltInDistraction),
                            isFull: lineup.isFull,
                            accent: accent
                        ) {
                            if let entry = lineup.apps.first(where: { $0.bundleID == app.bundleID }) {
                                lineup.remove(entry)
                            } else {
                                lineup.add(app)
                            }
                        }
                    }
                }
                .padding(2)
            }
            .frame(height: 260)

            Text("Apps the Shield blocks can\u{2019}t be work apps. Unblock one in Settings first if you need it.")
                .font(.appFont(size: 11))
                .foregroundColor(.white.opacity(0.55))

            HStack {
                if !lineup.isDefault {
                    Button("Reset to Locken\u{2019}s apps") { lineup.reset() }
                        .buttonStyle(.plain)
                        .quietAction()
                }
                Spacer()
                Button { lineup.dismissEditor() } label: {
                    Text("Done")
                        .font(.appFont(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 8)
                        .borderGlowButton(accent: accent, isProminent: true)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 620)
        .background(
            ZStack {
                SquircleTokens.bgBottom(for: "focus")
                RadialGradient(colors: [accent.opacity(0.14), .clear], center: .topLeading, startRadius: 0, endRadius: 520)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 40, y: 20)
        .scaleEffect(shown || reduceMotion ? 1 : 0.97)
        .opacity(shown ? 1 : 0)
        .accessibilityAddTraits(.isModal)
        .onExitCommand { lineup.dismissEditor() }
        .onAppear { withAnimation(.spring(response: 0.36, dampingFraction: 0.9)) { shown = true } }
        .task {
            apps = await Task.detached { InstalledAppsScanner.scan(onlyBlockable: false) }.value
        }
    }
}

/// An installed app in the lineup editor: its Finder icon and name; ticked when it's in the lineup.
private struct LineupAppTile: View {
    let app: InstalledApp
    let isIn: Bool
    let isBlocked: Bool
    let isFull: Bool
    let accent: Color
    let action: () -> Void

    @State private var isHovered = false
    private let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
    private var isDisabled: Bool { !isIn && (isBlocked || isFull) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                AppIconImage(url: app.url)
                    .frame(width: 34, height: 34)
                Text(isBlocked && !isIn ? "Blocked" : app.name)
                    .font(.appFont(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .frame(width: 96, height: 78)
            .background(shape.fill(isIn ? accent.opacity(0.14) : Color.white.opacity(0.04)))
            .overlay(shape.strokeBorder(isIn ? accent : Color.white.opacity(isHovered && !isDisabled ? 0.22 : 0.08), lineWidth: isIn ? 1.5 : 1))
            .opacity(isDisabled ? 0.45 : 1)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
        .help(isBlocked && !isIn ? "\(app.name) is blocked during focus" : isIn ? "Remove \(app.name)" : "Add \(app.name)")
        .accessibilityLabel(app.name)
        .accessibilityValue(isIn ? "In your apps" : isBlocked ? "Blocked during focus" : "Not in your apps")
    }
}

// MARK: - Adaptive time

/// The adaptive-time switch, shared by session setup and the Focus tab. With it on, each check-in's answer
/// (how far into the goal) re-estimates the time left.
struct AdaptiveTimeToggle: View {
    @ObservedObject private var state = TestAppStateManager.shared

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Adaptive time")
                    .font(.appFont(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text("Start with this length. At each check-in, the time left adjusts to how far into your goal you are.")
                    .font(.appFont(size: 11))
                    .foregroundColor(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: $state.isAdaptiveTimeOn)
                .toggleStyle(GlassSwitchToggleStyle())
                .accessibilityLabel("Adaptive time")
        }
    }
}


/// The setup card's glass background, or nothing when the sheet around it already provides one.
private struct OptionalCard: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content.innerObsidianCard(cornerRadius: SquircleTokens.radiusLarge)
        } else {
            content
        }
    }
}

/// Lays its children out left to right and wraps them onto a new row when a row is full, like words in a paragraph.
/// Every child keeps its own natural size, so no tile is ever squeezed or cut off.
struct WrapLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(fitting width: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            var row = rows.removeLast()
            if !row.items.isEmpty, row.width + spacing + size.width > width {
                rows.append(row)
                row = Row()
            }
            row.width += (row.items.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.items.append((index, size))
            rows.append(row)
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(fitting: proposal.width ?? .infinity, subviews)
        let height = rows.reduce(0) { $0 + $1.height } + rowSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(fitting: bounds.width, subviews) {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }
}
