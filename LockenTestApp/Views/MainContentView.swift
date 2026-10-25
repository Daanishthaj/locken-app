import SwiftUI
import AppKit

public struct MainContentView: View {
    @ObservedObject var state = TestAppStateManager.shared
    @ObservedObject private var admin = AdminManager.shared
    @Namespace private var sidebarPill
    /// The sidebar folded into a rail of icon buttons (remembered between launches).
    @AppStorage("sidebar.collapsed") private var sidebarCollapsed = false
    /// While the rail's tiles close, before the sidebar widens.
    @State private var railClosing = false

    /// Admin mode replaces the whole window (sidebar included) with the owner's console.
    private var isAdminMode: Bool { state.selectedTab == "admin" && admin.isAdmin }

    public var body: some View {
        ZStack {
            if isAdminMode {
                AdminConsoleView()
                    .transition(.opacity)
            } else {
                mainUI
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isAdminMode)
    }

    private func toggleSidebar() {
        guard !railClosing else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let animation: Animation? = reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 1)
        // Opening: the rail's tiles close first (their intro played backwards), then the sidebar widens.
        if sidebarCollapsed, !reduceMotion {
            railClosing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + SidebarRail.closeDuration) {
                railClosing = false
                withAnimation(animation) { sidebarCollapsed = false }
            }
            return
        }
        withAnimation(animation) { sidebarCollapsed.toggle() }
    }

    /// How far each tab's tile colour is mixed toward black (test).
    private static func tileDarkness(for tab: String) -> CGFloat {
        tab == "dashboard" ? 0.88 : tab == "focus" ? 0.85 : 0.90
    }

    /// The Locken logo (purple padlock), same art as the app icon, shifted to the current tab's colour. One view for both
    /// sidebars: 32 pt in the header when open, 56 pt over the rail when collapsed, and it moves and resizes with the sidebar.
    private var sidebarLogo: some View {
        let size: CGFloat = sidebarCollapsed ? 56 : 32
        let radius: CGFloat = sidebarCollapsed ? 14 : 8
        return Image("LockenLogo")
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .hueRotation(LogoTint.rotation(for: state.selectedTab))
            .saturation(LogoTint.saturation(for: state.selectedTab))
            .animation(.easeOut(duration: 0.35), value: state.selectedTab)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 1))
            .padding(.leading, sidebarCollapsed ? (SidebarRail.width - 56) / 2 : 22)
            .padding(.top, sidebarCollapsed ? 38 : 44)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// The full sidebar: brand, every page, and the profile card.
    private var expandedSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Traffic-Light Window Safe Area & Brand Header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(SquircleTokens.accentColor(for: state.selectedTab).opacity(0.25))
                        .frame(width: 36, height: 36)
                        .blur(radius: 8)

                    // The Locken logo is drawn by `sidebarLogo`, which moves and resizes with the sidebar; this keeps its room.
                    Color.clear.frame(width: 32, height: 32)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Locken")
                        .font(.appFont(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    Text("Focus for Mac")
                        .font(.appFont(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 42)
            .padding(.bottom, 24)

            // Scrollable Navigation Section
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    // Section: Primary Actions
                    SidebarNavItem(
                        title: "New",
                        icon: "plus.circle.fill",
                        isSelected: state.selectedTab == "new" || state.selectedTab == "dashboard",
                        accent: SquircleTokens.accentColor(for: "dashboard"),
                        pill: sidebarPill
                    ) {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                            state.selectedTab = "dashboard"
                        }
                    }

                    // Divider
                    SectionDivider()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)

                    SidebarNavItem(
                        title: "Focus Session",
                        icon: "bolt.fill",
                        isSelected: state.selectedTab == "focus",
                        accent: SquircleTokens.accentColor(for: "focus"),
                        // A live dot and the time left while a session runs, instead of a generic badge.
                        liveText: state.isTimerActive
                            ? String(format: "%d:%02d", state.timerSecondsRemaining / 60, state.timerSecondsRemaining % 60)
                            : nil,
                        pill: sidebarPill
                    ) {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                            state.selectedTab = "focus"
                        }
                    }

                    SidebarNavItem(
                        title: "Assistant",
                        icon: "waveform",
                        isSelected: state.selectedTab == "assistant",
                        accent: SquircleTokens.accentColor(for: "assistant"),
                        pill: sidebarPill
                    ) {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                            state.selectedTab = "assistant"
                        }
                    }

                    SidebarNavItem(
                        title: "Calendar",
                        icon: "calendar",
                        isSelected: state.selectedTab == "calendar",
                        accent: SquircleTokens.accentColor(for: "calendar"),
                        pill: sidebarPill
                    ) {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                            state.selectedTab = "calendar"
                        }
                    }

                    SidebarNavItem(
                        title: "Habit Tracker",
                        icon: "flame.fill",
                        isSelected: state.selectedTab == "analytics" || state.selectedTab == "habits",
                        accent: SquircleTokens.accentColor(for: "analytics"),
                        pill: sidebarPill
                    ) {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                            state.selectedTab = "analytics"
                        }
                    }

                    SidebarNavItem(
                        title: "Analytics",
                        icon: "chart.bar.xaxis",
                        isSelected: state.selectedTab == "usage",
                        accent: SquircleTokens.accentColor(for: "usage"),
                        pill: sidebarPill
                    ) {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                            state.selectedTab = "usage"
                        }
                    }

                    SidebarNavItem(
                        title: "Notes & Reminders",
                        icon: "note.text",
                        isSelected: state.selectedTab == "artifacts" || state.selectedTab == "notes",
                        accent: SquircleTokens.accentColor(for: "artifacts"),
                        pill: sidebarPill
                    ) {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                            state.selectedTab = "artifacts"
                        }
                    }

                    // Only shown to the owner's accounts; the server refuses everyone else anyway.
                    if admin.isAdmin {
                        SidebarNavItem(
                            title: "Admin",
                            icon: "lock.shield",
                            isSelected: state.selectedTab == "admin",
                            accent: SquircleTokens.accentColor(for: "admin"),
                            pill: sidebarPill
                        ) {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                                state.selectedTab = "admin"
                            }
                        }
                    }

                }
                .padding(.horizontal, 10)
            }

            Spacer()

            // ── Bottom Sidebar Footer: ProfileCard (React Bits) with now playing ──
            SidebarProfileCard()
                .frame(height: 224)
                .padding(.horizontal, 14)
                .padding(.bottom, 20)
        }
    }

    private var mainUI: some View {
        ZStack {
            // ── 1. Background ──
            // Near-black (#0B0B0F, the obsidian base) behind the window on every tab, no gradients, glow or drifting lines.
            SquircleTokens.obsidianBase
                .ignoresSafeArea()

            // ── 2. Primary Layout ──
            HStack(spacing: 0) {
                // ── Left Collapsible Obsidian Sidebar ──
                // Collapsed, it is a narrow rail of React Bits GlassIcons buttons.
                // The two sidebars slide out to and in from the left while the width follows, with one logo that moves and resizes
                // between them.
                ZStack(alignment: .topLeading) {
                    if sidebarCollapsed {
                        SidebarRail(isAdmin: admin.isAdmin, isClosing: railClosing)
                            .frame(width: SidebarRail.width)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    } else {
                        expandedSidebar
                            .frame(width: 236)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
                .frame(width: sidebarCollapsed ? SidebarRail.width : 236, alignment: .topLeading)
                .clipped()
                .overlay(alignment: .topLeading) { sidebarLogo }
                // One button that stays put as the sidebar folds: its icon morphs, and it slides from the header to the bottom of the rail.
                .overlay(alignment: sidebarCollapsed ? .bottomLeading : .topLeading) {
                    Button(action: toggleSidebar) {
                        SidebarToggleIcon(isOpen: !sidebarCollapsed)
                            .frame(width: 24, height: 24)
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(sidebarCollapsed ? "Expand the sidebar" : "Collapse the sidebar")
                    .accessibilityLabel(sidebarCollapsed ? "Expand the sidebar" : "Collapse the sidebar")
                    .padding(.leading, sidebarCollapsed ? 32 : 188)
                    .padding(sidebarCollapsed ? .bottom : .top, sidebarCollapsed ? 20 : 44)
                }

                // ── Right Floating Liquid Glass Canvas & Bottom Command Bar ──
                ZStack(alignment: .bottom) {
                    // View Router
                    Group {
                        if state.isSessionIntroPlaying {
                            SessionIntroView()
                        } else if state.isCountdownPresented {
                            FocusCountdownView()
                        } else {
                        switch state.selectedTab {
                        case "dashboard", "new":
                            TestDashboardView()
                        case "focus":
                            TestFocusSessionView()
                        case "admin":
                            TestDashboardView()
                        case "assistant":
                            AssistantView()
                        case "calendar":
                            TestCalendarTimelineView()
                        case "analytics":
                            TestAnalyticsView()
                        case "usage":
                            UsageAnalyticsView()
                        case "artifacts", "notes":
                            TestProjectStudioView()
                        case "customize", "settings":
                            TestSettingsView()
                        default:
                            TestDashboardView()
                        }
                        }
                    }
                    .revealWhenLoaded()
                    .id(state.isSessionIntroPlaying ? "intro" : state.isCountdownPresented ? "countdown" : state.selectedTab)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.22), value: state.selectedTab)
                    .animation(.easeInOut(duration: 0.3), value: state.isCountdownPresented)
                    .animation(.easeInOut(duration: 0.3), value: state.isSessionIntroPlaying)

                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    // Every tab (test): a dark tile with a slight tint of its page colour; Home a little more.
                    SquircleTokens.accentColor(for: state.selectedTab).darkened(Self.tileDarkness(for: state.selectedTab))
                        // Focus: fainter, so its violet tile blends into the near-black window instead of standing out.
                        .opacity(state.selectedTab == "focus" ? 0.55 : 0.95)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .animation(.easeInOut(duration: 0.4), value: state.selectedTab)
                )
                .liquidGlassCard(cornerRadius: 24)
                .padding(.trailing, 18)
                .padding(.vertical, 18)
            }
        }
        .magicBentoSection(glowColor: SquircleTokens.accentColor(for: state.selectedTab))
        .frame(minWidth: 1140, minHeight: 740)
        // Default for any text that doesn't set its own font.
        .font(.appFont(size: 13))
    }
}

