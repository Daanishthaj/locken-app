//
//  GradualBlur.swift
//  LockenTestApp
//
//  Native port of React Bits' GradualBlur for scrolling pages: a band along the bottom edge where what scrolls under it
//  blurs more and more toward the edge, with a dark tint on top. It fades away on its own when there is nothing more
//  below to scroll to (the original's `autoHide`).
//
//  The original stacks CSS backdrop blurs with growing radii. Here one frosted-glass layer (a window `NSVisualEffectView`)
//  has its opacity ramped along the band with the original's exponential curve, so the page goes from sharp to frosted
//  gradually. The tint is the original's too: rgba(18, 15, 23, 0.6) under a quintic smoothstep.
//

import AppKit
import SwiftUI

struct GradualBlurEdge: View {
    var height: CGFloat = 96
    /// The page tile's bottom corner radius (24); 0 for a page that runs to the window's edge.
    var cornerRadius: CGFloat = 24
    /// 0...1: how much of the effect shows (the original's `--gradual-blur-reveal`).
    var reveal: Double = 1
    var tint = Color(red: 18 / 255, green: 15 / 255, blue: 23 / 255).opacity(0.6)
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// The original's "exponential" level, 0...1 along the band: slow at first, then quickly stronger.
    static func blurAmount(_ t: Double) -> Double { (pow(2, 4 * t) - 1) / 15 }

    /// The original's tint mask: a quintic smoothstep.
    static func tintAmount(_ t: Double) -> Double { t * t * t * (t * (t * 6 - 15) + 10) }

    var body: some View {
        ZStack {
            // Reduce Transparency: no frosted layer, only the dark fade.
            if !reduceTransparency {
                FrostedBand(amounts: (0...64).map { Self.blurAmount(Double($0) / 64) })
            }
            Rectangle()
                .fill(tint)
                .mask(LinearGradient(stops: (0...8).map { .init(color: .black.opacity(Self.tintAmount(Double($0) / 8)), location: Double($0) / 8) },
                                     startPoint: .top, endPoint: .bottom))
        }
        .frame(height: height)
        // The page tile has 24 pt corners; the band keeps them.
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: cornerRadius, bottomTrailingRadius: cornerRadius, style: .continuous))
        .opacity(reveal)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Frosted glass over what's behind it in the window, strongest at the bottom; `amounts` run from the top of the band to
/// the bottom. Mouse and scroll events pass through to the page.
private struct FrostedBand: NSViewRepresentable {
    let amounts: [Double]

    private final class PassThrough: NSVisualEffectView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = PassThrough()
        view.material = .hudWindow
        view.blendingMode = .withinWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        view.maskImage = mask()
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}

    /// A one-pixel-wide image whose opacity follows `amounts` (the image's bottom row is the band's bottom).
    private func mask() -> NSImage {
        let rows = amounts.count
        let image = NSImage(size: NSSize(width: 4, height: CGFloat(rows)), flipped: false) { _ in
            for row in 0..<rows {
                // Not flipped: row 0 is the bottom of the image, which is the last amount.
                NSColor.black.withAlphaComponent(CGFloat(amounts[rows - 1 - row])).setFill()
                NSRect(x: 0, y: CGFloat(row), width: 4, height: 1).fill()
            }
            return true
        }
        image.resizingMode = .stretch
        return image
    }
}

private struct GradualBlurScroll: ViewModifier {
    var height: CGFloat
    var cornerRadius: CGFloat
    /// How far the page can still scroll down.
    @State private var room: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                max(0, geometry.contentSize.height - geometry.visibleRect.maxY)
            } action: { _, newRoom in
                room = newRoom
            }
            .overlay(alignment: .bottom) {
                GradualBlurEdge(height: height, cornerRadius: cornerRadius, reveal: min(max(Double(room / height), 0), 1))
            }
    }
}

extension View {
    /// Adds the gradual blur along the bottom of a ScrollView: it shows while there is more to scroll to and fades away
    /// at the end.
    func gradualBlurBottom(height: CGFloat = 96, cornerRadius: CGFloat = 24) -> some View {
        modifier(GradualBlurScroll(height: height, cornerRadius: cornerRadius))
    }
}
