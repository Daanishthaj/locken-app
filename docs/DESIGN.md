# Locken design rules

Read this before any UI work on the Locken apps or website. It follows the ranking for keeping AI-made UI from looking vibe coded:

1. **S, say what you hate:** the rules prompt below.
2. **A, a design file:** the tokens and system in section 2.
3. **B, screenshot a site:** references in section 3.
4. **C, design skills:** section 4.
5. **D, switch styles:** last, and only when the maintainer asks.

## 1. The rules prompt (paste at the top of every design chat)

Copy this block into the start of any design request, then add the task underneath.

```
You are designing for Locken, a free macOS focus app for students (13+), built in SwiftUI for macOS 15 and later (Liquid Glass on macOS 26),
with a Vite website. The look is already decided: dark obsidian glass, Apple Liquid Glass on surfaces,
a purple brand with one accent per tab, Doto (round dots) as the main face for headings, controls and navigation, Montserrat as the secondary face for body text and small print, Snell Roundhand cursive for page titles,
and the components listed in COMPONENTS.md. Keep that look. Change only what I ask for.

Never do any of these:
- Move, scale, tilt or bounce anything on hover. Hover feedback is a subtle border glow only.
- Put a filled button next to an outlined button. Each screen has one main button; secondary actions
  are plain text (quietAction).
- Add section labels like "WORKSPACE", status pills like a red "ACTIVE", or badges nobody needs.
- Use decode, scramble or typewriter text effects. Titles use TextGenerateEffect (blur-in words).
- Add sparkle effects: stars, spotlights, cursor tilt, magnetism, click ripples, glow blobs.
- Make things that should feel physical look flat: paper should look like paper, not pure white.
- Put a black box behind overlays or transitions; they float on the app's own background.
- Make the hero element small. The 3D orb, papers and heroes are meant to be big.
- Write jargon ("NSPanel at statusBar window level"). Say what it does for the student in plain words.
- Show fake features, fake data, sample notes, placeholder goals or demo numbers as if they were real.
- Invent testimonials, brand logos, statistics, prices or company addresses.
- Use gradient-filled headline text, emoji as icons, three identical feature cards, or generic copy like
  "Unlock your potential", "Supercharge", "Seamless" or "Revolutionize".
- Use Inter or a system default font where Doto belongs.
- Ask for Full Disk Access or anything that looks suspicious to users.
- Replace a component I chose (JellyRadio, 3D Orb, DitherVeil, ProfileCard, BorderGlow, CodeSlots,
  the papers transition) with a different one.

Always:
- Use JellyRadio for single text choices and the glass switch for on/off. Choosing an app uses app icon
  tiles, so it never looks like a JellyRadio on the same card.
- Keep text at least 55% white on dark cards (4.5:1 contrast) and respect Reduce Motion and Reduce
  Transparency.
- Give every icon-only control an accessibility label.
- Show real empty states instead of sample content.
- Build it, run it, and check it before saying it's done.

Task: [describe the screen or change]
What I don't like about it now: [your own tells for this task]
Reference: [attach a screenshot or name a site]
```

### Tells the maintainer has already called out

Each of these came up while building Locken and has been fixed. Keep them fixed.

| Tell | Fix that stuck |
|---|---|
| Cards tilting, magnetising and sparkling on hover | MagicBento reduced to its border glow only |
| Filled + outlined button pairs | One BorderGlow button per screen; `quietAction()` for the rest |
| "WORKSPACE" label and red "ACTIVE" pill in the sidebar | Removed; the Focus item shows a small accent dot and time left |
| Decode/scramble title reveal | TextGenerateEffect |
| Papers too small, on a black background, pure white | Big notebook-paper sheets on a transparent background |
| A "Fly" button left in the transition | Removed |
| Hero orb too small | Fills the 460pt stage |
| Hard-coded sample notes | Real notes and Apple Reminders, empty state when there are none |
| Jargon on the notch card | Plain description of what the check-in does |
| Fake toggles (Google Calendar, Notion, Drive, "hardware enclave") | Removed |
| Two pickers on one card looking the same (goal source and workspace app, both JellyRadio pills) | Workspace app is a row of tiles with each app's real macOS icon and an accent ring on the chosen one (approved 2026-10-11). JellyRadio stays for text choices like Canvas Assignment / My Own Goal. Different kinds of choice on one card should look different. |

## 2. The design file

- **Components and their exact settings:** [COMPONENTS.md](../COMPONENTS.md).
- **Colors and radii:** `SquircleTokens` in `LockenTestApp/DesignSystem/SquircleTokens.swift`.
  - Corner radii: 8 / 12 / 16 / 22 / 26.
  - Backgrounds: `#0B0B0F` base, `#12131A` surface, `#171822` card.
  - Tab accents:

    | Tab | Accent |
    |---|---|
    | Dashboard | rose `#BE123C` |
    | Focus | violet (swapped with Dashboard on 2026-10-14; sign-in keeps violet) |
    | Calendar | mint `#10B981` |
    | Habits | amber `#F59E0B` |
    | Notes | plum `#8B5CF6` |
    | Settings | platinum `#94A3B8` |
    | Analytics | sky `#38BDF8` |

- **Type:** `Font.appFont(size:weight:)` pairs two faces: Doto, the main one (weight 800, 900 for bold, `ROND` 100), for headings, titles, buttons, navigation and numbers (15 pt and up, or 13–14 pt at medium weight or heavier), drawn at 15 pt or more so its dots stay sharp; Montserrat, the secondary one, for descriptions, body text and small print (regular text under 15 pt, anything under 13 pt). The website uses Doto in white. Snell Roundhand for page titles.
- **Surfaces:** Liquid Glass (`glassEffect`) over a 60% dark scrim, so the key window doesn't glare. Controls get the glass pill, glass switch and rim light (`liquid-glass-techniques`).
- **Motion:**
  - Springs for movement (`response 0.3–0.45`, `damping 0.6–0.8`), ease-out for fades, nothing over 0.5 s in normal UI.
  - Every animation has a Reduce Motion path.
  - The papers transition and 3D orb are the only "show" moments.
- **Layout:**
  - One clear main action per screen.
  - Cards are solid glass with readable text.
  - Heroes are large; empty states are honest.

## 3. References (screenshot a site)

When asking for a new screen or a redesign, attach a screenshot of something you like and say what to take from it (the spacing, the type, the motion), not "make it like this".

Sources already chosen for Locken:
- React Bits (ElectricLogo, DitherVeil, ProfileCard, JellyRadio, CodeSlots, BorderGlow, MagicBento)
- Supavec (3D Orb, Apache-2.0)
- Aceternity UI (Text Generate Effect)
- Apple Liquid Glass
- The Local Flow site's liquid glass techniques

Save reference screenshots in `docs/design-references/` with a one-line note of what to take from each.

## 4. Design skills to load

| Skill | When |
|---|---|
| `liquid-glass-techniques` | Glass surfaces, pills, switches, rim light (web and SwiftUI) |
| `ui-anti-slop-review` / `deslop` | Reviewing a screen for AI-template tells before calling it done |
| `macos-notch-ui` | Anything that drops from the notch |
| `apple-design`, `emil-design-eng` | Motion, springs, gestures |
| `macos-design-guidelines` | Native controls, settings, menus |
| `design-taste-frontend`, `high-end-visual-design` | Website sections |

## 5. Switching styles

Lowest priority. Don't swap Locken to a different preset style (brutalist, minimal, neon) to "freshen it up". Only change the overall style when the maintainer asks for it.
