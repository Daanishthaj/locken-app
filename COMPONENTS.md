# Locken component guide

Every UI component used in the Locken apps, what it is, where it came from, and the exact settings Locken uses, so the same look can be reused in another project.

- **Web components** are React components that run inside a transparent `WKWebView` in the Locken Test App. In a React or Next.js project you use them directly.
- **Native components** are SwiftUI. In another SwiftUI (macOS 26) project you copy the file or snippet.
- Paths are relative to the repo root. Copy the full source from the listed file; the code below is the configuration Locken uses.

## Index

| # | Component | Kind | Origin | Used for | Source file |
|---|---|---|---|---|---|
| 1 | ElectricLogo | Web (React) | React Bits | Electric outline around the selected app icon (session setup) | `LockenTestApp/WebComponents/src/ElectricLogo.jsx` + `.css` |
| 2 | DitherVeil | Web (React) | React Bits | Focus tab hero image that reveals under the pointer | `LockenTestApp/WebComponents/src/DitherVeil.jsx` + `.css` |
| 3 | ProfileCard | Web (React) | React Bits | Sidebar profile card with now-playing music | `LockenTestApp/WebComponents/src/ProfileCard.jsx` + `.css` |
| 4 | JellyRadio | Web (React) | React Bits | Every single-choice picker (Canvas / My Own Goal, priority, etc.) | `LockenTestApp/WebComponents/src/JellyRadio.jsx` + `.css` |
| 5 | CodeSlots | Web (React) | React Bits | 6-digit email / authenticator code entry | `LockenTestApp/WebComponents/src/CodeSlots.jsx` + `.css` |
| 6 | 3D Orb | Web (React + three.js) | 21st.dev | Home hero orb | `LockenTestApp/WebComponents/src/components/ui/3d-orb.tsx` |
| 7 | Menu bar padlock | SwiftUI | Locken's own | The menu bar timer's icon | `LockenTestApp/DesignSystem/LogoTraceLoader.swift` |
| 8 | Papers transition | Plain HTML/CSS/JS | Your spec | Animation between session setup and the timer | `LockenTestApp/WebComponents/public/papers.html` |
| 9 | BorderGlow | Native SwiftUI | React Bits port | Every button surface | `LockenTestApp/DesignSystem/SquircleTokens.swift` (`BorderGlowModifier`) |
| 10 | MagicBento border glow | Native SwiftUI | React Bits port | Card border that lights up near the pointer | `LockenTestApp/DesignSystem/MagicBento.swift` |
| 11 | Liquid glass surfaces | Native SwiftUI | Apple Liquid Glass | Page frame, cards, boxes | `LockenTestApp/DesignSystem/SquircleTokens.swift` |
| 12 | Glass pill | Native SwiftUI | Local Flow techniques | Sliding sidebar selection | `SquircleTokens.swift`, `KissaFocus/Views/DesignSystem/Theme.swift` |
| 13 | Glass switch | Native SwiftUI | Local Flow techniques | Every on/off switch | same as 12 |
| 14 | Glass rim light | Native SwiftUI | Local Flow techniques | Lens edge on glass controls | same as 12 |
| 15 | TextGenerateEffect | Native SwiftUI | Aceternity UI port | Page titles | `SquircleTokens.swift` |
| 16 | Notch check-in | Native SwiftUI + AppKit | Custom (`macos-notch-ui` skill) | Drop-down prompt from the notch | `LockenTestApp/Services/CheckInWindowManager.swift` |
| 17 | Small helpers | Native SwiftUI | Custom | `quietAction`, `borderTraceConfirm`, `scrollReveal` | `SquircleTokens.swift` |
| 18 | revealWhenLoaded | Native SwiftUI | Custom | Fades a page in only once its web views and 3D are ready | `LockenTestApp/DesignSystem/AssetLoadGate.swift` |
| 19 | GhostFibers background | Native SwiftUI Canvas | Custom | Moving fibre lines behind the sign-in screen (the app window uses one plain colour since 2026-10-19) | `LockenTestApp/Views/MainContentView.swift` |
| 20 | ~~Brain model~~ | Native SceneKit | USDZ model | Removed 2026-10-16 with the Intelligence tab | — |
| 21 | Design tokens | Native SwiftUI | Custom | Colors, radii, per-tab accents | `SquircleTokens.swift` |
| 22 | ConcentricRectangle | Native SwiftUI | Custom | Main app's nested bevelled containers | `KissaFocus/Views/DesignSystem/ConcentricRectangle.swift` |
| 23 | TiltedMusicCard | Native SwiftUI | React Bits TiltedCard, ported | Main app sidebar music widget | `KissaFocus/Views/DesignSystem/TiltedMusicCardView.swift` |
| 24 | Ferrofluid background | Web shader in WKWebView | React Bits | Main app background | `KissaFocus/Views/DesignSystem/FerrofluidBackgroundView.swift` |
| 25 | RotatingText | Native SwiftUI | React Bits, ported | Main app startup text | `KissaFocus/Views/DesignSystem/RotatingTextView.swift` |
| 26 | Spline 3D view | WKWebView | Spline | Main app 3D scenes | `KissaFocus/Views/DesignSystem/Spline3DView.swift` |
| 27 | SceneKit 3D scenes | Native SceneKit | Custom | Main app procedural 3D heroes | `KissaFocus/Views/DesignSystem/Glass3DSceneView.swift` |
| 28 | SquishButtonStyle | Native SwiftUI | Custom | Main app press feedback on buttons | `KissaFocus/Views/DesignSystem/Theme.swift` |
| 29 | Strands | Web (React, WebGL2) | React Bits | Assistant tab hero | `LockenTestApp/WebComponents/src/Strands.jsx` + `.css`, page `strands-entry.jsx` |
| 30 | GradualBlur | Native SwiftUI | React Bits port | Blur along the bottom of scrolling pages | `LockenTestApp/DesignSystem/GradualBlur.swift` |
| 31 | GlassIcons | Web (React, WebGL2) | React Bits | The collapsed sidebar's page buttons (Mac and Windows) | `LockenTestApp/WebComponents/src/GlassIcons.jsx` + `.css`, page `glassicons-entry.jsx` |
| 32 | LogoLoop | Web (React) | React Bits | The website's "Works with" rows of connected services | `web/src/components/LogoLoop.jsx` + `.css`, island `web/src/site/connectors.jsx` |
| 33 | Check-in aurora | Native SwiftUI (Mac), HTML/CSS (Windows) | Custom | Soft glow along the top of the screen while the check-in is open | `CheckInWindowManager.swift` (`CheckInAuroraView`), `windows/aurora.html` |