// MARK: - Session start transition

/// Plays papers.html (ten cream papers fly out and back) between starting a session and its timer page.
/// The page posts "flying" when a flight starts and "done" once the papers are home; the timer starts then.
private struct SessionIntroView: View {
    @ObservedObject private var state = TestAppStateManager.shared
    /// Restarts the safety net each time the papers fly.
    @State private var flight = UUID()

    var body: some View {
        ReactBitsWebView(page: .papers, onMessage: { message in
            switch message {
            case "flying": flight = UUID()
            case "done": state.finishSessionIntro()
            default: break
            }
        })
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityHidden(true)
        // If the page never reports back, don't leave the user stuck before their timer.
        .task(id: flight) {
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { state.finishSessionIntro() }
        }
    }
}

// MARK: - Sidebar ProfileCard (React Bits)
/// Its own view so now-playing updates (every couple of seconds) redraw only the card, not the whole window.
private struct SidebarProfileCard: View {
    @ObservedObject private var state = TestAppStateManager.shared
    @ObservedObject private var nowPlaying = NowPlayingService.shared

    private var status: String { state.isLocalOnlyMode ? "Saved on this Mac" : "Synced to your account" }

    /// The card's top row shows what's playing in Spotify or Music instead of the name.
    private var musicProps: [String: String] {
        if let track = nowPlaying.track {
            return [
                "musicState": "track",
                "musicTitle": track.title,
                "musicCover": track.artworkURL ?? "",
                "musicPlaying": track.isPlaying ? "1" : "0",
            ]
        }
        if nowPlaying.needsConsent { return ["musicState": "consent"] }
        if !nowPlaying.deniedPlayers.isEmpty { return ["musicState": "denied"] }
        let idle = nowPlaying.runningPlayers.isEmpty ? "Open Spotify or Music" : "Nothing playing"
        return ["musicState": "idle", "musicIdleText": idle]
    }

