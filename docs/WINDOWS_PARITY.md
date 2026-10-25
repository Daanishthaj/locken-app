# Windows ↔ Mac parity checklist

Every screen, card and panel in the Mac app (`LockenTestApp/Views`), and where the Windows app (`windows/`) stands.
Goal: the Windows app looks and works exactly like the Mac app, except where a feature depends on something only
macOS has. Updated as each item is ported.

Legend: ✅ ported · 🟡 partly ported · ⬜ to port · 🪟 Windows equivalent needed (different system API) · 🍎 Mac-only (no Windows equivalent)

## App shell
| Mac | Windows |
|---|---|
| Sign-in (`LoginView`): wordmark, pills, fields, Forgot password, Google, legal | ✅ |
| Consent gate (`ConsentGateView`): age, Terms box, guardian box | ✅ same boxes as sign-up; agreement time set by the server |
| Startup padlock reveal (`LaunchRevealView`) | ✅ |
| Receipt welcome after sign-in (`ReceiptIntroView`) | ✅ |
| Sidebar: brand, nav, live session time | ✅ |
| Sidebar profile card with avatar and now playing (`SidebarProfileCard`) | ✅ same React Bits card; now playing and play/pause from the Windows media controls; monogram avatar |
| Background fibers, per-page colours | ✅ |
| Gradual blur along the bottom of scrolling pages (React Bits `GradualBlur`); fades out at the end of the page | ✅ `windows/src/gradual-blur.js` on the page scroller (every page). Mac: `GradualBlur.swift` on each tab's ScrollView except Focus (its scroll drives the hero) and Admin |
| Admin page (owner only) | ⬜ |
| Update banner and What's New (`UpdatesCard`, `WhatsNewSheet`) | 🪟 Windows has no auto-updater yet |
| Collapsible sidebar: a rail of React Bits GlassIcons buttons (`SidebarRail`), with one morphing toggle button (`SidebarToggleIcon`) | ✅ same bundle in an iframe (`windows/public/glassicons/`), remembered between launches; five page buttons at the top and Settings kept apart at the bottom, like the Mac's Settings and Admin (two iframes of the same page: `rail-icons` and `rail-icons-bottom`; no Assistant or Calendar page on Windows); the toggle's panel morphs with a CSS `d` transition |
| Open at login (`LaunchAtLoginCard`): starts Locken hidden at login so Analytics keeps measuring after a restart | ⬜ Mac only, by choice (2026-10-22). Windows Analytics is focus-session totals, counted from saved start and end times, so a hidden or minimized window loses nothing; closing the window quits the app, and a session that ended while Locken was closed isn't counted |
| Sidebar collapse and expand slide to and from the left (the pages slide out and fade while the width follows and the logo grows, then the rail slides in; unfolding is the reverse, after the tiles close), no animation with Reduce Motion | ✅ `collapsing`, `entering` and `expanding` classes in `style.css`, driven by `setSidebarCollapsed(…, { slide: true })` in `main.js`; checked in the browser preview (the end states and the nav sliding in; the preview pane slows animations, so the frames between were not all caught). The Mac moves one logo view that resizes with the sidebar; Windows resizes the brand's own image |
| Focus mode sound (`FocusSound`: airy rise into two rising chime notes when the timer starts or resumes) | ✅ `windows/src/focus-sound.js`, Web Audio (no file), played when a session starts and when it resumes (not when one is restored after a force quit); rendered offline in the preview: peak 0.30, ends at silence, same loudness shape as the Mac's. Not heard by me |
| Menu bar timer (`MenuBarTimerPanel`) | ✅ system tray icon: time left and goal in its tooltip, click or "Open Locken" brings the window back |

