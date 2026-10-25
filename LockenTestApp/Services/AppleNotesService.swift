import AppKit
import Foundation

/// Shows the student's Apple Notes next to Locken's own notes. Apple Notes has no public API, so this reads
/// note titles, dates and the first lines through Apple Events (macOS asks once: "Locken wants to control
/// Notes"); no Full Disk Access. Nothing is saved to disk or sent anywhere: the list lives in memory, and
/// clicking a note opens it in the Notes app. Connected or not is remembered per account.
@MainActor
final class AppleNotesService: ObservableObject {
    static let shared = AppleNotesService()

    struct Note: Identifiable, Equatable {
        let id: String
        let title: String
        let modified: Date
        var preview: String
    }

    @Published private(set) var isConnected = false
    @Published private(set) var notes: [Note] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    /// How many of the most recently edited notes are shown.
    nonisolated static let shownCount = 30
    static let connectedKey = "appleNotes.connected"

    // NSAppleScript waits for Notes to reply, so scripts run here, one at a time, off the main thread.
    private let scriptQueue = DispatchQueue(label: "com.locken.LockenTestApp.apple-notes", qos: .userInitiated)

    private init() {}

    func activateAccount() {
        isConnected = UserDefaults.standard.bool(forKey: Self.connectedKey + AccountScope.suffix)
        notes = []
        errorMessage = nil
        if isConnected { refresh() }
    }

    /// The first read triggers macOS's Automation prompt; a refusal shows how to allow it later.
    func connect() {
        isConnected = true
        UserDefaults.standard.set(true, forKey: Self.connectedKey + AccountScope.suffix)
        refresh()
    }

    func disconnect() {
        isConnected = false
        UserDefaults.standard.removeObject(forKey: Self.connectedKey + AccountScope.suffix)
        notes = []
        errorMessage = nil
    }

    func refresh() {
        guard isConnected, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        scriptQueue.async {
            let result = Self.fetchNotes()
            Task { @MainActor in self.apply(result) }
        }
    }

    private func apply(_ result: FetchResult) {
        isLoading = false
        switch result {
        case .success(let notes): self.notes = notes
        case .failure(let message): errorMessage = message
        }
    }

    /// Opens the note in the Notes app.
    func open(_ note: Note) {
        let id = Self.escaped(note.id)
        scriptQueue.async {
            var error: NSDictionary?
            NSAppleScript(source: """
            tell application "Notes"
                show note id "\(id)"
                activate
            end tell
            """)?.executeAndReturnError(&error)
        }
    }

    // MARK: Scripts (run on scriptQueue)

    private enum FetchResult {
        case success([Note])
        case failure(String)
    }

    /// Titles and dates of every note outside Recently Deleted (subfolders included), newest first, then the
    /// first lines of the ones shown. Locked notes keep their title and show no preview.
    nonisolated private static func fetchNotes() -> FetchResult {
        let listScript = """
        on collectFolder(f, output)
            tell application "Notes"
                if name of f is not "Recently Deleted" then
                    set end of output to {id of notes of f, name of notes of f, modification date of notes of f}
                    repeat with child in folders of f
                        my collectFolder(child, output)
                    end repeat
                end if
            end tell
        end collectFolder

        set output to {}
        tell application "Notes"
            repeat with acc in accounts
                repeat with f in folders of acc
                    my collectFolder(f, output)
                end repeat
            end repeat
        end tell
        return output
        """
        var error: NSDictionary?
        guard let descriptor = NSAppleScript(source: listScript)?.executeAndReturnError(&error), error == nil else {
            return .failure(message(for: error))
        }

        var seen = Set<String>()
        var all: [Note] = []
        for folderIndex in stride(from: 1, through: descriptor.numberOfItems, by: 1) {
            guard let folder = descriptor.atIndex(folderIndex), folder.numberOfItems == 3,
                  let ids = folder.atIndex(1), let names = folder.atIndex(2), let dates = folder.atIndex(3) else { continue }
            for index in stride(from: 1, through: ids.numberOfItems, by: 1) {
                guard let id = ids.atIndex(index)?.stringValue, seen.insert(id).inserted else { continue }
                all.append(Note(
                    id: id,
                    title: names.atIndex(index)?.stringValue ?? "",
                    modified: dates.atIndex(index)?.dateValue ?? .distantPast,
                    preview: ""
                ))
            }
        }
        var shown = Array(all.sorted { $0.modified > $1.modified }.prefix(shownCount))
        guard !shown.isEmpty else { return .success([]) }

        let idList = shown.map { "\"\(escaped($0.id))\"" }.joined(separator: ", ")
        let previewScript = """
        set output to {}
        tell application "Notes"
            repeat with noteID in {\(idList)}
                try
                    set end of output to plaintext of note id noteID
                on error
                    set end of output to ""
                end try
            end repeat
        end tell
        return output
        """
        var previewError: NSDictionary?
        if let previews = NSAppleScript(source: previewScript)?.executeAndReturnError(&previewError), previewError == nil {
            for index in shown.indices {
                let text = previews.atIndex(index + 1)?.stringValue ?? ""
                shown[index].preview = preview(of: text, title: shown[index].title)
            }
        }
        return .success(shown)
    }

    /// The note's text after its first line (Notes repeats the title there), shortened for a two-line preview.
    nonisolated static func preview(of text: String, title: String) -> String {
        var lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if lines.first == title.trimmingCharacters(in: .whitespaces) { lines.removeFirst() }
        return String(lines.joined(separator: " ").prefix(200))
    }

    nonisolated private static func message(for error: NSDictionary?) -> String {
        switch error?[NSAppleScript.errorNumber] as? Int {
        case -1743: // errAEEventNotPermitted
            return "Allow Locken to use Notes in System Settings › Privacy & Security › Automation, then refresh."
        case -1712: // errAETimeout
            return "Notes took too long to answer. Try refreshing."
        default:
            return "Couldn't read Apple Notes. Try refreshing."
        }
    }

    /// Note IDs are Notes' own x-coredata URLs; escape them anyway before they go inside a script string.
    nonisolated private static func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
