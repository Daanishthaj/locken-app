import SwiftUI
import AppKit
import CoreText

@main
struct LockenTestApp: App {
    @NSApplicationDelegateAdaptor(TestAppDelegate.self) var appDelegate
    @StateObject private var state = TestAppStateManager.shared

    init() {
        // Register the bundled Doto and Montserrat fonts; Info.plist's UIAppFonts key is iOS-only and does nothing on macOS.
        for url in Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [] {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            IntroHost { DisplayScaleRoot { AuthGate() } }
                .preferredColorScheme(.dark)
                .onAppear {
                    state.selectedTab = "dashboard"
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 720)
        .commands {
            // macOS HIG Menu Commands
            CommandGroup(replacing: .newItem) {
                Button(state.isTimerActive ? "Pause Focus" : "Start Focus") {
                    state.selectedTab = "focus"
                    state.toggleTimer()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Note...") {
                    state.selectedTab = "notes"
                    state.addNote()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            CommandMenu("Navigate") {
                Button("New (Dashboard)") { state.selectedTab = "dashboard" }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Artifacts") { state.selectedTab = "artifacts" }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Customize") { state.selectedTab = "customize" }
                    .keyboardShortcut("4", modifiers: .command)
                Button("Focus Session") { state.selectedTab = "focus" }
                    .keyboardShortcut("5", modifiers: .command)
                Button("Calendar") { state.selectedTab = "calendar" }
                    .keyboardShortcut("6", modifiers: .command)
                Button("Analytics") { state.selectedTab = "analytics" }
                    .keyboardShortcut("7", modifiers: .command)
            }

            CommandMenu("Focus") {
                Button(state.isTimerActive ? "Pause Focus" : "Start Focus") {
                    state.toggleTimer()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button("Toggle Focus Shield") {
                    // Turning the Shield off during a session goes through commitment mode, like pausing.
                    if state.isShieldActive && state.isTimerActive {
                        state.requestStop(.shieldOff)
                    } else {
                        state.isShieldActive.toggle()
                    }
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }

        // The menu bar timer: a lock and the time left, with a panel to pause, end or start a session.
        MenuBarExtra {
            MenuBarTimerPanel()
                .preferredColorScheme(.dark)
        } label: {
            MenuBarTimerLabel()
        }
        .menuBarExtraStyle(.window)
    }
}

final class TestAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only one Locken at a time: an older copy still running (for example the one an update replaced) is asked
        // to quit, so the window on screen is always the current version.
        let me = ProcessInfo.processInfo.processIdentifier
        if let bundleID = Bundle.main.bundleIdentifier {
            for other in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) where other.processIdentifier != me {
                other.terminate()
            }
        }
        // Shutting down, restarting or logging out is never held up by a running session.
        // A running session is kept and picks up when Locken next opens.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main) { _ in
            AppQuit.isAllowed = true
            AppQuit.reason = .powerOff
        }
        ScreenUsageTracker.shared.start()
        NowPlayingService.shared.start()
        HabitReminders.install()
        // Started by macOS at login (Settings › Open at login): stay in the menu bar with the window hidden.
        let atLogin = LaunchAtLogin.openedAtLogin()
        DispatchQueue.main.async {
            if !atLogin { NSApplication.shared.activate(ignoringOtherApps: true) }
            if let window = NSApplication.shared.windows.first {
                window.title = "Locken"
                window.titlebarAppearsTransparent = true
                // Moving the window only from its top bar: dragging from the background also caught slider drags.
                window.isMovableByWindowBackground = false
                window.center()
                if !atLogin { window.makeKeyAndOrderFront(nil) }
                Self.alignTrafficLights(of: window)
                // AppKit puts the buttons back whenever it lays the title bar out again, so they are placed again after these.
                for name in [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification, NSWindow.didBecomeKeyNotification,
                             NSWindow.didExitFullScreenNotification, NSWindow.didDeminiaturizeNotification] {
                    NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { note in
                        guard let window = note.object as? NSWindow else { return }
                        MainActor.assumeIsolated { Self.alignTrafficLights(of: window) }
                    }
                }
            }
            if atLogin { NSApplication.shared.hide(nil) }
        }
    }

    /// The red, yellow and green buttons, placed where the window's rounded corner curves: the first one's left edge 20 pt in,
    /// lined up with the sidebar's logo, and all three centred 22 pt from the top. Left alone, macOS leaves them at about 8 pt,
    /// crowding the corner of the large rounded window. The title bar is made 44 pt tall to hold them (a click in that strip
    /// drags the window, so nothing clickable sits above 44 pt). Safe to call again and again: it only moves what is out of place.
    @MainActor private static func alignTrafficLights(of window: NSWindow) {
        guard !window.styleMask.contains(.fullScreen),
              let close = window.standardWindowButton(.closeButton), let titlebar = close.superview, let container = titlebar.superview
        else { return }
        let height: CGFloat = 44
        let strip = NSRect(x: 0, y: window.frame.height - height, width: window.frame.width, height: height)
        if container.frame != strip { container.frame = strip }
        let inner = NSRect(origin: .zero, size: strip.size)
        if titlebar.frame != inner { titlebar.frame = inner }
        for (index, type) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
            guard let button = window.standardWindowButton(type) else { continue }
            let origin = NSPoint(x: 26 + CGFloat(index) * 20 - button.frame.width / 2, y: (height - button.frame.height) / 2)
            if button.frame.origin != origin { button.setFrameOrigin(origin) }
        }
    }

    /// Turns Do Not Disturb back off if Locken quits mid-session, so Focus isn't left on with nothing to end it.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Commitment mode: quitting during a running session shows the countdown first (it quits from there).
        let state = TestAppStateManager.shared
        if !AppQuit.isAllowed && state.isTimerActive && state.isCommitmentModeOn {
            state.commitmentRequest = .quit
            sender.activate(ignoringOtherApps: true)
            sender.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
            return .terminateCancel
        }
        guard FocusModeManager.shared.isFocusActive else { return .terminateNow }
        Task { @MainActor in
            await FocusModeManager.shared.deactivate()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// What happens to a running session when Locken quits. A force quit or crash never gets here, so the saved
    /// session stays and picks up when Locken opens again.
    func applicationWillTerminate(_ notification: Notification) {
        if AppQuit.reason == .user { TestAppStateManager.shared.endRunningSessionForQuit() }
    }

    // Keep running with the window closed so Analytics keeps measuring app usage.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
