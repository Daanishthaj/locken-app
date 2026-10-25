import AppKit
import CoreText
import SwiftUI

/// Writes text on screen like a signature: the outline of each letter is drawn stroke by stroke in Snell
/// Roundhand (the app's script face), left to right, then the letters fill in. It plays once per account per
/// launch (after signing in); later appearances show the finished name. Reduce Motion shows it straight away.
/// Timing follows the animated-signature component: 2.8 s, cubic-bezier(0.2, 0.2, 0.8, 0.9).
struct SignatureText: View {
    let text: String
    var size: CGFloat = 30
    var duration: Double = 2.8
    var delay: Double = 0
    /// Plays the writing animation once per key (for example the signed-in account) until the app quits.
    var playKey: String
    /// Holds the writing back while the startup reveal or the sign-in welcome covers the app, so it's seen being written.
    var waitsForIntro = false

    private static var played = Set<String>()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    @State private var fillOpacity: Double = 0
    @ObservedObject private var cover = IntroCover.shared

    var body: some View {
        let glyphs = SignatureGlyphs.make(text, size: size)
        ZStack(alignment: .topLeading) {
            glyphs.path
                .trim(from: 0, to: progress)
                .stroke(style: StrokeStyle(lineWidth: max(0.8, size * 0.035), lineCap: .round, lineJoin: .round))
            glyphs.path
                .fill()
                .opacity(fillOpacity)
        }
        .frame(width: glyphs.size.width, height: glyphs.size.height)
        .accessibilityElement()
        .accessibilityLabel(text)
        .onAppear(perform: start)
        .onChange(of: text) { _, _ in start() }
        // The intro just ended: start now, unless it already started.
        .onChange(of: cover.isActive) { _, active in if !active, waitsForIntro, progress == 0 { start() } }
    }

    private func start() {
        let key = playKey + "|" + text
        guard !reduceMotion, !Self.played.contains(key) else {
            progress = 1
            fillOpacity = 1
            return
        }
        // Under the intro nothing is drawn yet; the writing starts when it clears.
        if waitsForIntro, cover.isActive {
            progress = 0
            fillOpacity = 0
            return
        }
        Self.played.insert(key)
        progress = 0
        fillOpacity = 0
        withAnimation(.timingCurve(0.2, 0.2, 0.8, 0.9, duration: duration).delay(delay)) { progress = 1 }
        withAnimation(.easeOut(duration: 0.5).delay(delay + duration * 0.8)) { fillOpacity = 1 }
    }
}

/// The text's glyph outlines as one path (glyphs in reading order), flipped into SwiftUI's coordinates and
/// moved to the origin, plus the size it needs.
private enum SignatureGlyphs {
    private static var cache: [String: (path: Path, size: CGSize)] = [:]

    static func make(_ text: String, size: CGFloat) -> (path: Path, size: CGSize) {
        let key = "\(size)|\(text)"
        if let cached = cache[key] { return cached }
        let name = NSFont(name: "SnellRoundhand-Bold", size: size) != nil ? "SnellRoundhand-Bold" : "Snell Roundhand"
        let font = CTFontCreateWithName(name as CFString, size, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        let outline = CGMutablePath()
        for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let runFont = attributes[kCTFontAttributeName] as! CTFont // swiftlint:disable:this force_cast
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            for index in 0..<count {
                guard let glyph = CTFontCreatePathForGlyph(runFont, glyphs[index], nil) else { continue }
                outline.addPath(glyph, transform: CGAffineTransform(translationX: positions[index].x, y: positions[index].y))
            }
        }
        // Core Text draws upward from the baseline; flip it and move the drawing to the top-left with a little room.
        let box = outline.boundingBoxOfPath
        let padding = max(2, size * 0.08)
        var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: padding - box.minX, ty: box.maxY + padding)
        let flipped = outline.copy(using: &transform) ?? outline
        let result = (Path(flipped), CGSize(width: ceil(box.width + padding * 2), height: ceil(box.height + padding * 2)))
        cache[key] = result
        return result
    }
}
