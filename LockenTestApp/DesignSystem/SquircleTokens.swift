import SwiftUI
import AppKit

// MARK: - Titanium & Obsidian Liquid Glass Design Tokens (Native macOS)
public struct SquircleTokens {
    // Radii Hierarchy
    public static let radiusMicro: CGFloat = 8.0
    public static let radiusSmall: CGFloat = 12.0
    public static let radiusMedium: CGFloat = 16.0
    public static let radiusLarge: CGFloat = 22.0
    public static let radiusXL: CGFloat = 26.0

    // Titanium & Obsidian Foundation
    public static let obsidianBase = Color(red: 11/255.0, green: 11/255.0, blue: 15/255.0)       // #0B0B0F
    public static let obsidianSurface = Color(red: 18/255.0, green: 19/255.0, blue: 26/255.0)   // #12131A
    public static let obsidianCard = Color(red: 23/255.0, green: 24/255.0, blue: 34/255.0)      // #171822
    public static let titaniumChassis = Color(red: 35/255.0, green: 38/255.0, blue: 48/255.0)   // #232630
    public static let titaniumBorder = Color(white: 0.35).opacity(0.30)
    public static let crystalEdgeHairline = Color.white.opacity(0.18)

    // Brand Gradients & Accents
    public static let logoMagenta = Color(red: 0.88, green: 0.15, blue: 0.45)
    public static let logoViolet = Color(red: 0.55, green: 0.20, blue: 0.90)

    // Tab-Specific Gemstone & Horological Accents
    public static let amberDashboard = Color(red: 217/255.0, green: 119/255.0, blue: 6/255.0)    // #D97706 Incandescent Amber
    public static let wineBurgundy = Color(red: 136/255.0, green: 19/255.0, blue: 55/255.0)     // #881337 Wine Burgundy
    public static let restrainedRose = Color(red: 190/255.0, green: 18/255.0, blue: 60/255.0)   // #BE123C Restrained Rose
    public static let emeraldCalendar = Color(red: 6/255.0, green: 78/255.0, blue: 59/255.0)    // #064E3B Deep Emerald
    public static let mintAccent = Color(red: 16/255.0, green: 185/255.0, blue: 129/255.0)      // #10B981 Muted Mint
    public static let smokedNavy = Color(red: 30/255.0, green: 41/255.0, blue: 59/255.0)        // #1E293B Smoked Slate Navy
    public static let smokedAmber = Color(red: 245/255.0, green: 158/255.0, blue: 11/255.0)     // #F59E0B Smoked Amber
    public static let royalPlum = Color(red: 139/255.0, green: 92/255.0, blue: 246/255.0)       // #8B5CF6 Royal Slate Plum
    public static let vividNavy = Color(red: 51/255.0, green: 82/255.0, blue: 199/255.0)        // #3352C7 Vivid Navy Blue — bright enough to read as a glow accent, unlike the dark `smokedNavy` background tone
    public static let titaniumPlatinum = Color(red: 148/255.0, green: 163/255.0, blue: 184/255.0) // #94A3B8

    // Background Gradient per Tab
    public static func bgTop(for tab: String) -> Color {
        switch tab {
        case "dashboard", "new":
            return Color(red: 0.09, green: 0.03, blue: 0.05) // Obsidian Wine
        case "focus", "session":
            return Color(red: 0.06, green: 0.04, blue: 0.09) // Obsidian Violet
        case "calendar":
            return Color(red: 0.03, green: 0.07, blue: 0.05) // Obsidian Emerald
        case "analytics", "habits":
            return Color(red: 0.05, green: 0.06, blue: 0.09) // Obsidian Navy
        case "artifacts", "notes":
            return Color(red: 0.07, green: 0.05, blue: 0.10) // Obsidian Plum
        case "customize", "settings":
            return Color(red: 0.05, green: 0.05, blue: 0.07) // Titanium Obsidian
        case "routines":
            return Color(red: 0.06, green: 0.05, blue: 0.08)
        case "usage":
            return Color(red: 0.03, green: 0.06, blue: 0.09) // Obsidian Ocean
        default:
            return obsidianBase
        }
    }