    var body: some View {
        ReactBitsWebView(
            page: .profileCard,
            props: [
                "name": state.displayName.isEmpty ? "Locken" : state.displayName,
                "handle": NSUserName(),
                "status": status,
                "avatarUrl": ProfileAvatar.dataURL ?? "",
                "settingsIcon": SymbolLogo.dataURL(systemName: "gearshape.fill") ?? "",
                // Faint tint from the current tab's palette, kept low so the card doesn't outshine the sidebar.
                "innerGradient": {
                    let colors = SquircleTokens.glowGradientColors(for: state.selectedTab)
                    return "linear-gradient(145deg,\(colors[0].hexRGB)33 0%,\(colors[2].hexRGB)1a 100%)"
                }(),
                "behindGlowColor": SquircleTokens.accentColor(for: state.selectedTab).hexRGB + "40",
            ].merging(musicProps) { _, music in music },
            onMessage: { message in
                switch message {
                case "openSettings": state.selectedTab = "customize"
                case "playPause": nowPlaying.playPause()
                case "connectMusic": nowPlaying.connect()
                case "openAutomation":
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                        NSWorkspace.shared.open(url)
                    }
                default: break
                }
            }
        )
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAction(named: "Open Settings") { state.selectedTab = "customize" }
        .accessibilityAction(named: nowPlaying.track?.isPlaying == true ? "Pause" : "Play") { nowPlaying.playPause() }
    }

    private var accessibilityLabel: String {
        let name = state.displayName.isEmpty ? "Profile" : state.displayName
        guard let track = nowPlaying.track else { return "\(name), \(status)" }
        return "Now playing \(track.title) by \(track.artist). \(name), \(status)"
    }
}