---

## Part A: Web components (Locken Test App)

### How they run in Locken

- Each component has an entry file (`*-entry.jsx`) that renders it with Locken's settings.
- `LockenTestApp/WebComponents/build.mjs` bundles each entry with esbuild into `LockenTestApp/Resources/Web/<page>.html`. Run `npm install` then `npm run build` in `LockenTestApp/WebComponents`.
- `LockenTestApp/Views/ReactBitsWebView.swift` loads a page into a transparent `WKWebView`:
  - props go in as `window.__initialProps` and later `window.updateProps(props)`
  - the page talks back with `window.webkit.messageHandlers.locken.postMessage("...")`
- **In a React project** you don't need any of that bridge. Copy the component's `.jsx` and `.css`, install its packages, and use the props shown below.

Shared packages (`LockenTestApp/WebComponents/package.json`):

```bash
npm install react react-dom motion framer-motion ogl three @react-three/fiber @hugeicons/react @hugeicons/core-free-icons
```

### 1. ElectricLogo (React Bits)

An animated electric outline that traces an icon. Locken tuned it for a small 44pt icon: smaller mark, two thin strands, dim glow.

```jsx
import ElectricLogo from './ElectricLogo';

<div style={{ width: '100%', height: '100%', position: 'relative' }}>
  <ElectricLogo
    src={iconDataUrlOrPath}   // the icon to trace (Locken passes the selected app's logo as a data URL)
    color="#ecc7ff"
    glowColor="#ad6dff"
    scale={0.55}
    intensity={0.6}
    glow={0.35}
    thickness={1.0}
    strands={2}
    bend={0.6}
    crackle={1.0}
    arcs={0}
    speed={2.5}
    cursorRadius={30}
    interactive
  />
</div>
```

SwiftUI call site (`LockenTestApp/Views/SessionSetupView.swift`): `ReactBitsWebView(page: .electricLogo, props: ["src": dataURL])`.

### 2. DitherVeil (React Bits)

An image drawn as Floyd–Steinberg dither dots that clears into the real photo around the pointer.

```jsx
import DitherVeil from './DitherVeil';

<div style={{ width: '100%', height: '100%', position: 'relative' }}>
  <DitherVeil
    src="https://images.unsplash.com/photo-1737071371043-761e02b1ef95?q=80&w=1400&auto=format&fit=crop"
    pattern="floyd"
    pixelSize={2}
    inkColor="#120f17"
    paperColor="#f4f1ea"   // Locken passes a light tint of the Focus tab's rose accent
    revealRadius={200}
    softness={0.6}
    linger={1}
  />
</div>
```

Locken bundles the image (`src/assets/dither-hero.jpg`, an Unsplash photo under the Unsplash License), so it works offline. In Locken the view sits behind a scroll view, so the app forwards the pointer with `window.__lockenPointer(x, y, inside)`; a normal web page doesn't need that.

### 3. ProfileCard (React Bits)

A tilting holographic profile card. Locken replaces the name with a now-playing row (cover, song, play/pause) and turns the contact button into a settings gear.

```jsx
import ProfileCard from './ProfileCard';

const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

<ProfileCard
  name="Your Name"
  title=""
  handle="your-username"
  status="Online"
  contactText={<img className="pc-settings-icon" src={settingsIconUrl} alt="" />}
  avatarUrl={avatarUrl}
  showUserInfo={true}
  enableTilt={!reducedMotion}         // no tilt or moving shine with Reduce Motion
  enableMobileTilt={false}
  onContactClick={() => openSettings()}
  iconUrl="iconpattern.png"           // LockenTestApp/WebComponents/public/iconpattern.png
  behindGlowEnabled
  innerGradient="linear-gradient(145deg,#60496e8c 0%,#71C4FF44 100%)"   // Locken tints this per tab
  behindGlowColor={undefined}         // optional per-tab glow color
  header={<MusicHeader /* see profile-entry.jsx */ />}
/>
```

- The full now-playing header (`MusicHeader`) is in `LockenTestApp/WebComponents/src/profile-entry.jsx`.
- The CSS that fits the card into a narrow sidebar (scaled 450px layout, glass music row) is in the `profile` block of `build.mjs`. Copy it if your card is also small.

### 4. JellyRadio (React Bits)

A row of pills where the selection squishes across like jelly. Locken uses it for every single choice.

```jsx
import JellyRadio from './JellyRadio';

<JellyRadio
  items={['Canvas Assignment', 'My Own Goal']}
  value={selected}
  onChange={setSelected}
  ariaLabel="Goal source"
  chipColor="#27272a"
  activeColor="#f5f5f5"      // Locken uses a very light tint of the current tab's accent
  textColor="#f5f5f5"
  activeTextColor="#18181b"
  size="md"
  gap={8}
  radius={18}
  swell={0.2}
  barge={6}
  shrink={0.05}
  jelly={1}
  bounce={0.25}
  stagger={22}
  stiffness={580}
/>
```

Font: Doto, weight 800, round dots (`.jelly-radio__label { white-space: nowrap; }`). SwiftUI wrapper: `JellyRadioPicker(items:selection:label:)` in `LockenTestApp/Views/ReactBitsWebView.swift`. It reports the component's size so the native frame hugs it.

