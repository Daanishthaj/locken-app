import SwiftUI

/// The last digests written this run. Kept in memory only (never saved), and cleared when the account changes.
@MainActor
final class AIDigestStore: ObservableObject {
    static let shared = AIDigestStore()

    struct Digest: Equatable {
        let text: String
        let written: Date
    }

    @Published var reminders: Digest?
    @Published var week: Digest?

    private init() {}

    func reset() {
        reminders = nil
        week = nil
    }
}

/// An AI digest on demand: a button that sends only what the disclosure says, then the result as formatted text.
/// Nothing is sent until the button is pressed.
struct AIDigestPanel: View {
    let title: String
    /// Plain words for what gets sent, and to whom.
    let disclosure: String
    let buttonTitle: String
    let digest: AIDigestStore.Digest?
    let accent: Color
    let write: () async throws -> String
    let onWritten: (AIDigestStore.Digest) -> Void

    @ObservedObject private var formatter = AITaskFormatter.shared
    @ObservedObject private var state = TestAppStateManager.shared
    @State private var isWriting = false
    @State private var error: AITaskFormatter.FormatterError?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(title, systemImage: "sparkles")
                        .font(.appFont(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Text(disclosure)
                        .font(.appFont(size: 11))
                        .foregroundColor(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(action: run) {
                    HStack(spacing: 6) {
                        if isWriting { LogoTraceLoader(size: 16, strokeWidth: 9) }
                        Text(digest == nil ? buttonTitle : "Write Again")
                            .font(.appFont(size: 12, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .borderGlowButton(accent: accent, isProminent: digest == nil)
                }
                .buttonStyle(.plain)
                .disabled(isWriting)
            }

            if let error {
                HStack(spacing: 8) {
                    Text(error.localizedDescription)
                        .font(.appFont(size: 11))
                        .foregroundColor(SquircleTokens.textGold)
                        .fixedSize(horizontal: false, vertical: true)
                    if Self.needsSettings(error) {
                        Button("Open Settings") { state.selectedTab = "customize" }
                            .buttonStyle(.plain)
                            .font(.appFont(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .underline()
                    }
                }
            }

            if let digest {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(LegalMarkdown.parse(digest.text).enumerated()), id: \.offset) { _, block in
                        MarkdownBlockView(block: block)
                    }
                    Text("Written by \(formatter.provider?.displayName ?? "AI") \(digest.written.formatted(.relative(presentation: .named))). Check anything important against the original.")
                        .font(.appFont(size: 11))
                        .foregroundColor(.white.opacity(0.55))
                        .padding(.top, 4)
                }
                .textSelection(.enabled)
            }
        }
        .padding(Spacing.m)
        .innerObsidianCard(cornerRadius: 14)
    }

    private func run() {
        isWriting = true
        error = nil
        Task {
            do {
                let text = try await write()
                onWritten(.init(text: text, written: Date()))
            } catch let failure as AITaskFormatter.FormatterError {
                error = failure
            } catch {
                self.error = .network(error.localizedDescription)
            }
            isWriting = false
        }
    }

    private static func needsSettings(_ error: AITaskFormatter.FormatterError) -> Bool {
        switch error {
        case .disabled, .ageUnknown, .missingAPIKey, .unrecognizedKey, .invalidKey: return true
        default: return false
        }
    }
}

/// Notes & Reminders: a digest of the student's open Apple Reminders.
struct RemindersDigestPanel: View {
    @ObservedObject private var state = TestAppStateManager.shared
    @ObservedObject private var store = AIDigestStore.shared
    @ObservedObject private var formatter = AITaskFormatter.shared
    let accent: Color

    private var reminders: [AITaskFormatter.DigestReminder] {
        state.openReminders.map { reminder in
            .init(
                title: reminder.title,
                due: reminder.due,
                hasDueTime: reminder.hasDueTime,
                list: reminder.listTitle,
                priority: reminder.priority == .none ? "" : reminder.priority.rawValue.lowercased()
            )
        }
    }

    var body: some View {
        AIDigestPanel(
            title: "Reminders digest",
            disclosure: "Sends your open reminders' titles, due dates, lists and priority (never their notes) to \(formatter.provider?.displayName ?? "your AI service") to sort out what to do first.",
            buttonTitle: "Write Digest",
            digest: store.reminders,
            accent: accent,
            write: { try await AITaskFormatter.shared.remindersDigest(reminders) },
            onWritten: { store.reminders = $0 }
        )
    }
}

/// Calendar: a plan for the next 7 days from Canvas due dates and Apple Calendar events.
struct WeekDigestPanel: View {
    @ObservedObject private var state = TestAppStateManager.shared
    @ObservedObject private var canvas = CanvasAPIManager.shared
    @ObservedObject private var store = AIDigestStore.shared
    @ObservedObject private var formatter = AITaskFormatter.shared
    let accent: Color

    private var items: [AITaskFormatter.DigestItem] {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start
        let assignments = canvas.assignments.compactMap { assignment -> AITaskFormatter.DigestItem? in
            guard let due = assignment.dueDate, due >= start, due < end else { return nil }
            return .init(kind: .canvas, start: due, title: assignment.title, detail: assignment.courseName)
        }
        let events = state.upcomingEvents
            .filter { $0.end > start && $0.start < end }
            .map { AITaskFormatter.DigestItem(kind: .calendar, start: $0.start, end: $0.end, isAllDay: $0.isAllDay, title: $0.title) }
        return assignments + events
    }

    var body: some View {
        AIDigestPanel(
            title: "Week digest",
            disclosure: "Sends the titles and times of this week's Canvas assignments and calendar events to \(formatter.provider?.displayName ?? "your AI service") to plan your week.",
            buttonTitle: "Plan My Week",
            digest: store.week,
            accent: accent,
            write: { try await AITaskFormatter.shared.weekDigest(items) },
            onWritten: { store.week = $0 }
        )
    }
}