// MARK: - Collapsed sidebar rail (React Bits GlassIcons)

/// The sidebar folded down to one glass button per page. The buttons are React Bits GlassIcons in a web view that reports
/// its size and each press ("select:<id>"); the page you're on gets a ring.
private struct SidebarRail: View {
    static let width: CGFloat = 96
    /// How long the tiles take to close: the last one starts first, 0.04 s apart, and each takes about 0.3 s.
    static let closeDuration: TimeInterval = 0.6

    @ObservedObject private var state = TestAppStateManager.shared
    let isAdmin: Bool
    let isClosing: Bool
    /// The pages' buttons and, apart at the bottom, Settings and Admin: each group is its own web view with its own size.
    @State private var railSize = CGSize(width: 92, height: 300)
    @State private var bottomSize = CGSize(width: 92, height: 60)
    private static let bottomIDs: Set<String> = ["settings", "admin"]

    private struct Page {
        let id: String
        let label: String
        /// The tab a press opens.
        let tab: String
        let icon: String
    }

    private var pages: [Page] {
        var list = [
            Page(id: "new", label: "New", tab: "dashboard", icon: "new"),
            Page(id: "focus", label: "Focus", tab: "focus", icon: "focus"),
            Page(id: "assistant", label: "Assistant", tab: "assistant", icon: "assistant"),
            Page(id: "calendar", label: "Calendar", tab: "calendar", icon: "calendar"),
            Page(id: "habits", label: "Habits", tab: "analytics", icon: "habits"),
            Page(id: "analytics", label: "Analytics", tab: "usage", icon: "analytics"),
            Page(id: "notes", label: "Notes", tab: "artifacts", icon: "notes"),
            Page(id: "settings", label: "Settings", tab: "settings", icon: "settings"),
        ]
        // Only the owner's accounts, like the full sidebar.
        if isAdmin { list.append(Page(id: "admin", label: "Admin", tab: "admin", icon: "admin")) }
        return list
    }

    /// Which button carries the ring for the open tab (a few pages share one button, as in the full sidebar).
    private var selectedID: String {
        switch state.selectedTab {
        case "dashboard", "new": return "new"
        case "analytics", "habits": return "habits"
        case "usage": return "analytics"
        case "artifacts", "notes": return "notes"
        case "customize", "settings": return "settings"
        default: return state.selectedTab
        }
    }

