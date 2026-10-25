import AppKit
import SwiftUI

/// Right after every sign-in or sign-up, before any of the app is seen. The sign-up screen's violet
/// stays and the view pans down to a printer in the middle of the window, which prints a receipt for Locken that
/// totals $0.00 (the app is free), a line at a time.
/// The receipt tears off, the printer slides up out of frame, and the receipt falls from where it hung all the way
/// down and out the bottom (about 2.8 s), tipping until it lies flat while its edges and corners curl up from the
/// air, and the app fades in behind it. A click or any key skips it. With Reduce Motion the
/// printed receipt simply appears, holds briefly and fades.
struct ReceiptIntroView: View {
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var panned = false              // the printer has panned up into the middle of the window
    @State private var feed: CGFloat = 0           // 0 = inside the printer, 1 = fully printed
    @State private var isPrinting = true
    @State private var falling = false
    @State private var printerGone = false         // the printer slides up out of frame as the receipt falls
    @State private var fallLayerReady = false      // the falling copy is built before the tear, so the tear can't hitch
    @State private var receiptFrame: CGRect = .zero  // where the printed receipt hangs, so the fall starts exactly there
    @State private var fall: CGFloat = 0           // 0…1 progress of the fall
    @State private var backdrop: Double = 1
    @State private var snapshot: NSImage?
    @State private var sequence: Task<Void, Never>?
    @FocusState private var isFocused: Bool

    private static let space = "receiptIntro"
    static let paperWidth: CGFloat = 250
    static let paperHeight: CGFloat = 330
    // Stepped feed from the receipt-printer component: the paper advances, pauses, advances (10 steps).
    private static let feedSteps: [CGFloat] = [0.09, 0.19, 0.30, 0.42, 0.55, 0.68, 0.80, 0.90, 0.97, 1]

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            ZStack(alignment: .top) {
                Self.violetBackdrop.opacity(backdrop)

                printerScene(height: height)
                    .frame(width: geo.size.width, height: height)
                    .offset(y: panned ? 0 : height)
                    .opacity(falling ? backdrop : 1)

                if fallLayerReady, let snapshot {
                    FallingReceipt(image: snapshot, progress: fall, windowSize: geo.size, start: receiptFrame)
                        .frame(width: geo.size.width, height: height, alignment: .top)
                        .opacity(falling ? 1 : 0)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: geo.size.width, height: height, alignment: .top)
            .coordinateSpace(name: Self.space)
            .onPreferenceChange(ReceiptFrameKey.self) { receiptFrame = $0 }
            .clipped()
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: finish)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress { _ in finish(); return .handled }
        .onAppear {
            isFocused = true
            snapshot = Self.render(receipt)
            sequence = Task { await play() }
        }
        .onDisappear { sequence?.cancel() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("You're signed in. Your Locken receipt: total zero dollars. Locken is free.")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Activate to skip")
    }

    // MARK: Pages