## New (dashboard)
| Mac | Windows |
|---|---|
| Greeting with signature-written name (`SignatureText`) | ✅ (written once per account each launch, after the intro) |
| Plasma ring with four glass boxes and stat cards | ✅ |
| Session setup: Canvas Assignment / My Own Goal pills | ✅ link row, searchable picker (Return picks the top match) |
| Dotted pill and tile text stays sharp: 15 px or larger, snapped to whole pixels; rows wrap instead of being cut off | ✅ (Windows tiles wrap onto a second row; Mac pills and app tiles wrap too) |
| Intelligent Rephrase (AI sparkle) | ✅ Claude, ChatGPT or Gemini key; requests and key stay in Rust |
| Where you'll work tiles with electric logo, lineup editor (`WorkspaceLineupOverlay`) | 🟡 tiles, electric logo, opens the app at start (Chrome, Edge, Comet, VS Code, Cursor, Word); lineup editor ✅ (Edit apps…: choose and order the tiles from ten apps, adding Firefox, Brave, Notion and Obsidian; Windows opens only apps from this fixed list) |
| How long slider | ✅ |
| Adaptive time toggle (`AdaptiveTimeToggle`) | ✅ (on New and the Focus timer card; same formula as the Mac) |

## Focus Session
| Mac | Windows |
|---|---|
| Focus Enclave header, Shield label, DitherVeil hero | ✅ (scroll split animation ⬜) |
| Timer card: Start / Pause / Resume / Reset | 🟡 Start on the idle card; Pause / Resume / Reset on the countdown |
| Your own goal card | ✅ |
| Canvas assignments card (`CanvasAssignmentsCard`) | ✅ link (token or calendar feed), refresh, unlink, time limit, mark as done, undo, show again |
| Session videos card (YouTube allowed videos) | ⬜ |
| Papers transition before a session (`SessionIntroView`) | ✅ same papers.html; timer and work app start when the stack settles (6 s safety) |
| Countdown view: dial, ring, Focused / Blocked / Ends | ✅ |
| Countdown digits as liquid glass that morph into the next number, with droplets under the pointer (`fluidglass` page) | ✅ one shared drawing file, `shared/fluidglass-time.js`, used by both apps; plain text if WebGL2 is missing, still when Reduce Motion is on |
| Countdown: Back, Pause / Resume, Reset, End | ✅ (Back not needed: the countdown is the Focus page) |
| Home ("New") is never shown while a session runs: opening the app or choosing it stays on Focus; paused or finished sessions can go Home again | ✅ (on the Mac the Focus page is only the timer dial on the left half and the steps on the right half, with no hero, while a session runs or is paused partway; Windows' Focus page shows the live countdown and steps) |
| Milestones card (`FocusMilestonesCard`, AI or planned steps) | 🟡 planned-by-time steps, tick, add, remove, steps in the celebration ✅; AI-written steps ✅ (planned by time without a key) |
| Pause reason page (`PauseReasonView`) | ✅ |
| Finish celebration (`SessionCelebrationView`) | ✅ padlock unlocks, Session complete / Finished early, real numbers, Start Another / Done |
| Commitment countdown | ✅ end (20 s), pause (10 s) and quit (20 s, when the window is closed mid-session; without Commitment mode, closing ends the session properly first); Shield off 🍎 (the Windows Shield has no off switch mid-session) |
| Check-in window every 30 min (`CheckInWindowManager`) | ✅ Mac layout: goal, time left, 0–100% slider, Check In, adaptive preview |
| Check-in aurora: a soft glow along the top of the screen while the check-in is open (`CheckInAuroraView`) | 🟡 a transparent click-through window under the check-in (`open_aurora`, `aurora.html`); drifts but doesn't lean toward the pointer, fades out when the answer is sent. The Rust side compiled and passed `cargo test` on the Windows CI runner (run 39914530311, 2026-10-23); not seen on a PC. Hidden in high contrast and with Windows' transparency effects off |
| Blocker: games and social apps | ✅ |
| Blocker: browser tabs (AppleScript) | 🪟 needs a browser extension or other approach on Windows |
| Focus / Do Not Disturb | 🪟 Windows Focus Assist |
| Force-quit: session resumes on next launch | ✅ goal, time left, steps and the Shield come back (paused sessions aren't kept, as on the Mac) |

## Habit Tracker
| Mac | Windows |
|---|---|
| Header, summary, New Habit, empty state | ✅ |
| Today ring and check pills | ✅ |
| This week: arrows, day columns, streak rows, day cells | ✅ |
| First-run setup (`HabitSetupCard`) | ✅ features and examples (Reminders 🪟) |
| Habit editor: symbol, schedule, amount goal, reminder, auto-track (`HabitEditorSheet`) | ✅ name, icon, category, schedule (every day, weekdays, pick days, times a week), amount goal, focus-session auto-track, edit and delete; streaks follow the schedule. Reminders 🪟 (needs Windows notifications); social-media auto-track 🪟 (needs usage tracking) |
| History panel per habit (`HabitDetailPanel`) | ✅ click a habit: streaks, last 30 days, 12-week grid; pencil edits |
| Habit features in Settings (`HabitFeaturesCard`) | ✅ Today view, Streaks & history, Auto-tracking |

## Analytics
| Mac | Windows |
|---|---|
| Screen usage by app and category (`UsageAnalyticsView`) | 🪟 foreground-app tracking on Windows |
| Week digest, AI digest (`WeekDigestPanel`, `AIDigestPanel`) | ✅ week digest on the Analytics page from Canvas due dates (no calendar events on Windows); reminders digest 🍎 (Apple Reminders) |
| Focus stats charts (`TestAnalyticsView`) | 🟡 |

## Notes & Reminders
| Mac | Windows |
|---|---|
| Notes list and editor (`TestProjectStudioView`) | ✅ Mac layout: count, New Note, inline editor with Delete / Done, "Edited …" times |
| Reminders (`RemindersDigestPanel`, `ReminderEditorSheet`) | 🍎 Apple Reminders |
| Apple Notes section | 🍎 |

## Calendar
| Mac | Windows |
|---|---|
| Calendar timeline (`TestCalendarTimelineView`, Apple Calendar) | 🍎 (an Outlook/Google calendar could replace it later) |

## Settings
| Mac | Windows |
|---|---|
| Commitment mode | ✅ |
| Intelligent Rephrase / AI key | ✅ on/off, 18+, what is shared, key in Credential Manager |
| Focus setup card (`FocusSetupCard`) | 🪟 Windows has no public API for apps to switch on Do Not Disturb: a Settings card explains how and opens Notification settings |
| Blocked apps, add app sheet (`BlockedAppsCard`, `AddBlockedAppSheet`) | ✅ (pick from running programs; browsers protected) |
| Habit features | ✅ |
| Updates | 🟡 version and a link to the latest download; auto-update 🪟 |
| Feedback card and sheet | ✅ |
| Account security: change password, sign out everywhere, your name (`AccountSecurityCard`) | ✅ |
| Two-factor authentication (`TwoFactorCard`) | ✅ set up with QR code or key, turn off; authenticator code asked at sign-in |
| Calendar connections | 🍎 |
| Google Classroom as a third way to link, next to Canvas (`GoogleClassroom.swift`, Settings › Connections and the Canvas link sheet) | ⬜ Mac only so far: Windows needs the same Google sign-in (system browser, PKCE) and Classroom calls in Rust, with the token in Credential Manager |
| Permissions card | 🪟 (Windows needs none of the Mac's permissions) |
| Data on this PC: download my data, delete (`LocalDataCard`) | ✅ |
| Legal: Terms, Privacy, Acceptable Use, Security, Credits (`LegalCard`, `LegalReaderView`) | ✅ in-app reader with a document switcher, bundled from `docs/legal` so it opens offline (`windows/src/legal.js`); the sign-in and sign-up Terms and Privacy links open it too |

## Windows quality checklist (audited 2026-10-21)
What the app does on Windows beyond matching the Mac screens. ✅ checked in a browser preview of the real UI (no Windows PC or Rust toolchain was available for this pass), 🟡 written but not testable there, ⬜ not done.

| Area | State |
|---|---|
| Keyboard shortcuts: the Mac menu's, with Ctrl (Ctrl+1 New, 2 Notes, 3 Habits, 4 Settings, 5 Focus, 7 Analytics, Ctrl+N start or pause, Ctrl+Shift+P pause, Ctrl+Shift+N new note); listed under Settings › Keyboard shortcuts; off while a dialog is open | ✅ |
| Accessible names: every visible control on every page has one (the Commitment mode switch was the one gap); one `main`, one `nav`, one `h1` per page, `lang`, page title | ✅ |
| Keyboard use: visible focus rings, no positive tab order; the legal reader traps Tab, closes on Escape and returns focus to what opened it | ✅ |
| Reduced motion | ✅ (transitions off; the signature, celebration and glass digits hold still) |
| Hover feedback is a glow, never movement (the sphere labels used to grow on hover) | ✅ |
| Reduced transparency (Windows "Transparency effects" off): solid surfaces, no blur, no gradual-blur band | 🟡 `prefers-reduced-transparency` rules in `style.css` |
| High contrast (forced colors): system colours, borders and focus ring, decorative effects hidden, plain timer text instead of glass digits | 🟡 `forced-colors` rules in `style.css` |
| Offline: notice at the bottom while the PC has no internet; sessions, notes and habits keep working | ✅ |
| Unexpected failures: an unhandled promise failure is noted (kind only, never contents) instead of a red console error | ✅ |
| Timer accuracy across sleep and wake: the countdown is computed from its end time, not counted down | ✅ (by reading the code; not slept on a PC) |
| Light theme or a cream theme | 🍎 neither app has one: both are dark only, as the Mac |
| Notion and Google Drive: backup, export or connection | 🍎 the Mac app has neither (the fake toggles were removed on 2026-10-07), so Windows has none; Download My Data covers export |
| Collapsed sidebar rail (React Bits GlassIcons): reachable by keyboard (Tab enters it, Enter opens the page, the ring follows), named controls, toggle button states | ✅ checked in the browser preview (2026-10-23) |
| Narrow windows: below 860 px the rail replaces the full sidebar and the toggle is hidden (the saved choice is kept and comes back when the window widens); the smallest window is 640 px wide (it was 420, where the page was cramped and the sphere clipped); no page scrolls sideways from 640 px up | ✅ in the preview at 640, 800, 900 and 1000 px; the 640 minimum is in `tauri.conf.json` and has not been run on a PC |
| High contrast: the sidebar toggle's cut-out uses system colours | 🟡 `forced-colors` rule, not testable in the preview |
| Floating focus widget (a compact always-on-top window with the timer, pause and task) | ⬜ needs a second Tauri window and its permissions (Rust side); the check-in popup and tray icon cover the need for now |
| Global hotkey, foreground-app tracking, Windows toasts, auto-update, installer testing at 125, 150 and 200% scaling and on several monitors | ⬜ need Rust and a Windows PC |

## Assistant (Mac only for now)
| Mac | Windows |
|---|---|
| Assistant tab (`AssistantView`, `VoiceAssistant`): talk to Locken, replies spoken with Kokoro | ⬜ nothing on Windows yet (no microphone, speech or voice code) |
| Microphone only when asked: off until the button or hotkey, off again when you leave the tab or switch app | ⬜ must be the same when it is ported |
| Stop or interrupt while it thinks or talks: hotkey, Escape or the button | ⬜ |
| Other media gets quieter while Locken talks (Spotify, Music, browser tabs); browser music in the sidebar card (Settings › Other media) | ⬜ comes with the Assistant. Windows already shows browser and YouTube Music audio in the card (it reads the Windows media controls); lowering other apps' volume would use Windows' per-app audio sessions (Rust) |
| Hotkey that works in any app (hold 0.4 s to talk; from another app one question, then it stops) | ⬜ Windows would need its own global key state (`GetAsyncKeyState`) |
| Assistant actions, each behind a confirm button: start a session, add a calendar event, add a Reminders item, tick off a focus step, mark a Canvas assignment done, tick off a habit, mark a reminder done or move it, save a note, open a page, play, pause or skip Spotify or Music, pause or resume a running session (through commitment mode); it also answers questions about focus time, screen time, streaks, habits and reminders from totals it is given | ⬜ comes with the Assistant (Windows has no Calendar or Reminders app to write to; the step and Canvas actions would map to its own milestones and checked-off list) |
| Strands hero (React Bits `Strands`, coral ribbons) on the Assistant page | ⬜ comes with the Assistant; `Strands.jsx` is plain WebGL2 and can be reused as is |
| History panel (`AssistantHistoryPanel`, `AssistantHistoryStore`): saved conversations by day (Today, Yesterday, dates), start time and title, open and continue, New chat, search, delete one or a day with confirmation; saved per account on the Mac | ⬜ comes with the Assistant itself; reuse the same file format (`assistant-history-<user id>.json`) |

## Progress log (Windows)

### 2026-10-23, bringing the Mac's changes of this day to Windows (uncommitted)
- **Rail: Settings at the bottom.** A second iframe of the same GlassIcons page holds Settings; the open page's ring follows between the two; checked by pressing Settings in the preview (page opens, ring moves).
- **AI retries and blank answers (`ai.rs`).** Same as the Mac: a blank answer from any provider is a failure (Gemini tries the next model, Claude and ChatGPT retry), a dropped connection moves Gemini on to the next model, Claude and ChatGPT retry once after a second on a dropped connection, a busy server (5xx, 408), a rate limit or a blank answer, and the empty-answer text no longer says "goal". Two new Rust tests (`blank_answers_are_failures_worth_retrying`, `retries_once_for_a_failure_that_usually_clears`); the whole `ai` test module passes (6 tests). **Rust can now be checked on the Mac:** `PATH="$HOME/.rustup/toolchains/stable-aarch64-apple-darwin/bin:$PATH" CARGO_TARGET_DIR=$HOME/LockenDeploy/cargo-target cargo test --lib` in `windows/src-tauri` compiles (for macOS) and runs the unit tests; Windows-only code (`cfg(windows)`) is still only compiled by the CI runner.
- **Darker glass rail** (copied bundle) and the **sidebar slide** and **focus sound** above.
- **Liquid-glass digits idle at half the frames** (shared `shared/fluidglass-time.js`, so the Windows timer gets it too): every other frame with twice the steps while nothing touches them, every frame near the pointer or while the digits change; nothing is drawn while scrolled out of view. Measured in the preview: 30 draws a second idle, 60 while the pointer is near or the digits change.
- **Not ported yet:** the Mac's tab-coloured BorderGlow buttons (Windows buttons are solid accent fills with a fixed violet hover glow); the Assistant, Admin console, Google Classroom, screen usage and the other ⬜ rows.

### 2026-10-23, an autonomous pass (nothing pushed, published or committed)
- **CI read first.** The Windows build for the 2.0.8 push (run 39914530311) passed, so the hand-edited `Cargo.lock` (rustls-webpki 0.103.16, webpki-root-certs 1.0.10), the aurora window code and the version bump all compile and pass `cargo test` on a Windows runner. The dependency scan passes too.
- **Security scan fixed.** The code scan (Semgrep) blocked on one finding: the rail's `message` listener in `windows/src/main.js` ("insufficient postMessage origin validation", although the origin was checked). The rail page is same-origin, so it now reports "ready" and "select:<id>" with a direct call (`window.__lockenRailMessage`, set by `main.js`, called from `public/glassicons/bridge.js`) and there is no listener. Checked in the preview: ready arrives, a press opens the page, the ring follows.
- **Rail keyboard access.** The rail's iframe had `tabindex="-1"`, so a collapsed sidebar could not be reached with Tab. Removed; checked that Tab enters it, moves between the buttons and Enter opens the page.
- **Narrow windows.** At 480 px the full sidebar left 244 px for the page and pages scrolled sideways. Below 860 px the rail is now used (`fitSidebar`, `NARROW_WINDOW`), the toggle is hidden there, and the saved choice is untouched. Found by measuring every page: two real bugs, both fixed in `style.css`: the top bar's `.bar` padding (16px 24px) also applied to the Analytics chart bars, keeping each at least 48 px wide; and the goal-source pills did not wrap. The sphere stage can't shrink without changing its markup, so the minimum window width went from 420 to 640 px (`tauri.conf.json`), which also fits the Mac's habit of a minimum size.
- **High contrast and transparency.** The sidebar toggle icon has `forced-colors` colours; the aurora window is hidden in high contrast and with transparency effects off.
- **Validated.** Browser preview at 640, 800, 900, 1000 px: no sideways scroll on any of the six pages, sidebar and rail switch live and restore, no JavaScript errors across a walk of every page, the rail, collapse and expand, and the Ctrl shortcuts. `vite build` (production) and the JSON configs pass. Not run: any Windows runtime, the installer, display scaling, several monitors.
- **Deferred, and why.** Everything left in the table above needs Rust that cannot be compiled or run here (no `cargo`; installing it is not something this pass may do): foreground-app tracking, Google Classroom, Windows toasts, a global hotkey, the floating widget, the Assistant. Gating a window close with commitment mode (the Mac's quit gate) needs a close handler, which makes Tauri's JS destroy the window and so needs a new capability; a wrong permission would stop the app closing, so it waits for a PC to test on. Publishing the new Windows installer (the site still has the 19 October one) needs approval.

