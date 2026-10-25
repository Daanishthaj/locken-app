import AppKit
import SwiftUI

/// A borderless, transparent panel that floats above every window (including full-screen apps) and can
/// take keyboard focus without activating Locken, the way Spotlight does. Borderless windows refuse key
/// status by default, so `canBecomeKey` is overridden; `constrainFrameRect` is overridden so macOS doesn't
/// push the window below the menu bar, which lets it sit flush against the notch.
final class CheckInPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        // The prompt draws its own shadow inside the panel, so it follows the notch shape as it grows.
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    /// Escape doesn't dismiss: the prompt stays until a status is submitted.
    override func cancelOperation(_ sender: Any?) {}
}

/// The aurora's window: the same kind of floating, borderless panel as the prompt, but it never takes the keyboard or
/// the mouse, so the check-in and everything under the glow stay usable.
final class CheckInAuroraPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isFloatingPanel = true
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Whether the prompt is grown out of the notch or tucked back into it. The view animates the change.
@MainActor
final class CheckInPromptModel: ObservableObject {
    @Published var isOpen = false
}

/// Drops a check-in prompt down from the notch during an active session, asks how far into the session's
/// goal the user is (a slider, not typing), and tucks it back into the notch once submitted.
///
/// Timing follows the session's own clock (`sessionTick`, called every second the countdown runs), so
/// pauses, Mac sleep and restarted sessions can't push a check-in off schedule: every 30 minutes, or once
/// at the halfway point when the whole session is 30 minutes or shorter.
@MainActor
final class CheckInWindowManager: ObservableObject {
    static let shared = CheckInWindowManager()

    struct CheckIn: Identifiable, Equatable {
        let id = UUID()
        let date: Date
        /// How far into the goal, 0–100 %.
        let progress: Int
    }

    static let checkInInterval = 30 * 60

    /// Room around the black shape for its shadow.
    static let shadowMargin = CGSize(width: 28, height: 36)
    static let shapeWidth: CGFloat = 440
    /// Height of the prompt's content below the notch.
    static let contentHeight: CGFloat = 168
    /// How far down the screen the aurora's glow reaches.
    static let auroraHeight: CGFloat = 380

    @Published private(set) var isSessionActive = false
    @Published private(set) var isPresented = false
    @Published private(set) var history: [CheckIn] = []

    private var panel: CheckInPanel?
    private var auroraPanel: CheckInAuroraPanel?
    private let promptModel = CheckInPromptModel()
    private var screenObserver: NSObjectProtocol?

    private init() {}

    // MARK: Session hooks

    func startSession() {
        isSessionActive = true
        history = []
    }

    /// Where the slider starts: the last answer this session, or 0.
    var lastProgress: Int { history.last?.progress ?? 0 }

    func endSession() {
        isSessionActive = false
        dismiss(animated: true)
    }

    /// Call once per second while the session countdown runs. Shows the prompt when `elapsedSeconds`
    /// reaches one of the session's check-in points.
    func sessionTick(elapsedSeconds: Int, totalSeconds: Int) {
        guard isSessionActive, Self.checkInPoints(totalSeconds: totalSeconds).contains(elapsedSeconds) else { return }
        present()
    }

    /// Seconds into a session at which to check in: every 30 minutes, or once at the halfway point when the
    /// session is 30 minutes or shorter (a 30-minute cadence would never land inside it; a 30-minute session's
    /// only mark would be its last second). A mark on the final second is dropped since the session is ending.
    static func checkInPoints(totalSeconds: Int) -> [Int] {
        guard totalSeconds > 1 else { return [] }
        if totalSeconds <= checkInInterval { return [totalSeconds / 2] }
        return Array(stride(from: checkInInterval, to: totalSeconds, by: checkInInterval))
    }

    /// Shows the prompt now, for a manual check-in.
    func presentNow() {
        present()
    }

    // MARK: Presentation