    private func props(for group: [Page], gap: CGFloat) -> [String: String] {
        // The buttons' colours come from the page itself (one muted palette, by id), not from the tabs' accents.
        let items = group.map { ["id": $0.id, "label": $0.label, "icon": $0.icon] }
        let json = (try? JSONSerialization.data(withJSONObject: items)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return ["items": json, "value": selectedID, "size": "40", "gap": String(format: "%.0f", gap), "closing": isClosing ? "1" : ""]
    }

    private func handle(_ message: String, size: Binding<CGSize>) {
        if message.hasPrefix("size:") {
            let parts = message.dropFirst(5).split(separator: "x").compactMap { Double($0) }
            if parts.count == 2, parts[0] > 0, parts[1] > 0 { size.wrappedValue = CGSize(width: parts[0], height: parts[1]) }
        } else if message.hasPrefix("select:"), let page = pages.first(where: { $0.id == message.dropFirst(7) }) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { state.selectedTab = page.tab }
        }
    }

    private func group(_ group: [Page], gap: CGFloat, size: Binding<CGSize>) -> some View {
        ReactBitsWebView(page: .glassIcons, props: props(for: group, gap: gap), onMessage: { handle($0, size: size) })
            .frame(width: size.wrappedValue.width, height: size.wrappedValue.height)
            .frame(maxWidth: .infinity, alignment: .top)
    }

    var body: some View {
        VStack(spacing: 0) {
            // The Locken logo is drawn by the sidebar (`MainContentView.sidebarLogo`); this keeps its room.
            Color.clear
                .frame(width: 56, height: 56)
                .padding(.top, 38)
                .padding(.bottom, 14)

            // Leaves the page's own padding out of the spacing: the gap shrinks a little when there are more buttons.
            // The pages sit at the top; Settings and Admin are kept apart at the bottom.
            GeometryReader { geometry in
                let gap = max(18, min(30, (geometry.size.height - 60 - CGFloat(pages.count) * 40) / CGFloat(max(pages.count, 1))))
                VStack(spacing: 0) {
                    group(pages.filter { !Self.bottomIDs.contains($0.id) }, gap: gap, size: $railSize)
                    Spacer(minLength: 12)
                    group(pages.filter { Self.bottomIDs.contains($0.id) }, gap: gap, size: $bottomSize)
                }
            }

            // Room for the collapse button, which floats over the bottom of the rail.
            Color.clear.frame(height: 64)
        }
    }
}

// MARK: - Sidebar toggle icon

/// An SVG path made only of absolute M, H, V, C and Z commands, kept as numbers so two paths of the same shape can be
/// blended point by point (the sidebar icon's panel grows from narrow to wide).
private struct BlendablePath {
    enum Step {
        case move(CGPoint)
        case line(CGPoint)
        case curve(CGPoint, CGPoint, CGPoint)
        case close
    }

    let steps: [Step]

    init(_ d: String) {
        let spaced = d.map { "MHVCZ".contains($0) ? " \($0) " : String($0) }.joined()
        var steps: [Step] = []
        var current = CGPoint.zero
        var command: Character = "M"
        var numbers: [CGFloat] = []

        func flush() {
            switch command {
            case "M" where numbers.count >= 2:
                current = CGPoint(x: numbers[0], y: numbers[1]); steps.append(.move(current))
            case "H" where numbers.count >= 1:
                current.x = numbers[0]; steps.append(.line(current))
            case "V" where numbers.count >= 1:
                current.y = numbers[0]; steps.append(.line(current))
            case "C" where numbers.count >= 6:
                let c1 = CGPoint(x: numbers[0], y: numbers[1]), c2 = CGPoint(x: numbers[2], y: numbers[3])
                current = CGPoint(x: numbers[4], y: numbers[5]); steps.append(.curve(c1, c2, current))
            case "Z":
                steps.append(.close)
            default:
                break
            }
            numbers = []
        }

        for token in spaced.split(whereSeparator: { $0 == " " || $0 == "," }) {
            if token.count == 1, let letter = token.first, "MHVCZ".contains(letter) {
                flush()
                command = letter
            } else if let number = Double(token) {
                numbers.append(CGFloat(number))
            }
        }
        flush()
        self.steps = steps
    }