    public static func bgBottom(for tab: String) -> Color {
        return Color(red: 8/255.0, green: 8/255.0, blue: 11/255.0) // Pure Deep Horizon
    }

    public static func accentColor(for tab: String) -> Color {
        switch tab {
        case "dashboard", "new":
            return restrainedRose
        case "focus", "session":
            return logoViolet
        case "calendar":
            return mintAccent
        case "analytics", "habits":
            return smokedAmber
        case "artifacts", "notes":
            return royalPlum
        case "customize", "settings":
            return titaniumPlatinum
        case "routines":
            return Color(red: 0.90, green: 0.75, blue: 0.35)
        case "usage":
            return Color(red: 56/255.0, green: 189/255.0, blue: 248/255.0) // #38BDF8 Sky
        case "assistant":
            return Color(red: 251/255.0, green: 113/255.0, blue: 88/255.0) // #FB7158 Coral
        default:
            return logoViolet
        }
    }

    /// The three BorderGlow gradient colors for each page, drawn from that page's palette.
    public static func glowGradientColors(for tab: String) -> [Color] {
        let sky = Color(red: 56/255.0, green: 189/255.0, blue: 248/255.0) // #38BDF8
        switch tab {
        case "dashboard", "new":
            return [restrainedRose, logoMagenta, smokedAmber]
        case "focus", "session":
            return [logoViolet, logoMagenta, vividNavy]
        case "calendar":
            return [mintAccent, sky, vividNavy]
        case "analytics", "habits":
            return [smokedAmber, amberDashboard, restrainedRose]
        case "artifacts", "notes":
            return [royalPlum, logoViolet, logoMagenta]
        case "customize", "settings":
            return [titaniumPlatinum, vividNavy, royalPlum]
        case "routines":
            return [Color(red: 0.90, green: 0.75, blue: 0.35), smokedAmber, amberDashboard]
        case "usage":
            return [sky, vividNavy, mintAccent]
        default:
            return [logoViolet, vividNavy, royalPlum]
        }
    }

    // Typography
    public static let textPrimary = Color.white
    public static let textSecondary = Color.white.opacity(0.72)
    public static let textMuted = Color.white.opacity(0.45)
    public static let textGold = Color(red: 0.95, green: 0.75, blue: 0.35)

    // Glass scrims: Liquid Glass renders much brighter and warmer in the key window than in an inactive one.
    // A neutral layer on the glass, under the content, keeps every surface at the calmer inactive look.
    public static let glassScrimBase = Color(red: 0.10, green: 0.10, blue: 0.12).opacity(0.6)
    public static let glassScrimRaised = Color(red: 0.17, green: 0.17, blue: 0.19).opacity(0.6)
}

// MARK: - Liquid Glass with a macOS 15 fallback
public extension View {
    /// System Liquid Glass on macOS 26 and later. On macOS 15 (Liquid Glass isn't available there) the same
    /// shape gets the frosted system material with the tint laid over it and a hairline rim, so cards keep
    /// their depth and readability on older Macs.
    @ViewBuilder
    func adaptiveGlass<S: Shape>(tint: Color?, in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            if let tint {
                self.glassEffect(.regular.tint(tint), in: shape)
            } else {
                self.glassEffect(.regular, in: shape)
            }
        } else {
            self
                .background(shape.fill(tint ?? .clear))
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
    }
}