    private func present() {
        guard !isPresented, let screen = NSScreen.main else { return }
        let metrics = Self.notchMetrics(on: screen)
        let size = Self.panelSize(notchHeight: metrics.height)
        let panel = self.panel ?? CheckInPanel(contentRect: NSRect(origin: .zero, size: size))
        self.panel = panel
        // Fresh content each time: tucked into the notch, with the slider at the last answer.
        promptModel.isOpen = false
        installPrompt(in: panel, size: size, notch: metrics)

        panel.setFrame(Self.anchoredFrame(size: size, on: screen), display: false)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        // Key without activating Locken, so whatever app is in front stays in front.
        panel.makeKey()
        installAurora(on: screen, below: panel)
        isPresented = true

        // Next runloop turn, once the view is on screen, so SwiftUI animates the shape growing out of the notch.
        DispatchQueue.main.async { [promptModel] in
            promptModel.isOpen = true
        }

        // Follow display changes (notch screen unplugged, resolution change) while visible.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel, self.isPresented, let screen = NSScreen.main else { return }
                let metrics = Self.notchMetrics(on: screen)
                let size = Self.panelSize(notchHeight: metrics.height)
                self.installPrompt(in: panel, size: size, notch: metrics)
                panel.setFrame(Self.anchoredFrame(size: size, on: screen), display: true)
                self.auroraPanel?.setFrame(Self.auroraFrame(on: screen), display: true)
            }
        }
    }

    private func dismiss(animated: Bool) {
        guard isPresented, let panel else { return }
        isPresented = false
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil

        guard animated else {
            promptModel.isOpen = false
            panel.orderOut(nil)
            auroraPanel?.orderOut(nil)
            return
        }
        // Shrink back into the notch (and let the aurora fade), then remove the windows once that has finished.
        promptModel.isOpen = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            if !self.isPresented {
                panel.orderOut(nil)
                self.auroraPanel?.orderOut(nil)
            }
        }
    }

    private func submit(progress: Int) {
        let answer = min(max(progress, 0), 100)
        history.append(CheckIn(date: Date(), progress: answer))
        TestAppStateManager.shared.applyCheckIn(progress: answer)
        dismiss(animated: true)
    }

    /// The aurora spans the top of the screen, just under the prompt in the window stack.
    private func installAurora(on screen: NSScreen, below panel: CheckInPanel) {
        let frame = Self.auroraFrame(on: screen)
        let aurora = auroraPanel ?? CheckInAuroraPanel(contentRect: frame)
        auroraPanel = aurora
        let hosting = NSHostingController(rootView: CheckInAuroraView(model: promptModel))
        hosting.sizingOptions = []
        hosting.view.frame = NSRect(origin: .zero, size: frame.size)
        hosting.view.autoresizingMask = [.width, .height]
        aurora.contentViewController = hosting
        aurora.setFrame(frame, display: false)
        aurora.alphaValue = 1
        aurora.orderFrontRegardless()
        aurora.order(.below, relativeTo: panel.windowNumber)
    }

    private func installPrompt(in panel: CheckInPanel, size: CGSize, notch: (width: CGFloat, height: CGFloat)) {
        let hosting = NSHostingController(rootView: CheckInPromptView(
            model: promptModel,
            notchWidth: notch.width,
            notchHeight: notch.height,
            initialProgress: lastProgress
        ) { [weak self] progress in
            self?.submit(progress: progress)
        })
        hosting.sizingOptions = []
        hosting.view.frame = NSRect(origin: .zero, size: size)
        hosting.view.autoresizingMask = [.width, .height]
        panel.contentViewController = hosting
    }

    // MARK: Geometry

    static func panelSize(notchHeight: CGFloat) -> CGSize {
        CGSize(
            width: shapeWidth + shadowMargin.width * 2,
            height: notchHeight + contentHeight + shadowMargin.height
        )
    }

    /// The aurora's frame: the whole width of the screen, flush with its top edge.
    static func auroraFrame(on screen: NSScreen) -> NSRect {
        let frame = screen.frame
        return NSRect(x: frame.minX, y: frame.maxY - auroraHeight, width: frame.width, height: auroraHeight)
    }

    /// The hardware notch's size. Displays without one use the menu bar's height and a notch-like width,
    /// so the prompt still grows out of the top centre of the screen.
    static func notchMetrics(on screen: NSScreen) -> (width: CGFloat, height: CGFloat) {
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea, screen.safeAreaInsets.top > 0 {
            return (max(120, right.minX - left.maxX), screen.safeAreaInsets.top)
        }
        return (180, NSStatusBar.system.thickness)
    }

    /// The panel's frame, top edge flush with the top of the screen and centred on the notch.
    /// On notched displays the notch sits between `auxiliaryTopLeftArea` and `auxiliaryTopRightArea`;
    /// other displays use the screen's horizontal centre.
    static func anchoredFrame(size: CGSize, on screen: NSScreen) -> NSRect {
        let frame = screen.frame
        var centerX = frame.midX
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            centerX = frame.minX + (left.maxX + right.minX) / 2
        }
        return NSRect(x: (centerX - size.width / 2).rounded(), y: frame.maxY - size.height, width: size.width, height: size.height)
    }
}

