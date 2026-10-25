import AppKit
import SwiftUI

/// Locken's loading indicator: a short stroke traces the padlock logo while work is in progress, then the outline
/// closes and the filled padlock fades in. Drawn in the current foreground color, at a fixed size so nothing shifts.
/// Reduce Motion shows the filled logo straight away.
///
/// The logo geometry is the Locken padlock glyph from `web/assets/locken-logo.svg` (viewBox 0 0 100 100).
struct LogoTraceLoader: View {
    var loading: Bool = true
    var size: CGFloat = 28
    var strokeWidth: CGFloat = 7
    var loopDurationSeconds: Double = 1.4
    var fillFadeSeconds: Double = 0.35
    var ariaLabel: String = "Loading"
    var onDone: (() -> Void)?

    private enum Phase { case loop, closingOutline, fadingFill, done }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Phase = .loop
    @State private var closeProgress: CGFloat = 0
    @State private var fillOpacity: Double = 0
    @State private var didFinish = false

    var body: some View {
        let scale = size / 100
        ZStack {
            // Faint full outline underneath, so the trace reads as "going around the logo".
            LockenLogo.tracePath
                .stroke(style: StrokeStyle(lineWidth: max(1, strokeWidth / 2), lineJoin: .round))
                .opacity(0.18)

            if phase == .loop && !reduceMotion {
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let head = CGFloat((t / loopDurationSeconds).truncatingRemainder(dividingBy: 1))
                    TraceSegment(start: head, length: 0.16, lineWidth: strokeWidth)
                }
            }

            if phase == .closingOutline || phase == .fadingFill {
                LockenLogo.tracePath
                    .trim(from: 0, to: closeProgress)
                    .stroke(style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round))
            }

            if phase == .fadingFill || phase == .done {
                ZStack {
                    LockenLogo.shackle
                    LockenLogo.body.fill(style: FillStyle(eoFill: true))
                }
                .opacity(fillOpacity)
            }
        }
        .frame(width: 100, height: 100)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: size, height: size, alignment: .topLeading)
        .accessibilityElement()
        .accessibilityLabel(ariaLabel)
        .accessibilityAddTraits(.updatesFrequently)
        .onAppear {
            if reduceMotion { showFilledNow() } else if !loading { finish() }
        }
        .onChange(of: loading) { _, isLoading in
            if !isLoading { finish() }
        }
    }

    /// The loop resolves: close the outline, then fade in the filled padlock. Timers back up the animations so
    /// `onDone` is never left waiting, and it's called exactly once.
    private func finish() {
        guard phase == .loop else { return }
        if reduceMotion { showFilledNow(); return }
        phase = .closingOutline
        withAnimation(.easeInOut(duration: 0.45)) { closeProgress = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            phase = .fadingFill
            withAnimation(.easeOut(duration: fillFadeSeconds)) { fillOpacity = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + fillFadeSeconds) {
                phase = .done
                callDone()
            }
        }
    }

    private func showFilledNow() {
        phase = .done
        fillOpacity = 1
        callDone()
    }

    private func callDone() {
        guard !didFinish else { return }
        didFinish = true
        onDone?()
    }
}

/// A stroke segment `length` long (as a fraction of the path) starting at `start`, wrapping past the end.
private struct TraceSegment: View {
    let start: CGFloat
    let length: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        let end = start + length
        ZStack {
            LockenLogo.tracePath.trim(from: start, to: min(end, 1)).stroke(style: style)
            if end > 1 {
                LockenLogo.tracePath.trim(from: 0, to: end - 1).stroke(style: style)
            }
        }
    }
}