// MARK: - Specular Liquid Glass & Squircle View Modifiers
public extension View {
    /// Real system Liquid Glass — this is the outer frame wrapping every
    /// tab's content (the "border on each tab"), so it's the most visible
    /// glass surface in the app. Previously a hand-rolled multi-layer
    /// ultraThinMaterial + 62%-alpha fill construction; now the same
    /// glassEffect API as everything else, at a light amber tint.
    func liquidGlassCard(cornerRadius: CGFloat = SquircleTokens.radiusXL) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(shape.fill(SquircleTokens.glassScrimBase))
            .adaptiveGlass(tint: SquircleTokens.amberDashboard.opacity(0.06), in: shape)
    }

    /// Luxury Inset Card for nested telemetry and list items — real system
    /// Liquid Glass, same glassEffect API as glassBox.
    /// Carries MagicBento's card effects (see `magicBentoCard`).
    func innerObsidianCard(cornerRadius: CGFloat = SquircleTokens.radiusMedium) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(shape.fill(SquircleTokens.glassScrimRaised))
            .adaptiveGlass(tint: Color.white.opacity(0.05), in: shape)
            .magicBentoCard(cornerRadius: cornerRadius)
    }

    /// Primary Obsidian Titanium Card with elevated bevel — real system
    /// Liquid Glass; previously a hand-rolled 85%-alpha solid fill.
    /// Carries MagicBento's card effects (see `magicBentoCard`).
    func luxuryObsidianCard(cornerRadius: CGFloat = SquircleTokens.radiusLarge) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(shape.fill(SquircleTokens.glassScrimRaised))
            .adaptiveGlass(tint: Color.white.opacity(0.04), in: shape)
            .magicBentoCard(cornerRadius: cornerRadius)
    }

    /// Button surface: native port of React Bits' BorderGlow, with glow gradient colors from the current page.
    /// `isProminent` adds an accent tint so primary and selected buttons stay distinguishable.
    func borderGlowButton(accent: Color, isProminent: Bool) -> some View {
        modifier(BorderGlowModifier(accent: accent, isProminent: isProminent))
    }

    /// Real system Liquid Glass for rectangular cards/boxes (macOS 26 `glassEffect` API).
    ///
    /// No `.interactive()` here: `Glass.interactive()` gives the glass shape
    /// its own press/touch gesture recognizer, meant for cases where the
    /// glass *is* the control (e.g. `.buttonStyle(.glass)`). Every call site
    /// wraps this in an explicit `Button { }`, which already owns tap handling —
    /// the two recognizers competing was intermittently swallowing the first
    /// tap and only registering on a second attempt.
    /// The accent sits on top of the scrim (not in the glass tint) so it keeps its strength while the glass is muted.
    func glassBox(accent: Color, cornerRadius: CGFloat, tintOpacity: Double = 0.16) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(
                ZStack {
                    shape.fill(SquircleTokens.glassScrimRaised)
                    shape.fill(accent.opacity(tintOpacity))
                }
            )
            .adaptiveGlass(tint: nil, in: shape)
    }

    /// Brief animated border trace overlaid on a container to confirm a
    /// successful action (e.g. a notch check-in). Purely visual — never
    /// intercepts interaction with the content it frames.
    func borderTraceConfirm(active: Bool, color: Color = SquircleTokens.mintAccent, cornerRadius: CGFloat = SquircleTokens.radiusMedium) -> some View {
        self.overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .trim(from: 0, to: active ? 1 : 0)
                .stroke(color, lineWidth: 1.5)
                .opacity(active ? 0.9 : 0)
                .animation(active ? .easeOut(duration: 0.55) : .easeOut(duration: 0.25), value: active)
                .allowsHitTesting(false)
        )
    }

    // Editorial Serif typography for prestige titles
    func editorialSerif(size: CGFloat = 20, weight: Font.Weight = .semibold) -> some View {
        self.font(.appFont(size: size, weight: weight))
    }

    // Delicate cursive script accent for personal greetings and signature moments
    @ViewBuilder
    func scriptAccent(size: CGFloat = 28) -> some View {
        if NSFont(name: "Snell Roundhand", size: size) != nil {
            self.font(.custom("Snell Roundhand", size: size))
        } else {
            self.font(.system(size: size, weight: .regular, design: .serif)).italic()
        }
    }

    /// Fades and lifts content in as it scrolls into view, and softens it as it scrolls out.
    /// Mirrors the eased, staged scroll reveal from the Locken marketing site.
    func scrollReveal() -> some View {
        self.scrollTransition { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0)
                .scaleEffect(phase.isIdentity ? 1 : 0.97)
                .offset(y: phase.isIdentity ? 0 : (phase.value < 0 ? -14 : 14))
        }
    }
}

