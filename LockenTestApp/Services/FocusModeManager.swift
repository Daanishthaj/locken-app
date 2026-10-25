import AppKit
import Foundation

/// Turns macOS Focus (Do Not Disturb) on when a work session starts and off when it ends.
///
/// macOS has no public API for toggling Focus, and GUI-scripting Control Center would need Accessibility
/// access and break with every OS release. The supported route is the Shortcuts "Set Focus" action:
/// the user creates two shortcuts once, and Locken runs them headlessly with the `/usr/bin/shortcuts` CLI
/// (no window, no extra permission). If the CLI is missing, the `shortcuts://run-shortcut` URL scheme is
/// the fallback, which briefly brings the Shortcuts app forward.
///
/// One-time setup is a button: `setUp()` builds both shortcuts, signs them with `shortcuts sign`, and opens each
/// in Shortcuts, where the user only clicks "Add Shortcut":
/// - "Locken Focus On": **Set Focus** → turn **Do Not Disturb** **On** until **Turned Off**
/// - "Locken Focus Off": **Set Focus** → turn **Do Not Disturb** **Off**
@MainActor
final class FocusModeManager: ObservableObject {
    static let shared = FocusModeManager()

    static let enableShortcutName = "Locken Focus On"
    static let disableShortcutName = "Locken Focus Off"

    enum FocusModeError: LocalizedError, Equatable {
        case shortcutMissing(String)
        case shortcutFailed(name: String, status: Int32, output: String)
        case timedOut(String)
        case launchFailed(String)
        case signingFailed(String)

        var errorDescription: String? {
            switch self {
            case .shortcutMissing(let name):
                return "The \"\(name)\" shortcut doesn't exist yet. Create it in Shortcuts with the Set Focus action."
            case .shortcutFailed(let name, let status, let output):
                return "The \"\(name)\" shortcut failed (exit \(status))\(output.isEmpty ? "." : ": \(output)")"
            case .timedOut(let name):
                return "The \"\(name)\" shortcut didn't finish within 15 seconds."
            case .launchFailed(let reason):
                return "Couldn't run Shortcuts: \(reason)"
            case .signingFailed(let output):
                return "Shortcuts couldn't prepare the Focus shortcut. Check you're online and signed in to iCloud\(output.isEmpty ? "." : ": \(output)")"
            }
        }
    }

    /// What Locken last set. macOS doesn't expose the real Focus state without Full Disk Access,
    /// so a Focus changed by hand in Control Center isn't reflected here.
    @Published private(set) var isFocusActive = false
    @Published private(set) var isBusy = false
    @Published private(set) var lastError: FocusModeError?

    enum SetupState: Equatable {
        case checking
        case notSetUp
        /// Shortcuts is showing this shortcut's import window; waiting for the user to click "Add Shortcut".
        case waitingForAdd(String)
        case ready
    }
    @Published private(set) var setupState: SetupState = .checking
    /// Which of the two shortcuts aren't in Shortcuts yet. Focus only turns on once both exist, so it can
    /// always be turned back off.
    @Published private(set) var missingShortcuts: [String] = []

    nonisolated private static let cliURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
    nonisolated private static let timeout: TimeInterval = 15

    private init() {}

    // MARK: Session hooks

    /// Call when a work session starts.
    func activate() async {
        guard !isFocusActive else { return }
        if await run(Self.enableShortcutName) { isFocusActive = true }
    }

    /// Call when a work session ends or is paused.
    func deactivate() async {
        guard isFocusActive else { return }
        if await run(Self.disableShortcutName) { isFocusActive = false }
    }

    /// True when both shortcuts exist, so sessions can toggle Focus.
    func isConfigured() async -> Bool {
        let names = await Self.installedShortcutNames()
        return names.contains(Self.enableShortcutName) && names.contains(Self.disableShortcutName)
    }

