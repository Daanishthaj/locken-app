# Credits and third-party licenses

Locken uses the open-source libraries, fonts and assets below. Each one keeps its own license. Only what actually ships is listed; dev-only tools and unused packages are left out.

## Libraries

| Package | Ships in | License |
|---|---|---|
| three | website, Mac app web views | MIT |
| gsap | website | GSAP Standard "No Charge" License |
| lenis | website | MIT |
| Draco 3D decoder (`web/public/draco/`) | website | Apache-2.0 (text in `web/public/draco/LICENSE`) |
| react, react-dom | Mac app web views | MIT |
| @react-three/fiber | Mac app web views | MIT |
| motion, framer-motion | Mac app web views | MIT |
| ogl | Mac app web views | Unlicense |
| @hugeicons/core-free-icons, @hugeicons/react | Mac app web views | MIT |
| KokoroCoreML (Jud/kokoro-coreml 0.11.2) and BARTG2P (Jud/swift-bart-g2p) | Mac app (Assistant voice) | Apache-2.0 |
| Kokoro-82M voice model and voices (hexgrad), downloaded on request from the kokoro-coreml release `models-2026-03-23` | Mac app (Assistant voice, not bundled) | Apache-2.0 |
| Tauri 2, @tauri-apps/api, tauri-plugin-opener | Windows app | Apache-2.0 or MIT |
| serde, serde_json, sysinfo, keyring | Windows app | MIT or Apache-2.0 |

## Fonts

| Font | Used in | License |
|---|---|---|
| Doto | Mac app (text 13 pt and up), Windows app, website | SIL Open Font License 1.1 |
| Montserrat | Mac app (text under 13 pt, profile card) | SIL Open Font License 1.1 |

## Icons and logos

| Asset | Source | License |
|---|---|---|
| Cursor, Google Chrome, Perplexity, Safari logos in the Mac app (`LockenTestApp/Resources/Web/logos/`) | Simple Icons | CC0 1.0 (the logos remain their owners' trademarks) |
| Apple Music, YouTube, YouTube Music, SoundCloud, Claude, Gemini, Google, Arc and Brave marks on the website's "Works with" rows (`react-icons`, MIT) | Simple Icons | CC0 1.0 (the logos remain their owners' trademarks; Locken isn't affiliated with or endorsed by them) |
| Icons on the collapsed sidebar buttons (`@hugeicons/core-free-icons`) | HugeIcons | MIT |
| Chrome, Safari, Spotify logos on the website (`web/public/logos/`) | the brands' public marks | Trademarks of their owners; used only to say which apps Locken works with (notice in the site footer and `web/public/licenses.txt`) |

## Components

| Component | Source | License |
|---|---|---|
| DitherVeil, ElectricLogo, ProfileCard, JellyRadio, CodeSlots, Strands, GlassIcons, LogoLoop, GradualBlur (ported to SwiftUI) and other effect components | React Bits | MIT + Commons Clause (free to use in a free app; the components themselves may not be sold) |
| Plasma ring (`LockenTestApp/WebComponents/src/originkit/ui/plasma-ring.tsx`) | OriginKit, installed with the official `originkit add` CLI (free component) | OriginKit's terms for components added to your own projects |
| Menu bar padlock (`LockenLogo.menuBarImage` in `LogoTraceLoader.swift`) | Locken's padlock logo; the sign-in mascot was removed on 2026-10-18 | Locken's own |

## 3D models and media

| Asset | Source | License |
|---|---|---|
| `web/public/models/locken-figure.glb` | Blender Studio "Human Base Meshes" (realistic male body), arms posed and exported by Locken | CC0 1.0 |
| Ring and padlock in the website's 3D scenes | Built in code (`web/src/site/main.js`) | Locken's own |
| Hero image in the Mac app's DitherVeil (`LockenTestApp/WebComponents/src/assets/dither-hero.jpg`) | Unsplash photo 1737071371043-761e02b1ef95 (images.unsplash.com, standard library) | Unsplash License (free, commercial use allowed, no attribution required) |

No PeachWeb template assets remain anywhere (removed on 2026-10-17). The public credits page is `docs/legal/ACKNOWLEDGEMENTS.md`, published as /credits on the website and shown in the apps.