public extension Font {
    /// Two typefaces, Doto as the main one and Montserrat as the secondary:
    /// - Doto (SIL OFL, see Doto-OFL.txt), the dot-matrix face, for headings, titles, buttons, navigation and
    ///   numbers: anything 15 pt and larger, and 13–14 pt text at semibold or heavier. Weight 800 (900 for
    ///   semibold and heavier) with round dots (ROND 100), drawn at 15 pt or more so its dots stay sharp.
    /// - Montserrat (SIL OFL, see Montserrat-OFL.txt) for descriptions, body text and small print: regular text under
    ///   15 pt (medium included, so quotes and multi-line text don't crowd), and anything under 13 pt.
    /// Both are registered at launch in `LockenTestApp.init()`. `scriptAccent` (the cursive titles) is untouched.
    /// Falls back to the system font if neither is registered.
    static func appFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let isEmphasis = [.semibold, .bold, .heavy, .black].contains(weight)
        if size >= 15 || (size >= DotoFont.minimumSize && isEmphasis) {
            let dotoWeight: CGFloat
            switch weight {
            case .semibold, .bold, .heavy, .black:
                dotoWeight = 900
            default:
                dotoWeight = 800
            }
            if let font = DotoFont.font(size: size, weight: dotoWeight) {
                return Font(font as CTFont)
            }
        }
        let postScriptName: String
        switch weight {
        case .bold, .heavy, .black:
            postScriptName = "Montserrat-Bold"
        case .semibold:
            postScriptName = "Montserrat-SemiBold"
        case .medium:
            postScriptName = "Montserrat-Medium"
        default:
            postScriptName = "Montserrat-Regular"
        }
        guard NSFont(name: postScriptName, size: size) != nil else {
            return .system(size: size, weight: weight)
        }
        return .custom(postScriptName, size: size)
    }
}

/// Doto instances with explicit `wght` and `ROND` axis values, cached per size and weight
/// because `appFont` runs on every view update.
enum DotoFont {
    private static let weightAxis = NSNumber(value: 0x7767_6874) // 'wght'
    private static let roundAxis = NSNumber(value: 0x524F_4E44)  // 'ROND'
    private static let lock = NSLock()
    private static var cache: [String: NSFont] = [:]
    private static var scale: CGFloat = 2

    /// Pixels per point of the screen the window is on: 2 on Retina, 1 on a standard monitor like a 1080p display.
    /// Set by `DisplayScaleRoot`, which re-renders the window when it moves to a screen with a different scale.
    static var backingScale: CGFloat {
        get { lock.lock(); defer { lock.unlock() }; return scale }
        set { lock.lock(); scale = newValue >= 1.5 ? 2 : 1; lock.unlock() }
    }

    /// Text requested below this size uses Montserrat at its own size; the rest is Doto, on every screen (Mohammed
    /// Sir wants the dotted look kept on standard monitors too, 2026-10-18).
    static var minimumSize: CGFloat { 13 }

    /// Doto's dots sit on a grid one tenth of the font size apart. The size is snapped to multiples of 5 pt (at
    /// least 15 pt), so on Retina the grid lands on whole pixels; on a standard screen the dots are 1.5 px apart,
    /// slightly softer but still dotted.
    static func pixelAlignedSize(_ size: CGFloat) -> CGFloat {
        max(15, (size / 5).rounded() * 5)
    }