    /// Opens the Shortcuts editor so the user can create the two shortcuts above.
    func openShortcutsForSetup() {
        if let url = URL(string: "shortcuts://create-shortcut") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: One-click setup

    func refreshSetupState() async {
        if case .waitingForAdd = setupState { return }
        let names = await Self.installedShortcutNames()
        missingShortcuts = [Self.enableShortcutName, Self.disableShortcutName].filter { !names.contains($0) }
        setupState = missingShortcuts.isEmpty ? .ready : .notSetUp
    }

    /// Creates whichever of the two shortcuts is missing and opens it in Shortcuts for the user to add.
    /// Waits up to 3 minutes for each "Add Shortcut" click.
    func setUp() async {
        lastError = nil
        for (name, enablesFocus) in [(Self.enableShortcutName, true), (Self.disableShortcutName, false)] {
            if await Self.installedShortcutNames().contains(name) { continue }
            do {
                let file = try await Self.makeShortcutFile(named: name, enablesFocus: enablesFocus)
                setupState = .waitingForAdd(name)
                NSWorkspace.shared.open(file)
                guard await waitUntilInstalled(name) else {
                    setupState = .notSetUp
                    lastError = .shortcutMissing(name)
                    return
                }
            } catch let error as FocusModeError {
                setupState = .notSetUp
                lastError = error
                return
            } catch {
                setupState = .notSetUp
                lastError = .launchFailed(error.localizedDescription)
                return
            }
        }
        missingShortcuts = []
        setupState = .ready
    }

    private func waitUntilInstalled(_ name: String) async -> Bool {
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline {
            try? await Task.sleep(for: .seconds(1.5))
            if await Self.installedShortcutNames().contains(name) { return true }
        }
        return false
    }

    /// Writes the shortcut as an unsigned workflow plist, then signs it so Shortcuts will import it.
    nonisolated private static func makeShortcutFile(named name: String, enablesFocus: Bool) async throws -> URL {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw FocusModeError.launchFailed("no Application Support folder")
        }
        let folder = support.appendingPathComponent("LockenTestApp/Shortcuts", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let unsigned = folder.appendingPathComponent("\(name) unsigned.shortcut")
        // Shortcuts names an imported shortcut after its file.
        let signed = folder.appendingPathComponent("\(name).shortcut")

        let workflow: [String: Any] = [
            "WFWorkflowClientVersion": "2607.0.2",
            "WFWorkflowMinimumClientVersion": 900,
            "WFWorkflowMinimumClientVersionString": "900",
            "WFWorkflowIcon": ["WFWorkflowIconStartColor": 4_282_601_983, "WFWorkflowIconGlyphNumber": 59_511],
            "WFWorkflowImportQuestions": [Any](),
            "WFWorkflowTypes": [Any](),
            "WFWorkflowInputContentItemClasses": [Any](),
            "WFWorkflowActions": [[
                "WFWorkflowActionIdentifier": "is.workflow.actions.dnd.set",
                "WFWorkflowActionParameters": [
                    "Enabled": enablesFocus ? 1 : 0,
                    "AssertionType": "Turned Off",
                    "FocusModes": [
                        "Identifier": "com.apple.donotdisturb.mode.default",
                        "DisplayString": "Do Not Disturb",
                    ],
                ] as [String: Any],
            ]],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: workflow, format: .binary, options: 0)
        try data.write(to: unsigned, options: .atomic)
        defer { try? FileManager.default.removeItem(at: unsigned) }
        try? FileManager.default.removeItem(at: signed)

        let result = try await runProcess(
            arguments: ["sign", "--mode", "anyone", "--input", unsigned.path, "--output", signed.path],
            timeout: 60
        )
        guard result.status == 0, !result.timedOut, FileManager.default.fileExists(atPath: signed.path) else {
            throw FocusModeError.signingFailed(result.output)
        }
        return signed
    }

    // MARK: Running shortcuts

    /// Runs a shortcut and records any error. Returns true on success.
    private func run(_ name: String) async -> Bool {
        isBusy = true
        defer { isBusy = false }
        do {
            try await Self.runShortcut(named: name)
            lastError = nil
            return true
        } catch let error as FocusModeError {
            lastError = error
            return false
        } catch {
            lastError = .launchFailed(error.localizedDescription)
            return false
        }
    }

    nonisolated private static func runShortcut(named name: String) async throws {
        guard FileManager.default.isExecutableFile(atPath: cliURL.path) else {
            // No CLI (very old macOS): the URL scheme runs it through the Shortcuts app instead.
            var components = URLComponents(string: "shortcuts://run-shortcut")!
            components.queryItems = [URLQueryItem(name: "name", value: name)]
            guard let url = components.url else { throw FocusModeError.launchFailed("bad shortcut name") }
            await MainActor.run { _ = NSWorkspace.shared.open(url) }
            return
        }

        let installed = await installedShortcutNames()
        guard installed.contains(name) else { throw FocusModeError.shortcutMissing(name) }

        let result = try await runProcess(arguments: ["run", name])
        if result.timedOut { throw FocusModeError.timedOut(name) }
        guard result.status == 0 else {
            throw FocusModeError.shortcutFailed(name: name, status: result.status, output: result.output)
        }
    }

    nonisolated private static func installedShortcutNames() async -> Set<String> {
        guard let result = try? await runProcess(arguments: ["list"]), result.status == 0 else { return [] }
        return Set(result.output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) })
    }

    /// Runs `/usr/bin/shortcuts` off the main thread with a timeout; never blocks the UI.
    nonisolated private static func runProcess(arguments: [String], timeout: TimeInterval = timeout) async throws -> (status: Int32, output: String, timedOut: Bool) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = cliURL
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            // Shared by the pipe, termination and timeout callbacks, which run on different threads.
            let run = ProcessRun()

            // Drain output as it arrives so a long `shortcuts list` can't fill the pipe and stall the process.
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                run.locked { $0.collected.append(chunk) }
            }

            process.terminationHandler = { process in
                pipe.fileHandleForReading.readabilityHandler = nil
                let rest = pipe.fileHandleForReading.readDataToEndOfFile()
                let (output, alreadyFinished, didTimeOut) = run.locked { state -> (String, Bool, Bool) in
                    state.collected.append(rest)
                    let output = String(decoding: state.collected, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    let alreadyFinished = state.finished
                    state.finished = true
                    return (output, alreadyFinished, state.timedOut)
                }
                guard !alreadyFinished else { return }
                continuation.resume(returning: (process.terminationStatus, output, didTimeOut))
            }

            do {
                try process.run()
            } catch {
                run.locked { $0.finished = true }
                continuation.resume(throwing: FocusModeError.launchFailed(error.localizedDescription))
                return
            }

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                let stillRunning = run.locked { state -> Bool in
                    if !state.finished { state.timedOut = true }
                    return !state.finished
                }
                // terminate() fires terminationHandler, which reports the timeout.
                if stillRunning { process.terminate() }
            }
        }
    }
}

/// The mutable state of one `shortcuts` run, behind a lock so its callbacks can share it safely.
private final class ProcessRun: @unchecked Sendable {
    struct State {
        var finished = false
        var timedOut = false
        var collected = Data()
    }

    private let lock = NSLock()
    private var state = State()

    func locked<T>(_ body: (inout State) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&state)
    }
}