/// A soft, calm aurora along the top of the screen while the check-in is open: indigo, blue, cyan and green glows that
/// drift slowly and lean a little toward the pointer, fading to nothing a third of the way down. It fades in with the
/// prompt and out as it tucks away; with Reduce Motion on it holds still.
struct CheckInAuroraView: View {
    @ObservedObject var model: CheckInPromptModel
    private let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    /// Left to right across the screen: where each glow sits (a fraction of the width), its colour and its drift offset.
    private static let glows: [(x: Double, color: Color, phase: Double)] = [
        (0.03, Color(red: 0.30, green: 0.20, blue: 1.00), 0.0),
        (0.19, Color(red: 0.25, green: 0.55, blue: 1.00), 1.4),
        (0.35, Color(red: 0.30, green: 0.85, blue: 0.80), 2.6),
        (0.51, Color(red: 0.55, green: 1.00, blue: 0.45), 3.9),
        (0.67, Color(red: 0.35, green: 0.80, blue: 0.85), 5.1),
        (0.83, Color(red: 0.25, green: 0.50, blue: 1.00), 0.7),
        (0.98, Color(red: 0.32, green: 0.18, blue: 0.90), 2.0),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                context.addFilter(.blur(radius: 64))
                let screen = NSScreen.main?.frame ?? .zero
                // 0…1 across the screen; the glows lean a little toward it.
                let pointer = screen.width > 0 ? min(max((NSEvent.mouseLocation.x - screen.minX) / screen.width, 0), 1) : 0.5
                for glow in Self.glows {
                    let drift = reduceMotion ? 0 : sin(time * 0.32 + glow.phase)
                    let lean = reduceMotion ? 0 : (pointer - glow.x) * 0.07
                    let centerX = (glow.x + lean) * size.width + drift * size.width * 0.035
                    let centerY = size.height * 0.04 + (reduceMotion ? 0 : cos(time * 0.27 + glow.phase) * 14)
                    let radiusX = size.width * 0.15
                    let radiusY = size.height * 0.46
                    let rect = CGRect(x: centerX - radiusX, y: centerY - radiusY, width: radiusX * 2, height: radiusY * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(glow.color.opacity(0.85)))
                }
            }
        }
        // Full strength at the very top, gone before the bottom, so no edge shows.
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.3), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
        .opacity(model.isOpen ? 0.9 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: model.isOpen ? 0.7 : 0.45), value: model.isOpen)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The notch silhouette: concave "ears" where it meets the top of the screen, rounded corners at the bottom.
