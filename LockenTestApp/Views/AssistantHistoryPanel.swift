//
//  AssistantHistoryPanel.swift
//  LockenTestApp
//
//  The Assistant's History panel: saved conversations by day, newest first, with search, "New chat", and delete
//  (one conversation or a whole day) behind a confirmation. It slides in over the page, so the conversation on
//  screen stays where it is until the student picks another one.
//

import SwiftUI

struct AssistantHistoryPanel: View {
    @Binding var isOpen: Bool
    @ObservedObject private var store = AssistantHistoryStore.shared
    @ObservedObject private var assistant = VoiceAssistant.shared
    @State private var query = ""
    @State private var pending: PendingDelete?

    private enum PendingDelete: Identifiable {
        case conversation(SavedConversation)
        case day(HistoryDay)

        var id: String {
            switch self {
            case .conversation(let conversation): return "c-\(conversation.id)"
            case .day(let day): return "d-\(day.day.timeIntervalSince1970)"
            }
        }
    }

    private var accent: Color { SquircleTokens.accentColor(for: "assistant") }
    private var days: [HistoryDay] { AssistantHistoryStore.grouped(store.conversations, matching: query) }
    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            header
            newChatButton
            searchField
            if days.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .padding(Spacing.m)
        .frame(width: 340)
        .frame(maxHeight: .infinity)
        .luxuryObsidianCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Conversation history")
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible, presenting: pending) { item in
            Button("Delete", role: .destructive) { delete(item) }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text(confirmMessage(item))
        }
    }

    // MARK: Parts

    private var header: some View {
        HStack {
            Text("History")
                .font(.appFont(size: 17, weight: .bold))
                .foregroundColor(.white)
            Spacer()
            Button { isOpen = false } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close history")
        }
    }

    private var newChatButton: some View {
        Button { assistant.reset() } label: {
            Label("New chat", systemImage: "plus")
                .font(.appFont(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .borderGlowButton(accent: accent, isProminent: false)
        }
        .buttonStyle(.plain)
        .help("Start a separate conversation. This one stays saved in History.")
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
                .accessibilityHidden(true)
            TextField("Search conversations", text: $query)
                .textFieldStyle(.plain)
                .font(.appFont(size: 13))
                .foregroundColor(.white)
            if isSearching {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .innerObsidianCard(cornerRadius: 12)
    }

    private var list: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: Spacing.s, pinnedViews: []) {
                ForEach(days) { day in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(day.label)
                                .font(.appFont(size: 13, weight: .bold))
                                .foregroundColor(.white.opacity(0.75))
                            Spacer()
                            Button { pending = .day(day) } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.55))
                                    .padding(6)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Delete all of \(day.label)")
                            .help("Delete this whole day")
                        }
                        ForEach(day.conversations) { conversation in
                            HistoryRow(conversation: conversation, isSelected: assistant.currentConversationID == conversation.id, accent: accent,
                                       open: { assistant.open(conversation) },
                                       delete: { pending = .conversation(conversation) })
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 24)
            Text(isSearching ? "Nothing matches “\(query.trimmingCharacters(in: .whitespacesAndNewlines))”" : "No conversations yet")
                .font(.appFont(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)
            Text(isSearching ? "Try another word." : "Talk or type to Locken and your conversations are saved here, by day, on this Mac.")
                .font(.appFont(size: 11))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
    }

    // MARK: Delete

    private var confirmTitle: String {
        switch pending {
        case .conversation?: return "Delete this conversation?"
        case .day(let day)?: return "Delete all of \(day.label)?"
        case nil: return ""
        }
    }

    private func confirmMessage(_ item: PendingDelete) -> String {
        switch item {
        case .conversation(let conversation):
            return "“\(conversation.title)” and its \(conversation.messages.count) messages will be removed from this Mac. This can't be undone."
        case .day(let day):
            let count = day.conversations.count
            return "\(count) conversation\(count == 1 ? "" : "s") from \(day.label) will be removed from this Mac. This can't be undone."
        }
    }

    private func delete(_ item: PendingDelete) {
        let current = assistant.currentConversationID
        switch item {
        case .conversation(let conversation):
            store.delete(conversation.id)
            if current == conversation.id { assistant.reset() }
        case .day(let day):
            let ids = Set(day.conversations.map(\.id))
            store.deleteDay(day.day)
            if let current, ids.contains(current) { assistant.reset() }
        }
    }
}

/// One saved conversation: its title and start time. The chosen one is outlined in the Assistant's accent colour;
/// hovering only brightens the outline (nothing moves).
private struct HistoryRow: View {
    let conversation: SavedConversation
    let isSelected: Bool
    let accent: Color
    let open: () -> Void
    let delete: () -> Void
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        HStack(spacing: 4) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(conversation.title)
                        .font(.appFont(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(isSelected ? 1 : 0.85))
                        .lineLimit(1)
                    Text("\(conversation.startedAt.formatted(date: .omitted, time: .shortened)) · \(conversation.messages.count) message\(conversation.messages.count == 1 ? "" : "s")")
                        .font(.appFont(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(conversation.title), \(conversation.startedAt.formatted(date: .omitted, time: .shortened))")
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            Button(action: delete) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete conversation \(conversation.title)")
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 8)
        .background(shape.fill(isSelected ? accent.opacity(0.18) : Color.white.opacity(0.04)))
        .overlay(shape.stroke(isSelected ? accent : Color.white.opacity(hovering ? 0.3 : 0.08), lineWidth: isSelected ? 1.5 : 1))
        .onHover { hovering = $0 }
    }
}
