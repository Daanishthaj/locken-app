//
//  AssistantHistory.swift
//  LockenTestApp
//
//  The Assistant's saved conversations. Every message the student says, types or hears back is written to a file on
//  this Mac (one file per account) and shown by day in the Assistant's History panel. Text only, never audio.
//

import Foundation

struct StoredMessage: Codable, Equatable, Identifiable {
    var id: UUID
    var isStudent: Bool
    var text: String
    var date: Date
}

struct SavedConversation: Codable, Equatable, Identifiable {
    var id: UUID
    /// When the first message was sent. The conversation stays under this day even if it's continued later.
    var startedAt: Date
    var messages: [StoredMessage]

    /// A short title from the first thing the student said.
    var title: String {
        let first = messages.first(where: \.isStudent)?.text ?? messages.first?.text ?? ""
        let line = first.split(whereSeparator: \.isNewline).first.map(String.init) ?? first
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "New chat" }
        return trimmed.count > 48 ? String(trimmed.prefix(47)).trimmingCharacters(in: .whitespaces) + "…" : trimmed
    }
}

/// One calendar day of conversations, newest first.
struct HistoryDay: Identifiable, Equatable {
    let day: Date
    let label: String
    let conversations: [SavedConversation]
    var id: Date { day }
}

@MainActor
final class AssistantHistoryStore: ObservableObject {
    static let shared = AssistantHistoryStore()

    /// Newest first. Capped at `limit`; the oldest drop off when it's full.
    @Published private(set) var conversations: [SavedConversation] = []
    static let limit = 500
    static let fileName = "assistant-history"

    private init() {
        #if DEBUG
        Self.selfCheck()
        #endif
    }

    // MARK: Account

    /// Loads the signed-in account's conversations.
    func activateAccount() {
        conversations = load()
    }

    /// Forgets the loaded conversations without touching the file (sign-out, or the account is being deleted).
    func deactivate() {
        conversations = []
    }

    // MARK: Changes

    /// Adds a message to a conversation, starting it if this is its first message.
    func record(_ message: StoredMessage, in id: UUID) {
        if let index = conversations.firstIndex(where: { $0.id == id }) {
            conversations[index].messages.append(message)
        } else {
            conversations.insert(SavedConversation(id: id, startedAt: message.date, messages: [message]), at: 0)
            if conversations.count > Self.limit { conversations.removeLast(conversations.count - Self.limit) }
        }
        save()
    }

    func delete(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        save()
    }

    /// Removes every conversation that started on `day`.
    func deleteDay(_ day: Date, calendar: Calendar = .current) {
        conversations.removeAll { calendar.isDate($0.startedAt, inSameDayAs: day) }
        save()
    }

    // MARK: Grouping and search (pure, so they can be checked)

    /// "Today", "Yesterday", or "Monday, October 19" (with the year when it isn't this year).
    nonisolated static func dayLabel(for day: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale ?? .current
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: now)
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "EEEEMMMMd" : "EEEEMMMMdy")
        return formatter.string(from: day)
    }

    /// Conversations that contain `query` in any message (ignoring case and accents), grouped by the local day they started.
    nonisolated static func grouped(_ conversations: [SavedConversation], matching query: String = "",
                                    now: Date = Date(), calendar: Calendar = .current) -> [HistoryDay] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let kept = needle.isEmpty ? conversations : conversations.filter { conversation in
            conversation.messages.contains { $0.text.localizedStandardContains(needle) }
        }
        let byDay = Dictionary(grouping: kept) { calendar.startOfDay(for: $0.startedAt) }
        return byDay.keys.sorted(by: >).map { day in
            HistoryDay(day: day, label: dayLabel(for: day, now: now, calendar: calendar),
                       conversations: byDay[day]!.sorted { $0.startedAt > $1.startedAt })
        }
    }

    // MARK: File

    private var fileURL: URL? {
        guard AccountScope.userID != nil else { return nil }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LockenTestApp", isDirectory: true)
            .appendingPathComponent("\(Self.fileName)\(AccountScope.suffix).json")
    }

    private func load() -> [SavedConversation] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let saved = try? decoder.decode([SavedConversation].self, from: data) { return saved }
        // Unreadable: keep the file beside it instead of overwriting it with an empty list on the next save.
        try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension("unreadable"))
        return []
    }

    /// shortcut: the whole file is rewritten for each message. Fine up to the 500-conversation cap; move to one file per
    /// conversation if the cap is raised.
    private func save() {
        guard let url = fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(conversations).write(to: url, options: .atomic)
            // What the student said is personal: readable by this Mac account only.
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            print("AssistantHistoryStore: couldn't save: \(error)")
        }
    }

    #if DEBUG
    private static func selfCheck() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        func at(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }
        func message(_ text: String, _ iso: String, student: Bool = true) -> StoredMessage {
            StoredMessage(id: UUID(), isStudent: student, text: text, date: at(iso))
        }
        let now = at("2026-10-21T15:00:00Z")
        let monday = SavedConversation(id: UUID(), startedAt: at("2026-10-19T09:30:00Z"), messages: [message("Plan my Monday", "2026-10-19T09:30:00Z")])
        let todayAM = SavedConversation(id: UUID(), startedAt: at("2026-10-21T08:05:00Z"), messages: [
            message("What's due today?", "2026-10-21T08:05:00Z"), message("Your essay, at 10 PM.", "2026-10-21T08:05:05Z", student: false)])
        let todayPM = SavedConversation(id: UUID(), startedAt: at("2026-10-21T14:00:00Z"), messages: [message("Café study spots", "2026-10-21T14:00:00Z")])
        let yesterday = SavedConversation(id: UUID(), startedAt: at("2026-10-20T23:59:00Z"), messages: [message("Good night", "2026-10-20T23:59:00Z")])
        let all = [todayPM, todayAM, yesterday, monday]

        let days = grouped(all, now: now, calendar: calendar)
        assert(days.map(\.label) == ["Today", "Yesterday", "Monday, October 19"])
        assert(days[0].conversations.map(\.id) == [todayPM.id, todayAM.id], "two chats in one day, newest first")
        assert(dayLabel(for: at("2025-12-31T10:00:00Z"), now: now, calendar: calendar) == "Wednesday, December 31, 2025")
        // Search looks through the assistant's replies too, ignores case and accents, and drops empty days.
        assert(grouped(all, matching: "ESSAY", now: now, calendar: calendar).flatMap(\.conversations).map(\.id) == [todayAM.id])
        assert(grouped(all, matching: "cafe", now: now, calendar: calendar).flatMap(\.conversations).map(\.id) == [todayPM.id])
        assert(grouped(all, matching: "zzz", now: now, calendar: calendar).isEmpty)
        assert(todayAM.title == "What's due today?")
        assert(SavedConversation(id: UUID(), startedAt: now, messages: [message(String(repeating: "a", count: 80), "2026-10-21T08:00:00Z")]).title.count == 48)
    }
    #endif
}