/// Both radii animate, so the shape can grow out of the hardware notch.
struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = topCornerRadius
        let bottom = bottomCornerRadius
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top, y: rect.minY + top), control: CGPoint(x: rect.minX + top, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY), control: CGPoint(x: rect.minX + top, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom), control: CGPoint(x: rect.maxX - top, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - top, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// The check-in prompt: a black shape that grows out of the notch, then shows the question, the session's
/// goal and time left, a slider for how far into the goal the user is (← → move it by 5 %), and a Check In
/// button (Return works too).
struct CheckInPromptView: View {
    @ObservedObject var model: CheckInPromptModel
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let initialProgress: Int
    let onSubmit: (Int) -> Void

    @ObservedObject private var state = TestAppStateManager.shared
    @State private var progress: Double = 0
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let earRadius: CGFloat = 14
    private var accent: Color { SquircleTokens.accentColor(for: "focus") }

    var body: some View {
        let open = model.isOpen
        let margin = CheckInWindowManager.shadowMargin
        GeometryReader { geo in
            let shapeWidth = geo.size.width - margin.width * 2
            let shapeHeight = geo.size.height - margin.height

            ZStack(alignment: .top) {
                NotchShape(topCornerRadius: open ? earRadius : 6, bottomCornerRadius: open ? 26 : 10)
                    .fill(Color.black)
                    .frame(width: open ? shapeWidth : notchWidth + 12, height: open ? shapeHeight : notchHeight)
                    .shadow(color: .black.opacity(open ? 0.45 : 0), radius: 22, y: 12)
                    .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.8), value: open)

                content
                    .padding(.top, notchHeight + 12)
                    .padding(.horizontal, earRadius + 20)
                    .padding(.bottom, 20)
                    .frame(width: shapeWidth, height: shapeHeight, alignment: .top)
                    .opacity(open ? 1 : 0)
                    .offset(y: open || reduceMotion ? 0 : -8)
                    // In just after the shape starts growing; out right away when closing.
                    .animation(open ? .easeOut(duration: 0.22).delay(reduceMotion ? 0 : 0.12) : .easeOut(duration: 0.12), value: open)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .environment(\.colorScheme, .dark)
        .onAppear {
            progress = Double(initialProgress)
            // Next runloop turn, once the panel is key, so the arrow keys reach the prompt.
            DispatchQueue.main.async { isFocused = true }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image("LockenLogo")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .accessibilityHidden(true)
                Text("Check-in")
                    .font(.appFont(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                if state.isTimerActive {
                    HStack(spacing: 6) {
                        Circle().fill(accent).frame(width: 6, height: 6)
                        Text(String(format: "%d:%02d left", state.timerSecondsRemaining / 60, state.timerSecondsRemaining % 60))
                            .font(.appFont(size: 12, weight: .medium))
                            .monospacedDigit()
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("How far into your goal are you?")
                    .font(.appFont(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                if !state.focusGoal.isEmpty {
                    Text("Goal: \(state.focusGoal)")
                        .font(.appFont(size: 12))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            HStack(spacing: 12) {
                Slider(value: $progress, in: 0...100, step: 5)
                    .tint(accent)
                    .accessibilityLabel("How far into your goal")
                    .accessibilityValue("\(Int(progress)) percent")

                Text("\(Int(progress))%")
                    .font(.appFont(size: 15, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .frame(width: 48, alignment: .trailing)
                    .contentTransition(.numericText(value: progress))
                    .accessibilityHidden(true)

                Button(action: submit) {
                    Text("Check In")
                        .font(.appFont(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(accent))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }

            // Adaptive time: what this answer will do to the timer, before it's sent.
            if state.isAdaptiveTimeOn {
                Text(adaptivePreview)
                    .font(.appFont(size: 11))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(.leftArrow) { progress = max(progress - 5, 0); return .handled }
        .onKeyPress(.rightArrow) { progress = min(progress + 5, 100); return .handled }
    }

    private var adaptivePreview: String {
        let elapsed = state.timerTotalSeconds - state.timerSecondsRemaining
        guard let remaining = TestAppStateManager.adaptedRemaining(
            elapsed: elapsed, remaining: state.timerSecondsRemaining, planned: state.plannedTotalSeconds, progress: Int(progress)
        ) else { return "Adaptive time: move the slider to adjust the time left." }
        return remaining == 0 ? "Adaptive time: checking in at 100% ends the session."
            : "Adaptive time: \(remaining / 60) min left after this check-in."
    }

    private func submit() {
        onSubmit(Int(progress))
    }
}