### 5. CodeSlots (React Bits)

Six animated digit boxes for a verification code, with success and error states.

```jsx
import CodeSlots from './CodeSlots';

<CodeSlots
  key={resetKey}              // change it to clear the boxes
  length={6}
  status={status}             // 'idle' | 'success' | 'error'
  onChange={() => setStatus('idle')}
  onComplete={code => verify(code)}
  accentColor="#f5f5f5"       // Locken passes the page accent
  inkColor="#f5f5f5"
  slotColor="#27272a"
  digitColor="#18181b"
  dangerColor="#ff3b30"
  slotSize={44}
  gap={8}
  radius={12}
  bounce={0.2}
  settle={0.3}
  rise={8}
  cascade={20}
/>
```

SwiftUI wrapper: `CodeSlotsField` in `LockenTestApp/Views/ReactBitsWebView.swift`.

### 6. 3D Orb (21st.dev)

A wireframe globe in a soft glow inside a slowly turning starfield (three.js), on a transparent background. Replaced
OriginKit's plasma ring on 2026-10-25. Adapted from the 21st.dev component: no Tailwind, colours from the app, no earth
textures (not shipped, so it stays a wireframe), no "Drag to explore" hint, and Reduce Motion holds it still. The page
CSS fades the starfield toward the frame's edges so no square shows.

```jsx
import Globe from './components/ui/3d-orb';

<Globe
  colors={['#…', '#…', '#…']}   // Locken passes the tab accent darkened 55%, 40% and 15%; the orb drifts between them
  still={reducedMotion}
/>
```

### 7. Menu bar padlock (Locken's own)

`LockenLogo.menuBarImage(open:)` (in `LogoTraceLoader.swift`) draws a squared-off Locken padlock (`squareShackle`, `squareBody`: flat-topped shackle, 4-pt body corners, slot keyhole) as the menu bar's template icon; the shackle lifts while a session is paused. The sign-in screen shows no logo (removed 2026-10-18).

### 8. Papers transition (plain HTML)

Ten notebook-paper sheets fly to random spots with a random spin (1.5s ease-out), then slide back after 2 seconds. No libraries. Copy `LockenTestApp/WebComponents/public/papers.html` as-is. The settings that matter:

- background transparent
- each sheet `18vmin × 24vmin`
- spread over 75% × 65% of the window
- `transition: transform 1.5s ease-out`, with the transform set 20 ms after the sheet is created
- each sheet slightly differently shaded

```css
.paper {
  position: fixed; left: 50%; top: 50%;
  width: 18vmin; height: 24vmin; margin: -12vmin 0 0 -9vmin;
  background:
    url("data:image/svg+xml,...feTurbulence fibre grain...") ,
    linear-gradient(to right, transparent 3vmin, rgba(205,85,85,.45) 3vmin, rgba(205,85,85,.45) calc(3vmin + 1px), transparent calc(3vmin + 1px)),
    repeating-linear-gradient(to bottom, transparent 0, transparent calc(1.9vmin - 1px), rgba(95,125,180,.22) calc(1.9vmin - 1px), rgba(95,125,180,.22) 1.9vmin) 0 3.4vmin / 100% calc(100% - 3.4vmin) no-repeat,
    linear-gradient(160deg, #f8f2e4 0%, #efe6d2 60%, #e6dac2 100%);
  border-radius: 0.4vmin;
  box-shadow: inset 0 0 2.2vmin rgba(130,95,45,.14), 0 1vmin 3vmin rgba(0,0,0,.35);
  transition: transform 1.5s ease-out;
}
```

The `locken.postMessage('flying' | 'done')` lines only tell the native app when to move on. Remove them in a web project.

---

## Part B: Native SwiftUI components (Locken Test App)

These need macOS 26 (Liquid Glass) unless noted. `SquircleTokens` and `Font.appFont` are Locken's tokens (item 21). Replace them with your own colors and fonts if you don't copy the tokens.

### 9. BorderGlow (React Bits port)

A button surface with a dark fill, a 1px colored mesh border and an outer glow that appear around the pointer's angle as it nears the edge. Copy `BorderGlowModifier` and `BorderGlowMesh` from `LockenTestApp/DesignSystem/SquircleTokens.swift`.

```swift
Button("Start Focus") { start() }
    .padding(.horizontal, 20).padding(.vertical, 12)
    .borderGlowButton(accent: SquircleTokens.accentColor(for: "focus"), isProminent: true)
```

Configured values (from React Bits' BorderGlow props):

| Setting | Value |
|---|---|
| edgeSensitivity | 30 |
| backgroundColor | `#120F17` |
| borderRadius | 28 (capped at half the height) |
| glowRadius | 40 |
| glowIntensity | 1.0 |
| coneSpread | 25 |
| fill opacity | 0.5 |
| glowColor | the button's accent (the tab's colour) lifted 35% toward white |
| accent tint | 30% for prominent buttons, 8% otherwise |
| gradient colors | three shades of the accent (30% lighter, the accent, 25% darker), so the border and fill glow in the tab's colour only |

### 10. MagicBento border glow (React Bits port)

Only the border glow from React Bits' MagicBento: a 6pt ring lit by a 300pt radial gradient at the pointer, in the tab's accent. Nothing moves on hover. Copy `LockenTestApp/DesignSystem/MagicBento.swift`.

```swift
// Once, on the root view (tracks the pointer for the whole window):
RootView()
    .magicBentoSection(glowColor: SquircleTokens.accentColor(for: selectedTab))

// On each card:
CardContent()
    .padding(24)
    .magicBentoCard(cornerRadius: 22)
```

Settings: `spotlightRadius = 300`. Full strength within 150pt of a card, fading out by 225pt.

### 11. Liquid glass surfaces