    static func font(size requested: CGFloat, weight: CGFloat) -> NSFont? {
        let size = pixelAlignedSize(requested)
        let key = "\(size)-\(weight)"
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] { return cached }
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: "Doto",
            .variation: [weightAxis: weight, roundAxis: 100],
        ])
        guard let font = NSFont(descriptor: descriptor, size: size), font.familyName == "Doto" else { return nil }
        cache[key] = font
        return font
    }
}

/// Wraps the window's content so `Font.appFont` knows the current screen's pixel density. When the window moves
/// between a Retina and a standard screen, the content is rebuilt so every label picks the right font and size.
/// App state lives in `TestAppStateManager`, so it survives the rebuild.
struct DisplayScaleRoot<Content: View>: View {
    @Environment(\.displayScale) private var displayScale
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let density: CGFloat = displayScale >= 1.5 ? 2 : 1
        DotoFont.backingScale = density
        return content.id(density)
    }
}

/// Native port of Aceternity UI's Text Generate Effect, used for screen titles: each word fades in from a
/// 10pt blur, 0.2 s apart, over 0.5 s (its `filter: blur(10px)` → `blur(0)` with `opacity` 0 → 1).
/// The router's `.id(state.selectedTab)` remounts it, so it replays on tab switches only.
public struct TextGenerateEffect: View {
    private let text: String
    @State private var isShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        let words = text.split(separator: " ").map(String.init)
        HStack(spacing: 0) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                Text(index < words.count - 1 ? word + " " : word)
                    .opacity(isShown || reduceMotion ? 1 : 0)
                    .blur(radius: isShown || reduceMotion ? 0 : 10)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.5).delay(Double(index) * 0.2), value: isShown)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.isHeader)
        .onAppear { isShown = true }
    }
}

extension View {
    /// A secondary action next to a main button: plain text, no fill or outline, so each screen has one clear
    /// primary button instead of the filled-plus-outlined pair that marks generic AI-made UI.
    func quietAction() -> some View {
        self
            .font(.appFont(size: 13, weight: .medium))
            .foregroundColor(.white.opacity(0.6))
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
    }
}


// MARK: - BorderGlow (native port of React Bits BorderGlow, JS-CSS variant)
/// Mirrors the CSS layers: a 1px colored mesh border and a soft-light mesh fill shown within a cone
/// around the pointer's angle, plus an outer glow, all fading in as the pointer nears an edge.
/// Configured as edgeSensitivity 30, glowColor "40 80 80", backgroundColor #120F17, borderRadius 28,
/// glowRadius 40, glowIntensity 1.0, coneSpread 25, animated false. The mesh border and the outer glow are all the page's
/// accent (the tab's own colour), not the original's mixed colours and cream.
struct BorderGlowModifier: ViewModifier {
    let accent: Color
    let isProminent: Bool

    @ObservedObject private var state = TestAppStateManager.shared
    @State private var size: CGSize = .zero
    @State private var edgeProximity: Double = 0 // 0 at the center, 100 at the edge
    @State private var cursorAngle: Double = 45  // CSS convention: 0° = top, clockwise
    @State private var isHovering = false