    /// The printer, centered, with the paper coming out of its slot.
    private func printerScene(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            printer
                .offset(y: printerGone ? -height : 0)
                .zIndex(2)
            receipt
                .offset(y: -(1 - feed) * Self.paperHeight)
                .frame(width: Self.paperWidth, height: Self.paperHeight, alignment: .top)
                .clipped(antialiased: true)
                .background(GeometryReader { g in
                    Color.clear.preference(key: ReceiptFrameKey.self, value: g.frame(in: .named(Self.space)))
                })
                .opacity(falling ? 0 : 1)
                .padding(.top, -4)
                .zIndex(1)
            Spacer(minLength: 0)
        }
        .padding(.bottom, Self.paperHeight * 0.35)
        // Fill the whole window, so the backdrop and glow cover it edge to edge (not just the printer's width).
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // Locken's violet: the Focus page's backdrop with a soft glow behind the printer.
            ZStack {
                Self.violetBackdrop
                RadialGradient(colors: [SquircleTokens.logoViolet.opacity(0.22), .clear],
                               center: .center, startRadius: 0, endRadius: Self.paperHeight * 1.3)
            }
        }
    }

    /// The Focus page's violet-to-black backdrop.
    private static var violetBackdrop: LinearGradient {
        LinearGradient(colors: [SquircleTokens.bgTop(for: "focus"), SquircleTokens.bgBottom(for: "focus")],
                       startPoint: .top, endPoint: .bottom)
    }

    /// Receipt ink and paper in Locken's colors: deep violet ink on a pale lavender roll.
    private static let ink = Color(red: 0.22, green: 0.12, blue: 0.36)
    private static let paperTop = Color(red: 0.96, green: 0.94, blue: 1.0)
    private static let paperBottom = Color(red: 0.90, green: 0.87, blue: 0.97)

    private var printer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                LogoTraceLoader(loading: isPrinting, size: 16, strokeWidth: 9)
                    .foregroundColor(isPrinting ? .white.opacity(0.7) : SquircleTokens.royalPlum)
                Text(isPrinting ? "Printing your receipt" : "All set. It's on us.")
                    .font(.appFont(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.75))
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.18), value: isPrinting)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            Capsule()
                .fill(Color.black)
                .frame(width: Self.paperWidth + 22, height: 8)
                .overlay(Capsule().strokeBorder(SquircleTokens.logoViolet.opacity(0.35), lineWidth: 1))
                .shadow(color: SquircleTokens.logoViolet.opacity(0.5), radius: 6)
                .padding(.bottom, 12)
        }
        .frame(width: Self.paperWidth + 70)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.15, green: 0.11, blue: 0.23), Color(red: 0.08, green: 0.06, blue: 0.12)],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(LinearGradient(colors: [SquircleTokens.logoViolet.opacity(0.55), SquircleTokens.logoMagenta.opacity(0.25)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        )
        .shadow(color: SquircleTokens.logoViolet.opacity(0.35), radius: 30, y: 14)
    }

    // MARK: Receipt

    private var receipt: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("LOCKEN")
                .font(.appFont(size: 20, weight: .bold))
                .foregroundStyle(LinearGradient(colors: [SquircleTokens.logoViolet, SquircleTokens.logoMagenta],
                                                startPoint: .leading, endPoint: .trailing))
                .frame(maxWidth: .infinity, alignment: .center)
            Text("Focus app for students")
                .font(.appFont(size: 11))
                .frame(maxWidth: .infinity, alignment: .center)
                .opacity(0.7)
            dashedRule
            line("Focus sessions", "$0.00")
            line("Canvas sync", "$0.00")
            line("The Shield", "$0.00")
            line("Check-ins", "$0.00")
            line("Updates", "$0.00")
            dashedRule
            line("TOTAL", "$0.00", bold: true)
                .foregroundColor(SquircleTokens.logoViolet)
            Text("NOTHING TO PAY · NO CARD NEEDED")
                .font(.appFont(size: 11, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 2)
            Text("Thanks for focusing.")
                .font(.appFont(size: 11))
                .frame(maxWidth: .infinity, alignment: .center)
                .opacity(0.7)
        }
        .foregroundColor(Self.ink)
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 26)
        .frame(width: Self.paperWidth, height: Self.paperHeight, alignment: .top)
        .background(
            // Pale lavender with a faint fall of light, so the paper belongs to Locken's violet.
            LinearGradient(colors: [Self.paperTop, Self.paperBottom], startPoint: .top, endPoint: .bottom)
        )
        .clipShape(TornEdge())
    }

    private func line(_ label: String, _ price: String, bold: Bool = false) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(price)
        }
        .font(.appFont(size: bold ? 14 : 12, weight: bold ? .bold : .regular))
    }

    private var dashedRule: some View {
        Rectangle()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .frame(height: 1)
            .opacity(0.4)
    }

    @MainActor private static func render<V: View>(_ view: V) -> NSImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.nsImage
    }

    // MARK: Sequence

    private func play() async {
        if reduceMotion {
            panned = true
            feed = 1
            isPrinting = false
            try? await Task.sleep(for: .milliseconds(1600))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.45)) { backdrop = 0 }
            try? await Task.sleep(for: .milliseconds(480))
            guard !Task.isCancelled else { return }
            onFinished()
            return
        }
        // Pan down from the sign-up screen to the printer.
        withAnimation(.timingCurve(0.77, 0, 0.175, 1, duration: 1.0)) { panned = true }
        try? await Task.sleep(for: .milliseconds(1250))
        // Stepped feed: each step advances the paper, then it pauses for a beat, like a line being printed.
        for step in Self.feedSteps {
            guard !Task.isCancelled else { return }
            withAnimation(.linear(duration: 0.13)) { feed = step }
            try? await Task.sleep(for: .milliseconds(175))
        }
        guard !Task.isCancelled else { return }
        isPrinting = false
        fallLayerReady = true
        try? await Task.sleep(for: .milliseconds(800))
        guard !Task.isCancelled else { return }
        // Tear off: the printer slides up out of frame and the receipt falls the whole way down (about 2.8 s) while
        // the app fades in behind it. The fall's speed comes from FallingReceipt, so the clock runs linearly here.
        falling = true
        withAnimation(.timingCurve(0.77, 0, 0.175, 1, duration: 0.9)) { printerGone = true }
        withAnimation(.linear(duration: 2.8)) { fall = 1 }
        withAnimation(.easeInOut(duration: 1.8).delay(0.7)) { backdrop = 0 }
        try? await Task.sleep(for: .milliseconds(2850))
        guard !Task.isCancelled else { return }
        onFinished()
    }

    private func finish() {
        sequence?.cancel()
        onFinished()
    }
}