```swift
public extension View {
    /// The outer frame around each tab's content.
    func liquidGlassCard(cornerRadius: CGFloat = 26) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(shape.fill(Color(red: 0.10, green: 0.10, blue: 0.12).opacity(0.6)))   // calm scrim under the glass
            .glassEffect(.regular.tint(Color(red: 217/255, green: 119/255, blue: 6/255).opacity(0.06)), in: shape)
    }

    /// Main cards.
    func luxuryObsidianCard(cornerRadius: CGFloat = 22) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(shape.fill(Color(red: 0.17, green: 0.17, blue: 0.19).opacity(0.6)))
            .glassEffect(.regular.tint(Color.white.opacity(0.04)), in: shape)
            .magicBentoCard(cornerRadius: cornerRadius)   // remove if you don't use item 10
    }

    /// Nested rows and smaller cards.
    func innerObsidianCard(cornerRadius: CGFloat = 16) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(shape.fill(Color(red: 0.17, green: 0.17, blue: 0.19).opacity(0.6)))
            .glassEffect(.regular.tint(Color.white.opacity(0.05)), in: shape)
            .magicBentoCard(cornerRadius: cornerRadius)
    }

    /// An accent-tinted glass box. No `.interactive()`: the surrounding Button owns taps.
    func glassBox(accent: Color, cornerRadius: CGFloat, tintOpacity: Double = 0.16) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(ZStack {
                shape.fill(Color(red: 0.17, green: 0.17, blue: 0.19).opacity(0.6))
                shape.fill(accent.opacity(tintOpacity))
            })
            .glassEffect(.regular, in: shape)
    }
}
```

Why the scrim: Liquid Glass renders much brighter in the key window than in an inactive one. The 60% dark layer keeps every surface at the calmer inactive look.

### 12. Glass pill (sliding sidebar selection)

```swift
public extension View {
    /// Lens-edge rim light: bright on two opposite corners, faint between.
    func glassRimLight(cornerRadius: CGFloat) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(stops: [
                        .init(color: .white.opacity(0.42), location: 0),
                        .init(color: .clear, location: 0.22),
                        .init(color: .white.opacity(0.08), location: 0.45),
                        .init(color: .white.opacity(0.08), location: 0.60),
                        .init(color: .clear, location: 0.88),
                        .init(color: .white.opacity(0.42), location: 1),
                    ], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        )
    }
}

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
```

Making it slide between items:

```swift
struct Sidebar: View {
    @Namespace private var sidebarPill
    @State private var selected = "focus"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 6) {
            ForEach(["dashboard", "focus", "calendar"], id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { selected = tab }
                } label: {
                    Text(tab.capitalized)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background {
                            if selected == tab {
                                GlassPill(cornerRadius: 10)
                                    .matchedGeometryEffect(id: "sidebar-selection", in: sidebarPill)
                                    .transaction { if reduceMotion { $0.animation = nil } }
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
```

### 13. Glass switch

A 44×24 track with a 30pt glass knob that overhangs it, widens to 36pt while pressed and springs across with a slight overshoot. VoiceOver still sees an ordinary switch. This is the main app's version (tint defaults to purple):

```swift
struct GlassSwitchToggleStyle: ToggleStyle {
    var tint: Color? = nil
    func makeBody(configuration: Configuration) -> some View {
        GlassSwitch(configuration: configuration, tint: tint)
    }
}

private struct GlassSwitch: View {
    let configuration: ToggleStyleConfiguration
    let tint: Color?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 8) {
            configuration.label
            Button { configuration.isOn.toggle() } label: { EmptyView() }
                .buttonStyle(GlassSwitchKnobStyle(isOn: configuration.isOn, tint: tint ?? Color.purple, reduceMotion: reduceMotion))
        }
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
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
                .fill(RadialGradient(stops: [
                    .init(color: .white.opacity(0.97), location: 0),
                    .init(color: .white.opacity(0.80), location: 0.55),
                    .init(color: .white.opacity(0.62), location: 1),
                ], center: UnitPoint(x: 0.3, y: 0.2), startRadius: 0, endRadius: 32))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.7), lineWidth: 1))
                .overlay(Capsule().strokeBorder(LinearGradient(colors: [.clear, .black.opacity(0.10)], startPoint: .top, endPoint: .bottom), lineWidth: 2))
                .shadow(color: .black.opacity(0.30), radius: 9, y: 7)
                .frame(width: pressed ? 36 : 30, height: 30)
                .offset(x: isOn ? 3 : -3)
        }
        .frame(width: 44, height: 24)
        .contentShape(Capsule())
        .animation(spring, value: isOn)
        .animation(spring, value: pressed)
    }
}

// Use:
Toggle("Remind me", isOn: $remind).toggleStyle(GlassSwitchToggleStyle(tint: .purple))
```

### 14. Glass rim light

`glassRimLight(cornerRadius:)` is defined in item 12. Add it to any glass control: `.glassBox(...).glassRimLight(cornerRadius: 16)`.

### 15. TextGenerateEffect (Aceternity UI port)

Each word fades in from a 10pt blur, 0.2 s apart, over 0.5 s. With Reduce Motion it appears at once.

```swift
public struct TextGenerateEffect: View {
    private let text: String
    @State private var isShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ text: String) { self.text = text }

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

// Use (Locken pairs it with the cursive title font):
TextGenerateEffect("Workspace Intelligence").font(.custom("Snell Roundhand", size: 30))
```

### 16. Notch check-in drop-down

A black panel shaped like the notch, with concave "ears" at the top and rounded bottom corners. It springs out of the hardware notch, takes keyboard focus without activating the app, and tucks back in. Copy all of `LockenTestApp/Services/CheckInWindowManager.swift`:

- `CheckInPanel`: borderless, non-activating `NSPanel` at `.screenSaver` level, on all Spaces, with `canBecomeKey` overridden
- `CheckInWindowManager`: notch geometry from `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` / `safeAreaInsets.top`
- `NotchShape` and `CheckInPromptView`