    private let edgeSensitivity: Double = 30
    private let backgroundColor = Color(red: 0x12 / 255.0, green: 0x0F / 255.0, blue: 0x17 / 255.0)
    private let borderRadius: CGFloat = 28
    private let glowRadius: CGFloat = 40
    private let glowIntensity: Double = 1.0
    private let coneSpread: Double = 25
    private let fillOpacity: Double = 0.5
    /// The outer glow: the accent lifted toward white so it still shines on the dark fill.
    private var glowColor: Color { accent.lightened(0.35) }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: min(borderRadius, size.height / 2), style: .continuous)
        // Three shades of the one accent, so the border and fill glow in the tab's colour only.
        let colors = [accent.lightened(0.3), accent, accent.darkened(0.25)]
        let colorSensitivity = edgeSensitivity + 20
        let meshOpacity = Self.clamp((edgeProximity - colorSensitivity) / (100 - colorSensitivity))
        let glowOpacity = Self.clamp((edgeProximity - edgeSensitivity) / (100 - edgeSensitivity))
        let spread = coneSpread / 100

        content
            .background {
                ZStack {
                    shape.fill(backgroundColor)
                    shape.fill(accent.opacity(isProminent ? 0.30 : 0.08))
                    if isHovering {
                        BorderGlowMesh(colors: colors)
                            .mask(RadialGradient(colors: [.clear, .black], center: .center, startRadius: 0, endRadius: max(size.width, size.height) * 0.5))
                            .clipShape(shape)
                            .opacity(fillOpacity * meshOpacity)
                            .blendMode(.softLight)
                            .transition(.opacity)
                    }
                }
                .shadow(color: .black.opacity(0.20), radius: 4, y: 2)
                .shadow(color: .black.opacity(0.15), radius: 16, y: 8)
            }
            .overlay {
                shape.strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .overlay {
                if isHovering {
                    BorderGlowMesh(colors: colors)
                        .mask(shape.strokeBorder(lineWidth: 1))
                        .mask(Self.cone(angle: cursorAngle, stops: [
                            (0, 1), (spread, 1), (spread + 0.15, 0), (1 - spread - 0.15, 0), (1 - spread, 1), (1, 1),
                        ]))
                        .opacity(meshOpacity)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .overlay {
                if isHovering {
                    outerGlow(shape: shape)
                        .frame(width: size.width, height: size.height)
                        .frame(width: size.width + glowRadius * 2, height: size.height + glowRadius * 2)
                        .mask(Self.cone(angle: cursorAngle, stops: [
                            (0, 1), (0.025, 1), (0.10, 0), (0.90, 0), (0.975, 1), (1, 1),
                        ]))
                        .opacity(glowOpacity)
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { newSize in
                size = newSize
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    updatePointer(location)
                    if !isHovering {
                        withAnimation(.easeOut(duration: 0.25)) { isHovering = true }
                    }
                case .ended:
                    withAnimation(.easeInOut(duration: 0.75)) { isHovering = false }
                }
            }
    }

    private func outerGlow(shape: RoundedRectangle) -> some View {
        let halos: [(blur: CGFloat, opacity: Double)] = [(1, 0.6), (3, 0.5), (6, 0.4), (15, 0.3), (25, 0.2), (50, 0.1)]
        return ZStack {
            shape.stroke(glowColor.opacity(min(glowIntensity, 1)), lineWidth: 1)
            ForEach(halos.indices, id: \.self) { index in
                shape.stroke(glowColor.opacity(min(halos[index].opacity * glowIntensity, 1)), lineWidth: 2)
                    .blur(radius: halos[index].blur / 2)
            }
        }
    }

    private func updatePointer(_ location: CGPoint) {
        let cx = size.width / 2
        let cy = size.height / 2
        guard cx > 0, cy > 0 else { return }
        let dx = location.x - cx
        let dy = location.y - cy
        edgeProximity = min(max(max(abs(dx) / cx, abs(dy) / cy), 0), 1) * 100
        guard dx != 0 || dy != 0 else { return }
        var degrees = atan2(dy, dx) * 180 / .pi + 90
        if degrees < 0 { degrees += 360 }
        cursorAngle = degrees
    }

    /// CSS `conic-gradient(from <angle> at center, …)` as a black/clear mask; SwiftUI's 0° points right, CSS's points up.
    private static func cone(angle: Double, stops: [(location: Double, alpha: Double)]) -> AngularGradient {
        AngularGradient(
            stops: stops.map { Gradient.Stop(color: Color.black.opacity($0.alpha), location: $0.location) },
            center: .center,
            startAngle: .degrees(angle - 90),
            endAngle: .degrees(angle + 270)
        )
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

/// BorderGlow's mesh: a base color under seven radial blobs at fixed positions (color index map 0,1,2,0,1,2,1).
private struct BorderGlowMesh: View {
    let colors: [Color]

    private static let positions: [UnitPoint] = [
        UnitPoint(x: 0.80, y: 0.55), UnitPoint(x: 0.69, y: 0.34), UnitPoint(x: 0.08, y: 0.06),
        UnitPoint(x: 0.41, y: 0.38), UnitPoint(x: 0.86, y: 0.85), UnitPoint(x: 0.82, y: 0.18),
        UnitPoint(x: 0.51, y: 0.04),
    ]
    private static let colorIndex = [0, 1, 2, 0, 1, 2, 1]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                colors[0]
                // CSS paints the first gradient on top, so draw them in reverse.
                ForEach(Array(Self.positions.indices.reversed()), id: \.self) { index in
                    let point = Self.positions[index]
                    let color = colors[min(Self.colorIndex[index], colors.count - 1)]
                    // radial-gradient(at x y, color 0, transparent 50%) — 50% of the farthest-corner radius.
                    let farthestCorner = hypot(
                        max(point.x, 1 - point.x) * geometry.size.width,
                        max(point.y, 1 - point.y) * geometry.size.height
                    )
                    RadialGradient(
                        colors: [color, color.opacity(0)],
                        center: point,
                        startRadius: 0,
                        endRadius: max(farthestCorner * 0.5, 1)
                    )
                }
            }
        }
    }
}

// MARK: - Color helpers
public extension Color {
    /// sRGB "#rrggbb", for handing colors to the web components.
    var hexRGB: String {
        let color = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        return String(
            format: "#%02x%02x%02x",
            Int((color.redComponent * 255).rounded()),
            Int((color.greenComponent * 255).rounded()),
            Int((color.blueComponent * 255).rounded())
        )
    }

    /// This color mixed toward white by `amount` (0…1).
    func lightened(_ amount: CGFloat) -> Color {
        let base = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        return Color(nsColor: base.blended(withFraction: amount, of: .white) ?? base)
    }

    /// This color mixed toward black by `amount` (0…1).
    func darkened(_ amount: CGFloat) -> Color {
        let base = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        return Color(nsColor: base.blended(withFraction: amount, of: .black) ?? base)
    }
}

public extension SquircleTokens {
    /// A page's accent lifted toward white so it stays legible as text on the dark glass.
    static func readableAccent(for tab: String) -> Color {
        accentColor(for: tab).lightened(0.45)
    }
}

// MARK: - Page layout (shared by every tab)

/// One spacing scale for every page.
public enum Spacing {
    public static let xs: CGFloat = 8
    public static let s: CGFloat = 12
    public static let m: CGFloat = 16
    public static let l: CGFloat = 24
    public static let xl: CGFloat = 32
}

/// The line between sections, used app-wide so every section break looks the same and is easy to see.
public struct SectionDivider: View {
    /// Rows inside a list use the lighter weight; section breaks use the default.
    public var isSubtle = false
    public init(subtle: Bool = false) { isSubtle = subtle }
    public var body: some View {
        Rectangle()
            .fill(Color.white.opacity(isSubtle ? 0.1 : 0.16))
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// The widest a page's content gets, so it stays a centered column on large windows.
public enum PageWidth {
    /// Dashboards and multi-column pages.
    public static let wide: CGFloat = 1160
    /// Single-column lists (calendar).
    public static let reading: CGFloat = 880
    /// Forms and settings.
    public static let form: CGFloat = 720
    /// Equal margin on both sides of every page.
    public static let margin: CGFloat = 28
}

public extension View {
    /// Centers a page's content in a column of at most `maxWidth`, with equal margins on both sides.
    func lockenPage(maxWidth: CGFloat = PageWidth.wide) -> some View {
        self
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, PageWidth.margin)
            .padding(.top, PageWidth.margin)
            .padding(.bottom, PageWidth.margin * 2)
    }
}

/// A page's title (the cursive accent) with an optional plain subtitle, centered.
struct PageHeader<Accessory: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(spacing: Spacing.xs) {
            TextGenerateEffect(title)
                .scriptAccent(size: 30)
                .foregroundColor(.white)
            if let subtitle {
                Text(subtitle)
                    .font(.appFont(size: 13))
                    .foregroundColor(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
                    .fixedSize(horizontal: false, vertical: true)
            }
            accessory
        }
        .frame(maxWidth: .infinity)
    }
}

extension PageHeader where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - Liquid glass controls (liquid-glass-techniques skill)

public extension View {
    /// Lens-edge rim light: a 1pt border that is bright on two opposite corners and faint between them,
    /// like the edge of a glass lens. For controls only; it never takes clicks.
    func glassRimLight(cornerRadius: CGFloat) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.42), location: 0),
                            .init(color: .clear, location: 0.22),
                            .init(color: .white.opacity(0.08), location: 0.45),
                            .init(color: .white.opacity(0.08), location: 0.60),
                            .init(color: .clear, location: 0.88),
                            .init(color: .white.opacity(0.42), location: 1),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        )
    }
}

