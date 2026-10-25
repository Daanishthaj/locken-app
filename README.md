# Locken

**A free focus app for students, for Mac and Windows.** Pick one goal, start a timer, and Locken closes games and social
apps while you work, checks in on you along the way, and makes quitting early take a few seconds on purpose.

Download it at **[locken-app.vercel.app](https://locken-app.vercel.app)**.

## What it does

- **The Shield:** closes games, social media apps and distracting browser tabs when a session starts. You choose which
  apps it closes, and you can unblock any of them.
- **One goal, one timer:** type what you're working on (or pick a Canvas assignment) and how long. Locken opens the app
  you'll work in and turns on Do Not Disturb.
- **Check-ins:** a small panel drops from the notch partway through and asks how far into your goal you are. With
  Adaptive time on, the time left adjusts to your answer.
- **Commitment mode:** pausing, ending early or quitting Locken mid-session waits a few seconds first, so stopping is a
  choice instead of a reflex.
- **Steps, habits and analytics:** each session gets a short list of steps, and Locken tracks focus time, habits and how
  many distractions it blocked.
- **Assistant:** an optional voice assistant. Its voice (Kokoro) runs on your Mac; the microphone stays off until you
  press a button or hold the hotkey.
- **Canvas and calendar:** see Canvas coursework and your calendar in one place.

## What's in this repository

| Folder | What it is |
|---|---|
| `LockenTestApp/`, `LockenTestApp.xcodeproj` | The Mac app (Swift and SwiftUI). `LockenTestApp/WebComponents/` holds the React effects it shows in web views. |
| `windows/` | The Windows app (Tauri 2: Rust and JavaScript). |
| `web/` | The website (React and Vite). |
| `shared/` | Code used by both the Mac and Windows apps (the glass timer digits). |
| `supabase/` | Database migrations: tables, Row Level Security policies and functions. |
| `docs/` | Security, privacy, design and legal documents. |
| `scripts/` | Release and build helpers. |

## Build it yourself

**Mac app** (macOS 15 or later, Xcode 26 or later): open `LockenTestApp.xcodeproj` in Xcode and run the `LockenTestApp`
scheme. To rebuild the web effects, run `npm install` and then `node build.mjs` in `LockenTestApp/WebComponents/`.

**Windows app** (Node.js and the [Tauri prerequisites](https://tauri.app/start/prerequisites/)):

```bash
cd windows
npm install
npm run tauri dev
```

**Website:**

```bash
cd web
npm install
npm run dev
```

Sign-in and sync use Supabase. The apps ship only Supabase's public (anon) key, and every table is protected by Row
Level Security. To run your own backend, create a Supabase project, apply the migrations in `supabase/migrations/`, and
put your project's URL and anon key in place of Locken's (see `web/.env.example`). Before applying the admin migration,
replace the placeholder admin email in `supabase/migrations/20261016_feedback_and_admins.sql` with your own.

## Privacy and security

Locken has no ads and no tracking. How it handles your data, sign-in and updates is written up in
[`docs/SECURITY.md`](docs/SECURITY.md), [`docs/DATA_SECURITY.md`](docs/DATA_SECURITY.md) and
[`docs/legal/PRIVACY_POLICY.md`](docs/legal/PRIVACY_POLICY.md). To report a security problem, see `docs/SECURITY.md`.

## License

Locken's own code is released under the [MIT License](LICENSE). Third-party components keep their own licenses; they
are listed in [`CREDITS.md`](CREDITS.md).