    /// This path blended toward `other` (0 is this one, 1 is `other`), scaled from the icon's 24-unit grid to `scale` points per unit.
    func path(toward other: BlendablePath, by t: CGFloat, scale: CGFloat) -> Path {
        guard steps.count == other.steps.count else { return Path() }
        func mix(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: (a.x + (b.x - a.x) * t) * scale, y: (a.y + (b.y - a.y) * t) * scale)
        }
        var path = Path()
        for (from, to) in zip(steps, other.steps) {
            switch (from, to) {
            case let (.move(a), .move(b)): path.move(to: mix(a, b))
            case let (.line(a), .line(b)): path.addLine(to: mix(a, b))
            case let (.curve(a1, a2, a3), .curve(b1, b2, b3)): path.addCurve(to: mix(a3, b3), control1: mix(a1, b1), control2: mix(a2, b2))
            case (.close, .close): path.closeSubpath()
            default: return Path()
            }
        }
        return path
    }
}

/// The sidebar button's icon: a rounded square with a panel cut out of its left side. `progress` 0 is the narrow panel
/// (sidebar closed), 1 the wide one (open); the shape blends between them as it animates.
private struct SidebarPanelShape: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    static let closed = BlendablePath("M10 5.5 C10 4.793 10 4.439 9.780 4.220 C9.560 4 9.207 4 8.5 4 H8.5 C6.379 4 5.318 4 4.659 4.659 C4 5.318 4 6.379 4 8.5 V15.5 C4 17.621 4 18.682 4.659 19.341 C5.318 20 6.379 20 8.5 20 H8.5 C9.207 20 9.561 20 9.780 19.780 C10 19.561 10 19.207 10 18.5 V5.5 Z")
    static let open = BlendablePath("M14 6 C14 5.057 14 4.586 13.707 4.293 C13.414 4 12.943 4 12 4 H10 C7.172 4 5.757 4 4.879 4.879 C4 5.757 4 7.172 4 10 V14 C4 16.828 4 18.243 4.879 19.121 C5.757 20 7.172 20 10 20 H12 C12.943 20 13.414 20 13.707 19.707 C14 19.414 14 18.943 14 18 V6 Z")

    func path(in rect: CGRect) -> Path {
        Self.closed.path(toward: Self.open, by: progress, scale: rect.width / 24)
    }
}

private struct SidebarOuterShape: Shape {
    static let outline = BlendablePath("M11 3 H13 C16.7712 3 18.6569 3 19.8284 4.17157 C21 5.34315 21 7.22876 21 11 V13 C21 16.7712 21 18.6569 19.8284 19.8284 C18.6569 21 16.7712 21 13 21 H11 C7.2288 21 5.3431 21 4.1716 19.8284 C3 18.6569 3 16.7712 3 13 V11 C3 7.22876 3 5.34315 4.1716 4.17157 C5.3431 3 7.2288 3 11 3 Z")

    func path(in rect: CGRect) -> Path {
        Self.outline.path(toward: Self.outline, by: 0, scale: rect.width / 24)
    }
}