/// Where the printed receipt hangs, in the intro's coordinate space.
private struct ReceiptFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

/// The torn-off receipt falling. It starts exactly where it hung under the printer and drops the whole height of the
/// window, out the bottom, like paper: it starts still, speeds up, then air holds it near a steady speed, while it
/// drifts side to side, tips back until it lies flat, and its edges and corners curl up as the air catches them.
/// The curl is drawn by slicing the receipt into thin vertical strips and lifting and shading each one by how
/// far it sits from the middle (a cupped sheet seen from above), so no shader is needed.
private struct FallingReceipt: View, Animatable {
    let image: NSImage
    var progress: CGFloat
    let windowSize: CGSize
    let start: CGRect

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    /// Margin above and below the paper inside the canvas, so the curled edges have room.
    private static let margin: CGFloat = 40

    /// Distance fallen (0…1) at time t (0…1): falling with air drag, y ∝ ln(cosh(t/τ)). Starts at zero speed, so
    /// the tear doesn't jerk, and settles to a near-steady speed instead of accelerating forever.
    static func drop(_ t: CGFloat) -> CGFloat {
        let tau: CGFloat = 0.32
        return log(cosh(t / tau)) / log(cosh(1 / tau))
    }

    var body: some View {
        let w = ReceiptIntroView.paperWidth
        let h = ReceiptIntroView.paperHeight
        let p = progress
        // Tips toward flat over the first 60% of the fall; curls from 25% on. Sway and spin ease in, so the first
        // frames match the hanging receipt exactly.
        let tilt = min(1, p / 0.6)
        let curl = max(0, min(1, (p - 0.25) / 0.6))
        let easeIn = min(1, p / 0.25)
        let sway = sin(p * .pi * 2.2) * easeIn
        let startY = (start == .zero ? windowSize.height / 2 - h / 2 : start.minY) - Self.margin
        let endY = windowSize.height + Self.margin
        let startX = start == .zero ? 0 : start.midX - windowSize.width / 2
        Canvas { context, size in
            let strips = 40
            let flatten = 1 - 0.62 * tilt * tilt          // foreshortening as it lies down
            let stripWidth = size.width / CGFloat(strips)
            let swiftImage = Image(nsImage: image)
            for index in 0..<strips {
                let u = (CGFloat(index) + 0.5) / CGFloat(strips) * 2 - 1    // -1 … 1 across the width
                let lift = curl * u * u * 34                             // edges rise
                let squeeze = 1 - curl * u * u * 0.12                    // and foreshorten a little more
                let rect = CGRect(x: CGFloat(index) * stripWidth, y: 0, width: stripWidth + 0.6, height: size.height)
                context.drawLayer { layer in
                    layer.clip(to: Path(rect))
                    let drawnHeight = h * flatten * squeeze
                    // Lies down around its top edge first, so the top stays where it tore off at the start.
                    let top = Self.margin + (h - drawnHeight) * tilt * 0.5 - lift
                    layer.draw(swiftImage, in: CGRect(x: 0, y: top, width: w, height: drawnHeight))
                    // Raised edges catch the light; the sagging middle is a touch darker.
                    let shade = 0.1 * curl * (1 - u * u) - 0.08 * curl * u * u
                    let color = shade > 0 ? Color.black.opacity(Double(shade)) : Color.white.opacity(Double(-shade))
                    layer.fill(Path(CGRect(x: rect.minX, y: top, width: rect.width, height: drawnHeight)), with: .color(color))
                }
            }
        }
        .frame(width: w, height: h + Self.margin * 2)
        .shadow(color: .black.opacity(0.3 * Double(easeIn) * Double(1 - tilt * 0.5)), radius: 14 + 10 * tilt, y: 10 + 16 * tilt)
        .rotationEffect(.degrees(Double(sway) * 9 * Double(1 - p * 0.5) + Double(p * easeIn) * 6))
        .offset(x: startX + sway * 46, y: startY + Self.drop(p) * (endY - startY))
    }
}

/// A receipt's torn bottom edge: small zig-zag teeth along the bottom.
private struct TornEdge: Shape {
    var teeth = 24
    var depth: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - depth))
        let step = rect.width / CGFloat(teeth * 2)
        for i in 1...(teeth * 2) {
            let x = rect.maxX - CGFloat(i) * step
            let y = i % 2 == 1 ? rect.maxY : rect.maxY - depth
            p.addLine(to: CGPoint(x: x, y: y))
        }
        p.closeSubpath()
        return p
    }
}
