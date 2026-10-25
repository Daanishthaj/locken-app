import SwiftUI

// MARK: - MagicBento border glow (React Bits), ported natively
//
// React Bits' MagicBento renders its own demo grid, so it can't hold the app's live SwiftUI cards. Only its
// border glow is ported onto the existing cards: a 6pt border ring lit by a 300pt radial gradient centred on
// the pointer, full strength within 150pt of a card and fading out by 225pt (spotlightRadius 300), in the
// current tab's accent color. The other hover effects (stars, spotlight, tilt, magnetism, click ripple) are
// left out on purpose; nothing moves or appears on hover.

enum MagicBento {
    static let spotlightRadius: CGFloat = 300
    static let coordinateSpace = "magicBento"

    private static let proximity = spotlightRadius * 0.5
    private static let fadeDistance = spotlightRadius * 0.75

    /// MagicBento's falloff: full strength within `proximity` of a card's edge, fading out by `fadeDistance`.
    static func intensity(pointer: CGPoint, frame: CGRect) -> Double {
        let distance = hypot(pointer.x - frame.midX, pointer.y - frame.midY) - max(frame.width, frame.height) / 2
        let effective = max(0, distance)
        if effective <= proximity { return 1 }
        if effective <= fadeDistance { return Double((fadeDistance - effective) / (fadeDistance - proximity)) }
        return 0
    }
}

/// The pointer position every card's border glow reads; one per window.
@MainActor
final class MagicBentoField: ObservableObject {
    @Published var pointer: CGPoint = .zero
    @Published var isInside = false
}

private struct MagicBentoFieldKey: EnvironmentKey {
    static let defaultValue: MagicBentoField? = nil
}

private struct MagicBentoGlowKey: EnvironmentKey {
    static let defaultValue = Color(red: 132 / 255.0, green: 0, blue: 1)
}

private struct InsideMagicBentoKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var magicBentoField: MagicBentoField? {
        get { self[MagicBentoFieldKey.self] }
        set { self[MagicBentoFieldKey.self] = newValue }
    }

    /// The current tab's accent, used for the border glow.
    var magicBentoGlow: Color {
        get { self[MagicBentoGlowKey.self] }
        set { self[MagicBentoGlowKey.self] = newValue }
    }

    /// Set inside a MagicBento card so nested cards don't draw a second glow.
    var insideMagicBento: Bool {
        get { self[InsideMagicBentoKey.self] }
        set { self[InsideMagicBentoKey.self] = newValue }
    }
}

extension View {
    /// The area MagicBento cards live in: tracks the pointer for their border glow, drawn in `glowColor`.
    func magicBentoSection(glowColor: Color) -> some View {
        modifier(MagicBentoSection(glowColor: glowColor))
    }

    /// MagicBento's border glow on an existing card.
    func magicBentoCard(cornerRadius: CGFloat) -> some View {
        modifier(MagicBentoCard(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
    }
}

private struct MagicBentoSection: ViewModifier {
    let glowColor: Color
    // @State (not @StateObject) keeps the field alive without re-evaluating this section on every mouse move.
    @State private var field = MagicBentoField()

    func body(content: Content) -> some View {
        content
            .environment(\.magicBentoField, field)
            .environment(\.magicBentoGlow, glowColor)
            .coordinateSpace(.named(MagicBento.coordinateSpace))
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let location):
                    field.pointer = location
                    if !field.isInside { field.isInside = true }
                case .ended:
                    field.isInside = false
                }
            }
    }
}

private struct MagicBentoCard<S: InsettableShape>: ViewModifier {
    let shape: S

    @Environment(\.magicBentoField) private var field
    @Environment(\.magicBentoGlow) private var glow
    @Environment(\.insideMagicBento) private var insideMagicBento

    @ViewBuilder
    func body(content: Content) -> some View {
        if insideMagicBento || field == nil {
            content
        } else {
            content
                .environment(\.insideMagicBento, true)
                .overlay {
                    if let field {
                        MagicBentoBorderGlow(field: field, shape: shape, glow: glow)
                    }
                }
        }
    }
}

private struct MagicBentoBorderGlow<S: InsettableShape>: View {
    @ObservedObject var field: MagicBentoField
    let shape: S
    let glow: Color

    var body: some View {
        GeometryReader { geo in
            let frame = geo.frame(in: .named(MagicBento.coordinateSpace))
            let intensity = field.isInside ? MagicBento.intensity(pointer: field.pointer, frame: frame) : 0
            let center = UnitPoint(
                x: frame.width > 0 ? (field.pointer.x - frame.minX) / frame.width : 0.5,
                y: frame.height > 0 ? (field.pointer.y - frame.minY) / frame.height : 0.5
            )
            // Out of the pointer's reach the glow is fully clear, so it isn't drawn at all (every card used to draw an invisible
            // gradient border on every mouse move).
            if intensity > 0.001 {
                shape.strokeBorder(
                    RadialGradient(
                        stops: [
                            .init(color: glow.opacity(0.8 * intensity), location: 0),
                            .init(color: glow.opacity(0.4 * intensity), location: 0.3),
                            .init(color: .clear, location: 0.6),
                        ],
                        center: center,
                        startRadius: 0,
                        endRadius: MagicBento.spotlightRadius
                    ),
                    lineWidth: 6
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