The shape:

```swift
struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set { topCornerRadius = newValue.first; bottomCornerRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let top = topCornerRadius, bottom = bottomCornerRadius
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
```

Configured values:

| Setting | Value |
|---|---|
| Shape width | 440pt |
| Shape height | notch height + 146pt |
| Shadow margin | 28 × 36pt (shadow drawn by SwiftUI; the panel's own shadow is off) |
| Ears | 14pt open, 6pt tucked |
| Bottom corners | 26pt open, 10pt tucked |
| Grow animation | `.spring(response: 0.42, dampingFraction: 0.8)`; content fades in 0.12 s later; `.easeOut(0.15)` with Reduce Motion |
| Close | shrink back, then `orderOut` after 0.45 s |
| Screens without a notch | 180pt wide, menu-bar height |

### 17. Small helpers

```swift
extension View {
    /// A secondary action next to a main button: plain text, so each screen has one clear primary button.
    func quietAction() -> some View {
        self
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white.opacity(0.6))
            .padding(.horizontal, 10).padding(.vertical, 10)
            .contentShape(Rectangle())
    }

    /// A border that traces itself around a container to confirm an action.
    func borderTraceConfirm(active: Bool, color: Color = .green, cornerRadius: CGFloat = 16) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .trim(from: 0, to: active ? 1 : 0)
                .stroke(color, lineWidth: 1.5)
                .opacity(active ? 0.9 : 0)
                .animation(active ? .easeOut(duration: 0.55) : .easeOut(duration: 0.25), value: active)
                .allowsHitTesting(false)
        )
    }

    /// Fades and lifts content in as it scrolls into view.
    func scrollReveal() -> some View {
        scrollTransition { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0)
                .scaleEffect(phase.isIdentity ? 1 : 0.97)
                .offset(y: phase.isIdentity ? 0 : (phase.value < 0 ? -14 : 14))
        }
    }
}
```

### 18. revealWhenLoaded

Keeps a view at opacity 0 until everything under it that loads asynchronously (web views, 3D models) reports ready, then fades it all in together: 0.35 s ease-out, never waiting more than 1.2 s. Copy `LockenTestApp/DesignSystem/AssetLoadGate.swift`, then use `PageView().revealWhenLoaded()`. Web views register with the gate in `ReactBitsWebView.swift`.

### 19. GhostFibers background

A `Canvas` in a `TimelineView` drawing slow-moving fibre lines in the tab's glow color. It pauses with Reduce Motion. It's the `GhostFibersBackgroundView` struct at the bottom of `LockenTestApp/Views/MainContentView.swift`. Settings: `lineColor` white, `glowColor` per tab, `layers` 5.

### 20. Brain model

A SceneKit view that loads `LockenTestApp/Resources/Models/HumanBrain.usdz` and holds still with Reduce Motion. Copy `LockenTestApp/Views/BrainModelSceneView.swift` and the model. The model's license isn't recorded yet (see `CREDITS.md`).

### 21. Design tokens

From `SquircleTokens` in `LockenTestApp/DesignSystem/SquircleTokens.swift`:

| Token | Value |
|---|---|
| Radii | micro 8, small 12, medium 16, large 22, XL 26 |
| obsidianBase | `#0B0B0F` |
| obsidianSurface | `#12131A` |
| obsidianCard | `#171822` |
| titaniumChassis | `#232630` |
| logoViolet | rgb(0.55, 0.20, 0.90) |
| logoMagenta | rgb(0.88, 0.15, 0.45) |
| restrainedRose | `#BE123C` |
| mintAccent | `#10B981` |
| smokedAmber | `#F59E0B` |
| royalPlum | `#8B5CF6` |
| vividNavy | `#3352C7` |
| titaniumPlatinum | `#94A3B8` |
| Text | primary white, secondary white 72%, muted white 45% (use at least 55% on cards for readable contrast) |

Accent per tab (`accentColor(for:)`):

| Tab | Accent |
|---|---|
| Dashboard | logoViolet |
| Focus | restrainedRose |
| Calendar | mintAccent |
| Habits | smokedAmber |
| Notes | royalPlum |
| Settings | titaniumPlatinum |
| Analytics (usage) | sky `#38BDF8` |
| Anything else | logoViolet (the Intelligence tab was removed on 2026-10-16) |

Font: `Font.appFont(size:weight:)` draws Doto, the main face (variable; weight 800, or 900 for semibold and heavier; ROND 100), for text at 15 pt and above and for 13–14 pt text at medium weight or heavier, drawn at 15 pt or more and snapped to multiples of 5 pt; Montserrat, the secondary face (Regular / Medium / SemiBold / Bold), for regular text under 15 pt and anything under 13 pt, at its own size. Both are registered at launch with `CTFontManagerRegisterFontsForURL`. The in-app web pages load the same files from `Resources/Web/fonts/`: Doto for the JellyRadio labels and CodeSlots digits, Montserrat for the ProfileCard (drawn at about half size). `UIAppFonts` doesn't work on macOS. Cursive titles use Snell Roundhand.

---

### 22. LogoTraceLoader (every loading indicator)

`LockenTestApp/DesignSystem/LogoTraceLoader.swift`. Replaces `ProgressView()` everywhere in the app. A short stroke runs around the Locken padlock (geometry from `web/assets/locken-logo.svg`, one closed route: shackle, then body); when `loading` turns false the outline closes and the filled padlock fades in, then `onDone` runs once (timers back up the animations). Drawn in the current foreground color at a fixed size. Reduce Motion shows the filled logo at once.

```swift
LogoTraceLoader(size: 16, strokeWidth: 9)            // inline, where a small spinner was
LogoTraceLoader(size: 44, ariaLabel: "Opening Locken") // full-window wait
LogoTraceLoader(loading: isBusy, size: 28) { print("shown") }
```

### 23. SignatureText (the name on the dashboard)

`LockenTestApp/DesignSystem/SignatureText.swift`. Writes text like a signature: the glyph outlines of Snell Roundhand are stroked left to right (2.8 s, `timingCurve(0.2, 0.2, 0.8, 0.9)`, the animated-signature component's timing), then the letters fill in. It plays once per `playKey` per launch, so the greeting writes the person's name the first time the dashboard shows after sign-in; later it shows the finished name. Reduce Motion shows it at once.

```swift
SignatureText(text: "\(name)?", size: 30, delay: 0.25, playKey: userID)
    .foregroundColor(accent)
```

## Part C: Main app components (KissaFocus)

| # | Component | How to reuse |
|---|---|---|
| 22 | **ConcentricRectangle** | Copy `ConcentricRectangle.swift`. It's a nested bevelled container whose inner corner radius is `max(0, outerRadius - inset)`, plus `ConcentricButtonStyle`. Use: `ConcentricRectangle(outerRadius: 20, inset: 3.5, tint: .purple) { content }`. |
| 23 | **TiltedMusicCard** | Copy `TiltedMusicCardView.swift` (includes `MusicEqualizerView`). It's a native port of React Bits TiltedCard showing the current track, and needs `FocusMusicPlayer` (`KissaFocus/Services/Music/FocusMusicPlayer.swift`) or your own player state. |
| 24 | **Ferrofluid background** | Copy `FerrofluidBackgroundView.swift`. It's React Bits' Ferrofluid WebGL shader in a transparent `WKWebView`, with colors synced to the tab. |
| 25 | **RotatingText** | Copy `RotatingTextView.swift`. It's a React Bits RotatingText-style word cycler with spring physics. |
| 26 | **Spline 3D view** | Copy `Spline3DView.swift`. It's a `WKWebView` that loads a `prod.spline.design/.../scene.splinecode` scene; `SplinePresets` lists the scenes used. |
| 27 | **SceneKit scenes** | Copy `Glass3DSceneView.swift`. It contains `SceneKitView`, `ParallaxInteractiveSCNView` (tilts with the cursor) and the procedural scene builders. |
| 28 | **SquishButtonStyle** | In `Theme.swift`: `.buttonStyle(SquishButtonStyle())` gives a small press-down scale. |
| 12–14 | **Glass pill, glass switch, rim light** | Same code as Part B, in `Theme.swift`. |

---

## Moving components to another project

**React / Next.js project**
1. Copy the component's `.jsx` and `.css` from `LockenTestApp/WebComponents/src/` (and `public/` assets for ProfileCard and the avatar).
2. Install the packages listed in Part A.
3. Paste the configured JSX from this guide, and drop the `window.webkit` / `window.updateProps` bridge code.

**SwiftUI (macOS) project**
1. Copy the Swift snippets or files above.
2. Either copy `SquircleTokens.swift` too, or replace its colors and `Font.appFont` with your own.
3. Liquid Glass (`glassEffect`) needs macOS 26. Locken supports macOS 15, so it goes through `adaptiveGlass(tint:in:)`, which falls back to `.ultraThinMaterial` with a hairline rim on older systems.
4. To show a React component inside SwiftUI, copy `ReactBitsWebView.swift` and `WebComponents/build.mjs` and keep the bridge.

**Licenses** (details in `CREDITS.md`):
- React Bits components are MIT + Commons Clause, so you can't sell them as-is.
- Aceternity UI patterns are MIT.
- Every component above is either open source (see `CREDITS.md`) or Locken's own; the earlier AGPL avatar and the in-house cartoon mascot are both gone; the sign-in screen has no mascot or logo.

### 24. Commitment mode and the menu bar timer

`LockenTestApp/Views/CommitmentViews.swift`.

- **CommitmentGateView / CommitmentGateOverlay:** during a running session with commitment mode on, pausing, ending early, quitting Locken or turning off the Shield shows a "Stay with it?" card first. A ring counts down (10 s for a pause, 20 s for the rest). "Keep focusing" is the main button (Escape picks it); the stop button unlocks when the ring empties. Routed through `TestAppStateManager.requestStop(_:)`. Mac shutdown, logout and installing an update skip it (`AppQuit.isAllowed`).
- **CommitmentModeToggle:** the switch in Settings → Locken. On by default.
- **Surviving a force quit:** a running session is saved per account (`session-<user id>.json`, `TestAppStateManager.saveRunningSession`). If Locken is force-quit, crashes, is updated or the Mac restarts, the next launch picks the session up with the time left and the Shield starts again. Quitting the normal way, pausing or ending deletes it (`AppQuit.reason`).
- **MenuBarTimerLabel / MenuBarTimerPanel:** the `MenuBarExtra` (window style). The menu bar shows a lock and the time left (an open lock while paused). The panel shows the goal, time, progress, Pause/Resume and End (both through commitment mode), or "Start a session", plus Open Locken and Quit.

### 29. Strands (React Bits)

`LockenTestApp/WebComponents/src/Strands.jsx` + `Strands.css`, page `strands-entry.jsx`, built to `Resources/Web/strands.html`; shown by `ReactBitsWebView(page: .strands)` as the Assistant tab's hero (320 pt tall, full width). Installed from the React Bits registry (`https://reactbits.dev/r/Strands-JS-CSS.json`), source unmodified.

- **Settings Locken uses:** `glass={false}`, `colors=["#d6213f","#f0503a","#ff8a5c","#fff3ec","#ff6f9c","#b0306a","#4a1236"]` (the Assistant tab's coral `#FB7158` family: warm sheet tip, edge, body, white-hot core, then a pink second sheet and a deep wine), `speed=1.6`, `amplitude=1`, `waviness=1.4`, `energy=0.3`, `spread=1`, `intensity=0.9`, `scale=1`. The first version used `amplitude=1.65`, `spread=2.2`, `waviness=2.5` and violet-and-white colors; at that size the ribbons ran off the top and bottom of the box and showed as a smeared rectangle, and violet clashed with the maroon tab.
- **Shape:** the strands sit in a centred 2:1 box (`.strands-stage`, `build.mjs`) whose edges fade out with an elliptical mask. In a wider box the ribbons are cropped at the top and bottom edges.
- **Left off on purpose:** `interactive` and `clickPulse` are `false`. The component leans toward the pointer and pulses on click; Locken's design rules allow no cursor tilt or click ripples.
- **It shows what the assistant is doing** (`AssistantAurora` in `AssistantView.swift`, props read in `strands-entry.jsx`): idle is calm at the base energy; thinking is `level=0.45`; listening is `level` = the microphone loudness from `MicLevelMeter`, in steps of 0.05; speaking is `listening` (the component's own speech-like motion), so the strands swell and pulse while Locken talks.
- **Reduce Motion:** the component holds still by itself (it reads `prefers-reduced-motion`). The page is dimmed to 55% while the assistant is idle and full while it listens or talks.

### 30. GradualBlur (React Bits port)

`LockenTestApp/DesignSystem/GradualBlur.swift`. `.gradualBlurBottom(height: 96)` on a ScrollView adds a band along its bottom edge where the page blurs more and more toward the edge, with the original's tint `rgba(18, 15, 23, 0.6)`. It fades out when there's nothing left to scroll to (the original's `autoHide`, from `onScrollGeometryChange`). Used on every page: Home, Focus (the session page and the setup page, whose scroll also drives the hero), Assistant, Calendar, Habits, Analytics, Notes, Settings and the Admin console (square corners there, `cornerRadius: 0`, since it runs to the window's edge). Windows has it on every page too: one scroller (`.pages`) holds them all.

- **Not a line-for-line port:** the original stacks CSS backdrop blurs with growing radii. Here one frosted layer (`NSVisualEffectView`, `.hudWindow`, within the window) has its opacity ramped with the original's exponential curve, so `strength` and `layers` don't exist.
- **Reduce Transparency:** only the dark fade shows, no frosted layer.

### 31. GlassIcons (React Bits)

`LockenTestApp/WebComponents/src/GlassIcons.jsx` + `GlassIcons.css`, page `glassicons-entry.jsx`, built to `Resources/Web/glassicons.html`; shown by `ReactBitsWebView(page: .glassIcons)` in `SidebarRail` (`MainContentView.swift`). Fetched from the React Bits repo (`src/content/Components/GlassIcons`). Two small changes, marked `Locken` in `GlassIcons.jsx`: an item can have `aligned: true`, and its colour plate then straightens behind the glass (no tilt, no offset), easing in and out like the hover (the open page's button uses it, so its colour sits square inside the ring); and a `closing` prop plays the intro backwards, last button first (0.04 s apart), so the tiles close. Expanding the sidebar sets `closing`, waits 0.6 s (`SidebarRail.closeDuration`, 600 ms in `main.js`), then widens it; with Reduce Motion it widens at once. On Windows the same bundle runs in an iframe (`windows/public/glassicons/`, with a `bridge.js` that turns its messages into `postMessage`) inside the sidebar.

- **What it is for:** the sidebar collapses (with the morphing toggle button, below; remembered between launches) into a 96 pt rail with one glass button per page: New, Focus, Assistant (Mac), Calendar (Mac), Habits, Analytics, Notes, Settings and, for the owner, Admin (Mac). Each button has its own muted, dark colour (one palette in `glassicons-entry.jsx`, the same saturation and lightness on every button and hues 30 degrees or more apart, so they sit quietly on the dark app but are easy to tell apart: rose, violet, coral, mint, gold, steel blue, magenta, slate for Settings, indigo for Admin; Notes is magenta and not its page's plum because plum is too close to Focus's violet). The open page has a thin white ring, and its colour plate straightens to sit square inside it while the others stay tilted, and the name shows under a button on hover. The glass is dark and mostly opaque (near-black tint, low shine) so the white symbols stay easy to read. Collapsed, the profile card is hidden, so Settings gets its own button. On the Mac, Settings and Admin are kept apart at the bottom of the rail, above the collapse button (a second web view of the same page, `SidebarRail.group`); the other pages stay at the top. Windows still has one column.
- **Settings Locken uses:** the ones chosen for it: `columns=1`, `roundness=0.6`, `refraction=0.8`, `bevel=0.6`, `dispersion=0`, `frost=0.2`, `shine=0.5`, `tint="#08080c"`, `tintOpacity=0.4`, `iconColor="#ffffff"`, `plate="tilt"`, `tilt=30`, `spread=0.5`, `hover="press"`, `parallax=1`, `labels="hover"`, `intro`, `theme="dark"`. Only `size` (40) and `gap` (30, down to 18 when there are many buttons or little height) differ from the example, so eight to nine buttons fit the window. Icons are HugeIcons.
- **Talks to the app:** the app sends `{ items, value, size, gap }` (`window.updateProps`); the page posts `select:<id>` for a press and `size:<w>x<h>`.
- **Design rules:** the example's `parallax` and `press` were used as chosen; Locken's rule against movement on hover is otherwise unchanged.
- **Reduce Motion:** the component reads `prefers-reduced-motion`; the sidebar's own width change has no animation then.

**Collapse and expand motion (Mac).** The sidebar's width follows a critically damped spring (response 0.45) while the full sidebar slides out to the left and fades and the rail slides in from the left (`.move(edge: .leading)` with opacity); expanding is the reverse, after the tiles have closed. One logo (`MainContentView.sidebarLogo`) lives outside both sidebars and moves and resizes with them (32 pt at the header's corner, 56 pt centred over the rail). Reduce Motion: no animation.

**Focus mode sound (Mac).** `FocusSound` (in `TestAppStateManager.swift`) plays when the timer goes from stopped to running, a start or a resume: about 1.4 s, synthesised (no audio file), a band-pass-filtered swell of air rising from 350 Hz to 3.5 kHz into two chime notes (E5, then A5) and a short echo tail, peak 0.5 at volume 0.6, following the Mac's output volume and mute. Like AirPods' noise cancellation turning on.

**The toggle button (`SidebarToggleIcon`).** One button for both directions, from the icon the maintainer supplied (a rounded square in the text colour with a panel cut out of its left side; the panel is wide while the sidebar is open and narrow once it is collapsed). It floats over the sidebar: in the header's corner when open, sliding to the bottom of the rail when collapsed, while the panel morphs over 0.35 s (`cubic-bezier(0.4, 0, 0.2, 1)`). Mac: native SwiftUI (`BlendablePath` parses the two SVG paths and `SidebarPanelShape` blends their points; checked in a scratch harness: narrow panel's right edge at 10, wide at 14, halfway at 12). Windows: inline SVG with a CSS `d: path(...)` transition on `.toggle-panel` (`windows/src/style.css`). Reduce Motion: no animation. The icon's original is a React `motion` component; it is not a dependency here, and its original author isn't credited yet because we don't know it.

### 32. LogoLoop (React Bits)

`web/src/components/LogoLoop.jsx` + `LogoLoop.css`, mounted by `web/src/site/connectors.jsx` into `#connectors` in the "Works with" section (the static row stays inside it for visitors without JavaScript). Fetched from the React Bits repo (`src/content/Animations/LogoLoop`), source unmodified.

- **Settings Locken uses:** two rows, `direction="left"` and `"right"`, `speed=38`, `logoHeight=44`, `gap=64`, `labels="below"`, `hoverSpeed=0` (pauses under the pointer). `scaleOnHover` is left off: Locken's rules allow no scaling on hover.
- **What is listed:** only real connections. Canvas, Calendar, Reminders, Notes, Safari, Chrome, Arc, Brave, Microsoft Edge, Comet, Spotify, Apple Music, YouTube, YouTube Music, SoundCloud, Claude, ChatGPT, Gemini and Google sign-in. Google Classroom is added when its sign-in is switched on. Marks come from Simple Icons (through `react-icons`) and the site's own `/logos`; services without a mark there (Microsoft Edge, Comet, ChatGPT) show only their name. A note under the rows says the logos belong to their owners and that some connections are Mac only.
- **A trap:** the loop's column must be `minmax(0, 1fr)` (`.connectors` in `site.css`). With a plain `auto` column the grid grew to the scrolling track's width and the loop kept adding copies until React stopped with error #185.

### 33. Check-in aurora

A soft aurora along the top of the screen while the check-in drops down: indigo, blue, cyan and green glows that drift slowly and fade to nothing a third of the way down.

- **Mac:** `CheckInAuroraPanel` (a second borderless panel the width of the screen, ignoring mouse and keyboard, just under the prompt) and `CheckInAuroraView` (a blurred SwiftUI `Canvas` at 30 fps, masked to fade downward). It fades in with the prompt and out as the prompt tucks away, and the glows lean slightly toward the pointer. With Reduce Motion on it holds still and appears at once.
- **Windows:** `open_aurora` in `lib.rs` opens a transparent, click-through, always-on-top window across the top of the monitor under the check-in; `aurora.html` + `src/aurora.css`. Drift only (the window can't see the pointer). The check-in's answer fades it out first (`aurora-out`); any other way of closing the check-in closes it too.

## Performance notes: the Focus page (Mac, 2026-10-23)

Nothing was removed from the page; these only cut work that wasn't visible.

- **Scroll smoothing** (`FocusSplitDriver`) steps once per frame the screen draws, from a display link. It was a fixed 120 Hz timer, which ran the page's update twice per frame on a 60 Hz screen.
- **Clock dial** (`FocusDial`): the sixty ticks and the faint ring are `FocusDialFace`, an `Equatable` view drawn into one bitmap (`drawingGroup`), so each second only the marker and the shrinking ring redraw. The ring is animated (`.linear(1)`) only when it moves 1.5 pt or more a second (sessions shorter than about 10 minutes); on a long session it moves a fraction of a point a second, and the animation kept the whole page redrawing at the screen's frame rate.
- **Liquid-glass digits** (`shared/fluidglass-time.js`, used by both apps) draw every other frame, with twice the simulation steps, while nothing is happening to them, and every frame while the pointer is near them or the digits are changing (for 0.9 s after the pointer leaves). The same simulated time passes, so the motion looks the same, but the page hands the compositor half as many frames. Nothing is drawn while the digits are scrolled out of view.
- **Pointer forwarding** to a page behind the scroll view (`ReactBitsWebView.forward`): the first move goes at once, then at most one message per frame with the latest position, instead of one per mouse event.
- **Card border glow** (`MagicBentoBorderGlow`): a card the pointer is out of reach of draws nothing, instead of an invisible gradient border on every mouse move.
- **Assistant voice model** (`VoiceAssistant.voiceEngine`, `prepareVoice`, `play`): the model takes 5 to 10 seconds to load and warm up, and the first audio of a reply only arrives after a whole chunk is made. It is loaded off the main thread (a spoken reply used to load it on the main thread, freezing the window), and loading starts early: when the Assistant tab opens, when a question is typed, and when listening starts. A reply is spoken a sentence at a time (`VoiceAssistant.sentences`, a word or two joins its neighbour) so the first sentence starts as soon as it is made and the next is made while it plays; measured with the real model: first audio of a three-sentence reply after about 1.4 s instead of about 6 s. It was briefly let go after four idle minutes (build 56), which made every conversation after a pause start with a cold load and silence of 5 to 10 seconds; that was removed.
- **Always-on timers:** the Assistant's hotkey check (30 times a second, all day) no longer creates a task per tick and only asks how long ago the last key press or click was while the hold key is down; the now-playing poll no longer announces the growing listening totals every 2 seconds (nothing shows them), only when they are saved.