/// The selected-item highlight: a glass pill with a top-to-bottom sheen, a lens rim and a soft drop shadow.
/// Give it a `matchedGeometryEffect` so it slides from item to item.
struct GlassPill: View {
    var cornerRadius: CGFloat = 10

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(LinearGradient(colors: [.white.opacity(0.17), .white.opacity(0.07)], startPoint: .top, endPoint: .bottom))
            .glassRimLight(cornerRadius: cornerRadius)
            .shadow(color: .black.opacity(0.10), radius: 1, y: 1)
            .shadow(color: .black.opacity(0.28), radius: 7, y: 6)
    }
}

/// Liquid glass switch: a 44×24 track with a 30pt glass knob that overhangs it and widens while pressed,
/// then springs across with a slight overshoot. The track fills with the page accent when on.
/// VoiceOver still sees an ordinary switch.
struct GlassSwitchToggleStyle: ToggleStyle {
    var tint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        GlassSwitch(configuration: configuration, tint: tint)
    }
}

private struct GlassSwitch: View {
    let configuration: ToggleStyleConfiguration
    let tint: Color?

    @ObservedObject private var state = TestAppStateManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 8) {
            configuration.label
            Button { configuration.isOn.toggle() } label: { EmptyView() }
                .buttonStyle(GlassSwitchKnobStyle(
                    isOn: configuration.isOn,
                    tint: tint ?? SquircleTokens.accentColor(for: state.selectedTab),
                    reduceMotion: reduceMotion
                ))
        }
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