/// The icon that collapses and expands the sidebar: the square takes the text colour and the panel is cut out of it in
/// the sidebar's own colour. Its panel morphs between narrow (collapsed) and wide (open) over 0.35 s, still with Reduce Motion.
private struct SidebarToggleIcon: View {
    let isOpen: Bool
    private let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    var body: some View {
        ZStack {
            SidebarOuterShape()
                .fill(.foreground)
            SidebarOuterShape()
                .stroke(.foreground, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            SidebarPanelShape(progress: isOpen ? 1 : 0)
                .fill(SquircleTokens.obsidianBase)
        }
        .animation(reduceMotion ? nil : .timingCurve(0.4, 0, 0.2, 1, duration: 0.35), value: isOpen)
        .accessibilityHidden(true)
    }
}

// MARK: - Reusable Sidebar Nav Item
private struct SidebarNavItem: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let accent: Color
    var liveText: String? = nil
    let pill: Namespace.ID
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.65))
                    .frame(width: 18)

                Text(title)
                    .font(.appFont(size: 13, weight: .semibold)) // semibold keeps navigation in Doto; selection shows in color
                    .foregroundColor(isSelected ? .white : .white.opacity(0.80))
                    .lineLimit(1)

                Spacer(minLength: 4)

                if let liveText {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(accent)
                            .frame(width: 6, height: 6)
                        Text(liveText)
                            .font(.appFont(size: 11, weight: .medium))
                            .monospacedDigit()
                            .foregroundColor(.white.opacity(0.65))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Session running, \(liveText) left")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                // One glass pill shared by every item, so it slides to the new selection.
                if isSelected {
                    GlassPill(cornerRadius: 10)
                        .matchedGeometryEffect(id: "sidebar-selection", in: pill)
                        .transaction { if reduceMotion { $0.animation = nil } }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Ghost Fibers Ambient Background (shared across every tab)
struct GhostFibersBackgroundView: View {
    // NOTE: these are plain full-alpha colors on purpose — opacity is applied
    // exactly once below via `.opacity(...)`. SwiftUI's Color.opacity(_:)
    // multiplies against whatever alpha the color already carries, so
    // starting from a color that already has its own baked-in opacity (as a
    // design token like `titaniumBorder` does) silently compounds down to a
    // near-invisible result — that was the earlier bug here.
    var lineColor: Color = .white
    var glowColor: Color = SquircleTokens.amberDashboard
    var layers: Int = 5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Inactive when Locken isn't the window in use; the fibers stop moving then, so a background Mac stays idle.
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        // The fibers drift slowly, so 20 frames a second looks the same as 60 at a third of the work.
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion || activeState == .inactive)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let paths = (0..<layers).map { fiberPath(index: $0, size: size, time: time) }
                let fades = (0..<layers).map { 0.5 + 0.5 * Double($0) / Double(max(layers - 1, 1)) }

                // One blurred layer for all the glows (blurring is the expensive part), then the crisp lines on top.
                context.drawLayer { glow in
                    glow.addFilter(.blur(radius: 8))
                    for (path, fade) in zip(paths, fades) {
                        glow.stroke(path, with: .color(glowColor.opacity(0.55 * fade)), lineWidth: 4)
                    }
                }
                for (path, fade) in zip(paths, fades) {
                    context.stroke(path, with: .color(lineColor.opacity(0.4 * fade)), lineWidth: 1.2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func fiberPath(index: Int, size: CGSize, time: TimeInterval) -> Path {
        var path = Path()
        let phase = Double(index) * 1.7
        let amplitude = size.height * 0.05
        let baseY = size.height * (0.15 + 0.65 * Double(index) / Double(max(layers - 1, 1)))

        var isFirst = true
        var x: CGFloat = 0
        while x <= size.width {
            let progress = Double(x / max(size.width, 1))
            let wave = sin(progress * 6.0 + time * 0.3 + phase) * amplitude
            let twist = sin(progress * 3.0 - time * 0.15 + phase) * (amplitude * 0.4)
            let y = baseY + wave + twist

            if isFirst {
                path.move(to: CGPoint(x: x, y: y))
                isFirst = false
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
            x += 10
        }
        return path
    }
}



/// Turns the purple logo into each tab's colour: a hue rotation from the logo's violet to the tab accent, and
/// less saturation for grey accents (Settings).
enum LogoTint {
    /// The logo art's own violet.
    private static let baseHue = 0.72

    static func rotation(for tab: String) -> Angle {
        let accent = NSColor(SquircleTokens.accentColor(for: tab)).usingColorSpace(.deviceRGB) ?? .systemPurple
        var delta = accent.hueComponent - baseHue
        if delta > 0.5 { delta -= 1 } else if delta < -0.5 { delta += 1 }
        return .degrees(delta * 360)
    }

    static func saturation(for tab: String) -> Double {
        let accent = NSColor(SquircleTokens.accentColor(for: tab)).usingColorSpace(.deviceRGB) ?? .systemPurple
        return min(1, max(0.15, accent.saturationComponent / 0.8))
    }
}