/// The Locken padlock in a 100 × 100 box.
enum LockenLogo {
    /// One continuous, closed route around the logo: up the left shackle leg, over and down the right leg, then
    /// around the body. The legs (x = 33 and 67) meet the body on its rounded top corners, so the route follows
    /// those corners from exactly where the legs land; no part of the line doubles back.
    static let tracePath: Path = {
        let radius: CGFloat = 13
        // Where a leg at x meets the top corner circle centered at (cx, 56).
        func corner(_ x: CGFloat, _ cx: CGFloat) -> CGFloat { 56 - sqrt(radius * radius - (x - cx) * (x - cx)) }
        func arc(_ p: inout Path, cx: CGFloat, cy: CGFloat, from a0: CGFloat, to a1: CGFloat) {
            let steps = 14
            for i in 1...steps {
                let a = a0 + (a1 - a0) * CGFloat(i) / CGFloat(steps)
                p.addLine(to: CGPoint(x: cx + radius * cos(a), y: cy + radius * sin(a)))
            }
        }
        let leftY = corner(33, 36)
        let rightY = corner(67, 64)
        var p = Path()
        p.move(to: CGPoint(x: 33, y: leftY))
        p.addLine(to: CGPoint(x: 33, y: 32))
        p.addCurve(to: CGPoint(x: 50, y: 15), control1: CGPoint(x: 33, y: 22.5), control2: CGPoint(x: 40.5, y: 15))
        p.addCurve(to: CGPoint(x: 67, y: 32), control1: CGPoint(x: 59.5, y: 15), control2: CGPoint(x: 67, y: 22.5))
        p.addLine(to: CGPoint(x: 67, y: rightY))
        arc(&p, cx: 64, cy: 56, from: atan2(rightY - 56, 3), to: 0)              // top-right corner
        p.addLine(to: CGPoint(x: 77, y: 72))
        arc(&p, cx: 64, cy: 72, from: 0, to: .pi / 2)                             // bottom-right
        p.addLine(to: CGPoint(x: 36, y: 85))
        arc(&p, cx: 36, cy: 72, from: .pi / 2, to: .pi)                           // bottom-left
        p.addLine(to: CGPoint(x: 23, y: 56))
        arc(&p, cx: 36, cy: 56, from: .pi, to: 2 * .pi + atan2(leftY - 56, -3))   // top-left
        p.closeSubpath()
        return p
    }()

    /// The filled shackle (filled on its own so its legs don't cut holes where they meet the body).
    static let shackle: Path = {
        let line = Path { s in
            s.move(to: CGPoint(x: 33, y: 45))
            s.addLine(to: CGPoint(x: 33, y: 32))
            s.addCurve(to: CGPoint(x: 50, y: 15), control1: CGPoint(x: 33, y: 22.5), control2: CGPoint(x: 40.5, y: 15))
            s.addCurve(to: CGPoint(x: 67, y: 32), control1: CGPoint(x: 59.5, y: 15), control2: CGPoint(x: 67, y: 22.5))
            s.addLine(to: CGPoint(x: 67, y: 45))
        }
        return line.strokedPath(StrokeStyle(lineWidth: 7.5, lineCap: .round))
    }()

    /// The body with the keyhole cut out; fill it with the even-odd rule.
    static let body: Path = {
        var body = Path(roundedRect: CGRect(x: 23, y: 43, width: 54, height: 42), cornerRadius: 13)
        body.addEllipse(in: CGRect(x: 45.5, y: 54.5, width: 9, height: 9))
        body.move(to: CGPoint(x: 47.8, y: 61))
        body.addLine(to: CGPoint(x: 46.5, y: 71))
        body.addQuadCurve(to: CGPoint(x: 48, y: 72.5), control: CGPoint(x: 46.5, y: 72.5))
        body.addLine(to: CGPoint(x: 52, y: 72.5))
        body.addQuadCurve(to: CGPoint(x: 53.5, y: 71), control: CGPoint(x: 53.5, y: 72.5))
        body.addLine(to: CGPoint(x: 52.2, y: 61))
        body.closeSubpath()
        return body
    }()
}

extension LockenLogo {
    /// A squared-off padlock for the menu bar: a flat-topped shackle with tight corners and a body with small corner
    /// radii, so it reads crisp and precise at 18 pt.
    static let squareShackle: Path = {
        let line = Path { s in
            s.move(to: CGPoint(x: 33, y: 45))
            s.addLine(to: CGPoint(x: 33, y: 22))
            s.addQuadCurve(to: CGPoint(x: 39, y: 16), control: CGPoint(x: 33, y: 16))
            s.addLine(to: CGPoint(x: 61, y: 16))
            s.addQuadCurve(to: CGPoint(x: 67, y: 22), control: CGPoint(x: 67, y: 16))
            s.addLine(to: CGPoint(x: 67, y: 45))
        }
        return line.strokedPath(StrokeStyle(lineWidth: 8, lineCap: .butt, lineJoin: .miter))
    }()

    static let squareBody: Path = {
        var body = Path(roundedRect: CGRect(x: 21, y: 43, width: 58, height: 42), cornerRadius: 4)
        body.addRect(CGRect(x: 46.5, y: 55, width: 7, height: 17))
        return body
    }()

    /// The padlock as a menu bar template image (black on clear; macOS tints it for light and dark menu bars).
    /// `open` lifts the shackle, for a paused session.
    static func menuBarImage(open: Bool) -> NSImage {
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let s = rect.width / 100
            context.scaleBy(x: s, y: s)
            context.setFillColor(NSColor.black.cgColor)
            context.saveGState()
            if open { context.translateBy(x: 0, y: -9) }
            context.addPath(squareShackle.cgPath)
            context.fillPath()
            context.restoreGState()
            context.addPath(squareBody.cgPath)
            context.fillPath(using: .evenOdd)
            return true
        }
        image.isTemplate = true
        return image
    }
}