private struct GlassSwitchKnobStyle: ButtonStyle {
    let isOn: Bool
    let tint: Color
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let spring: Animation? = reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.62)
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? tint : Color.white.opacity(0.12))
                .overlay(Capsule().strokeBorder(Color.white.opacity(isOn ? 0.18 : 0.10), lineWidth: 1))
            Capsule()
                .fill(RadialGradient(
                    stops: [
                        .init(color: .white.opacity(0.97), location: 0),
                        .init(color: .white.opacity(0.80), location: 0.55),
                        .init(color: .white.opacity(0.62), location: 1),
                    ],
                    center: UnitPoint(x: 0.3, y: 0.2),
                    startRadius: 0,
                    endRadius: 32
                ))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.7), lineWidth: 1))
                .overlay(Capsule().strokeBorder(
                    LinearGradient(colors: [.clear, .black.opacity(0.10)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 2
                ))
                .shadow(color: .black.opacity(0.30), radius: 9, y: 7)
                // Widens toward the middle of the track while held.
                .frame(width: pressed ? 36 : 30, height: 30)
                .offset(x: isOn ? 3 : -3)
        }
        .frame(width: 44, height: 24)
        .contentShape(Capsule())
        .animation(spring, value: isOn)
        .animation(spring, value: pressed)
    }
}
