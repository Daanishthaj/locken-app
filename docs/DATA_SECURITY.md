# Data security

Everything Locken stores or sends, where it lives, who can read it, how long it's kept and how it's deleted. If a change adds a new kind of data or a new place it goes, update this file in the same change.

## What stays on the Mac

None of this leaves the Mac. It's protected by the user's macOS account and FileVault.

| Data | App | Where | Kept | Deleted by |
|---|---|---|---|---|
| Session tokens | Mac app | Keychain (`auth.accessToken`, `auth.refreshToken`, `ThisDeviceOnly`) | until Sign Out | Sign Out, Delete Account |
| Canvas access token, calendar feed link | Mac app | Keychain, per account | until Unlink | Unlink, Delete Account |
| Canvas access token, calendar feed link | Windows app | Credential Manager (`app.locken.windows.canvas`, per account); read only by Rust, which makes every Canvas request, so the web view never holds it | until Unlink | Unlink, Delete Account |
| Canvas assignments checked off by hand (assignment IDs only, last 500) | Windows app | local storage, per account (`locken.canvas.checked.<id>`); nothing is sent to Canvas | until Delete Account | Show them again, Delete Account |
| Google Classroom refresh token (read-only sign-in, since 2026-10-21; no client secret exists in the app) | Mac app | Keychain (`classroom.refreshToken`), per account; access tokens live in memory only | until Unlink | Unlink (also revokes it at Google), Delete Account |
| AI provider API keys | Mac app | Keychain, per account | until removed | Remove key, Delete Account |
| ElevenLabs API key (Assistant voice, since 2026-10-25; the student's own key, optional) | Test App | Keychain (`com.locken.LockenTestApp.elevenlabs`, `apiKey-<user id>`), per account | until removed | Settings → Assistant voice → Remove, Delete Account |
| AI provider API keys | Windows app | Credential Manager (`app.locken.windows.ai`, per account); read only by Rust, never sent to the web view | until removed | Remove key, Delete Account |
| ElevenLabs API key (Assistant voice, since 2026-10-27; the student's own key, optional) | Windows app | Credential Manager (`app.locken.windows.elevenlabs`, per account); read only by Rust (`voice.rs`), never sent to the web view | until removed in Settings or the account is deleted |
| Kokoro voice model (public file, no personal data; 92 MB, SHA-256 checked) | Windows app | the web view's Cache API (`locken-kokoro-v1`) | until removed in Settings › Assistant voice |
| Assistant conversations (text only) and voice choice | Windows app | local storage, per account (`locken.assistant.history.<id>`, newest 200; `locken.assistant.voice.<id>`, `locken.assistant.speak.<id>`) | until deleted in the Assistant's History or the account is deleted |
| Focus stats (focus seconds per day, sessions, app usage counts, blocked distractions, how often each pause reason was chosen) | Test App | `~/Library/Application Support/LockenTestApp/stats-<user id>.json` | day-by-day history 1 year (older days dropped); totals until deleted | Delete Account |
| Screen usage (front app name and category; browser **domain only**, never full URLs). Measured while Locken is running, including with its window closed; with Settings → Open at login on, Locken also starts hidden at login so it keeps measuring after a restart | Test App | `screen-usage-<user id>.json`; nothing is sent anywhere | 35 days | rolling, Settings → Clear Screen Time History, Delete Account |
| Open at login (Mac): whether Locken starts when the student logs in | macOS's own login-items list (`SMAppService.mainApp`; System Settings › General › Login Items), not a Locken file | off until turned on | until turned off | Settings → Open at login, or Login Items in System Settings; not removed by Delete Account (it holds no data) |
| Notes, milestones, habits | Test App | `notes-`, `milestones-`, `habits-<user id>.json` | indefinitely | user, Delete Account |
| The running focus session (goal, end time, total and planned length, Shield on/off, distractions blocked so far) | Test App | `session-<user id>.json`; never sent anywhere. Lets a session survive a force quit, crash, restart or update: the next launch picks it up if it still has time left | while the session runs; deleted when it's paused, ended, or Locken is quit normally | automatically, Delete Account |
| What's playing in a browser tab (title, artist and artwork of tabs on YouTube, YouTube Music, Spotify's web player and SoundCloud, read from the page's own media session, only after the student allows Automation for that browser and turns on its Allow JavaScript from Apple Events switch) | Test App | memory only; shown in the sidebar card while it plays; never saved, counted as listening time, or sent anywhere. The volume of Spotify, Music and those tabs is turned down while the Assistant talks and put back. The original volumes (numbers only, no titles) are also written to UserDefaults key `assistant.duckedMedia` while they are turned down, so a force quit or crash can't leave the music quiet: the next launch puts them back and clears the key (the Settings switch `assistant.lowersOtherMedia` turns the whole thing off) | while it plays | Settings › Other media, leaving the browser's switch off |
| Now Playing listening time per song (Spotify and Music only) | Test App | UserDefaults, per account | only the 200 most-listened songs are kept | Delete Account |
| Display name (dashboard greeting, profile card; starts from the Google name or the email's first part) | Test App | UserDefaults, per account (`profile.displayName-<user id>`); never sent anywhere | indefinitely | Settings → Account → Your name, Delete Account |
| Blocked-apps choices (bundle IDs and names the user added; built-in blocks they turned off) | Test App | UserDefaults, per account (`blocker.userBlocked`, `blocker.userAllowed`); never sent anywhere. Installed apps are found by reading each app's Info.plist in /Applications, ~/Applications and /System/Applications (no extra permission) | indefinitely | Settings → Blocked apps, Delete Account |
| Work-app lineup (names, bundle IDs and app paths of the apps under "Where you'll work") | Test App | UserDefaults, per account (`workspace.lineup`); never sent anywhere. Found the same way as blocked apps (Info.plist only) | indefinitely | Start session → + tile → Reset, Delete Account |
| YouTube videos allowed for the current session (video IDs pasted by the user, or found in a Canvas assignment's description) | Test App | memory only; passed to the tab-check AppleScript; never written to disk or sent anywhere | until the session ends or is reset | remove in Focus → Videos for this session |
| Canvas assignment details (title, course, due time, points and Canvas's description as plain text, cut to 1,200 characters), shown when you click an assignment on the Calendar page | Test App | memory only, fetched straight from your school's Canvas; the description is shown as text and never rendered as HTML; never saved or sent to an AI (the Assistant gets titles and due dates only) | until Locken quits or Canvas is refreshed | Unlink, quitting Locken |
| Canvas assignments checked off by hand (assignment IDs only, last 500) | Test App | UserDefaults, per account (`canvas.checkedOff`); nothing is sent to Canvas | indefinitely | "Show them again" in Focus, Delete Account |
| Typed "Other" pause reasons (last 50, up to 200 characters each) | Test App | inside `stats-<user id>.json`; never sent anywhere | indefinitely | Delete Account |
| Birth month and year (age screen at sign-up; AI features need 18+) | Test App | UserDefaults, per account (`age.birthMonth`, `age.birthYear`), and on the account (`profiles.birth_month`, `birth_year`, since 2026-10-18) so every Mac and PC uses the same answer; the account's answer wins | indefinitely; can't be changed (the server refuses changes) | Delete Account |
| Sign-up stopped on this Mac (yes/no, set when someone under 13 tries to sign up) | Test App | UserDefaults `signup.ageBlocked`; no personal data | indefinitely | — |
| Sign-in throttle (failed attempts and pause end time) | Test App | UserDefaults `auth.throttle.failures`, `auth.throttle.lockedUntil`; no personal data | until the next successful attempt | automatically |
| Updater log (time and outcome of each update install: installed, signature check failed, and so on) | Test App | `~/Library/Logs/Locken/updater.log`; file paths and dates only, no personal data; never sent anywhere | until deleted | user |
| Commitment mode on/off | Test App | UserDefaults `focus.commitmentMode`; no personal data | indefinitely | Settings → Locken |
| Assistant conversations (since 2026-10-21): what the student said or typed (voice becomes text on the Mac first) and the replies, with a start time per conversation, shown by day in the Assistant's History panel | Test App | `~/Library/Application Support/LockenTestApp/assistant-history-<user id>.json`, readable by this Mac account only (`0600`); never sent anywhere by itself (only the last 12 turns go to the AI provider, as before, see below). The 500 newest conversations are kept; if the file can't be read it's set aside as `.json.unreadable` instead of being overwritten | until deleted | History panel: delete one conversation or a whole day (asks first); Delete Account (also removes the `.unreadable` copy); included in Download My Data |
| Assistant microphone audio | Test App | never stored: Apple's speech recognizer runs with `requiresOnDeviceRecognition = true`, so audio stays on the Mac and only the text is used | not kept | — |
| Assistant voice choice and the ElevenLabs clones' names (no personal data) | Test App | UserDefaults: `assistant.elevenLabsVoice-<user id>` (the picked clone, per account) and `assistant.elevenLabsVoiceNames` (names ElevenLabs gives the clones) | until changed | Settings; the choice goes with Delete Account and is in Download My Data |
| Assistant voice files (Kokoro, about 103 MB, no personal data) | Test App | `~/Library/Application Support/Locken/Voice/`; downloaded only when the student clicks Download voice, checked against a pinned SHA-256 | until removed | deleting the folder |
| Assistant "add calendar events" switch | Test App | UserDefaults `assistant.mayAddCalendarEvents`; off by default; no personal data | indefinitely | the switch |
| Assistant hotkey choice (which key to hold) | Test App | UserDefaults `assistant.holdKey`; the chosen key's up/down state is read about 30 times a second while someone is signed in with an AI key saved, in any app (`NSEvent.modifierFlags` and the time since the last key press or click; no keyboard-monitoring permission, no key contents, nothing recorded or sent). Holding it for 0.4 s starts listening (from another app: one question, then it stops, with a short sound), pressing it while Locken talks interrupts; Escape works only in Locken's own window; no personal data | indefinitely | Settings |
| Apple Reminders and Calendar | Mac app | Apple's own stores, read/written through EventKit with the user's permission | Apple's | the user, in Reminders/Calendar |
| Apple Notes (titles, edit dates, first lines of the 30 most recent notes) | Test App | read from the Notes app through Apple Events after the user taps Connect (macOS Automation prompt); held in memory only, never written to disk or sent; the connected flag is a per-account UserDefaults value (`appleNotes.connected`) | while the app runs | Disconnect, Delete Account |

**Per-account isolation:** every per-account file, UserDefaults key and Keychain item above is suffixed with the signed-in user's ID (`AccountScope`), so two accounts on one Mac never see each other's data. Items from before this change are adopted once by the first account that signs in. ("Test App" in this file means the Mac app that ships, `LockenTestApp/`; the old main app was retired on 2026-10-14.)

## What stays on a Windows PC (Windows app)

- Session tokens: Windows Credential Manager.
- Today's focus minutes, sessions and distractions closed, per account: the app's local storage, keyed by user ID.
- Habits (name and the days ticked, last 400) and notes (title and text), per account: the app's local storage, keyed by user ID; never sent anywhere; erased by Delete account.
- Blocked-apps choices (extra program names to close, built-in apps kept open), per account: local storage; sent only to the app's own blocker, never off the PC.
- Birth month and year, per account (also on the account, `profiles.birth_month`/`birth_year`, so a PC and a Mac agree), and the under-13 "sign-up isn't available" flag: local storage.
- Your name (Settings › Account, up to 40 characters), per account: local storage `locken.name.<user id>`; never sent anywhere; included in Download My Data and erased by Delete Account.
- Week digest (Analytics): the last plan written, in memory only until sign-out or quit.
- Session goal and check-in answers: in memory for the session only, never saved.
- Running programs: read during a session to close blocked ones; never stored or sent.

## What goes to Locken's server (Supabase)

| Data | Table | Who can read it |
|---|---|---|
| Email, hashed password, auth metadata, TOTP factors | `auth.users` (managed by Supabase) | the server only |
| Full name, avatar URL | `public.profiles` | the owner only (RLS); user-editable |
| Birth month and year, Terms agreement time (since 2026-10-18) | `public.profiles` (`birth_month`, `birth_year`, `terms_agreed_at`) | the owner only (RLS). Write-once: trigger `private.guard_profile_consent` refuses changes once set, refuses an age under 13 or over 120 (so no child's birth date is stored), and sets the agreement time to the server's `now()` |
| Focus session records (name, minutes, completed) | `public.focus_sessions` | the owner only (RLS). **No app writes here today.** |
| Feedback the user sends (rating 1–5, up to 2,000 characters, app version) | `public.feedback` | the user who sent it (read own, for Download My Data) and the owner's admin view (service role). Users can add rows (RLS `user_id = auth.uid()`, `user_id` set by the server), at most 5 a day, and read only their own; no update or delete; deleted with the account |
| Account bans | Supabase Auth's `banned_until` on the account; set and cleared only by `admin-overview` for accounts in `public.admins` (never on an admin) | until the owner unbans; removed with the account |
| Sign-ups never confirmed | `auth.users` without `email_confirmed_at` | deleted, with their profile row, by the nightly `delete-unconfirmed-signups` job once 24 hours old |
| Admin list (the owner's account IDs) | `public.admins` | the server only (RLS on, no grants); the `admin-overview` function checks it on every request and returns 403 to everyone else |
| Admin console analytics (activity days, builds, sign-in methods, an event feed of sign-ups/sign-ins/confirmations/feedback/data changes, RLS and function-exposure checks) | computed on request by `public.admin_analytics()` from data Supabase Auth and the app's tables already hold; nothing new is collected from the app | SECURITY DEFINER, executable by `service_role` only (not `anon` or `authenticated`); returned only through `admin-overview` to accounts in `public.admins`. The console's CSV export runs on the admin's Mac and saves only where they choose |
| Waitlist (empty; the 3 old emails were deleted on 2026-10-15) | `public.waitlist_subscribers` | nobody through the API. Anonymous inserts were closed on 2026-10-10. |

- **No storage buckets.** Nothing is uploaded.
- **At rest and in transit:** Supabase encrypts the database at rest; all traffic is HTTPS with App Transport Security at its default.
- **Account deletion:** removes the auth user; the profile, sessions and feedback cascade (see [AUTH.md](AUTH.md)).
- **Audit log (since 2026-10-15):** `audit.log` records each insert, update and delete on `auth.users` (sign-up, email or password change, deletion; routine sign-in timestamps are skipped), `public.profiles`, `public.focus_sessions` and `public.feedback`: the table, action, row ID, acting user (`auth.uid()`), role and the **names** of changed columns, never their values, kept 24 months (the `audit_log_prune` trigger removes older records whenever a new one is written). The `audit` schema isn't exposed by the API and no app role can read or write it; only the project owner can. Migration `supabase/migrations/20261015_audit_log.sql`. A failure to log never blocks the change.

## Data processors (for the Privacy Policy)

| Processor | Role | Data |
|---|---|---|
| Supabase (AWS us-east-2) | accounts and sign-in | email, password hash, name and picture from Google, sign-in codes |
| Google (OAuth) | optional "Continue with Google" | sign-in only |
| Gmail SMTP / Supabase email | sign-in and confirmation codes | email address, 6-digit code |
| Vercel | update feed and downloads | standard web requests |
| Have I Been Pwned | breached-password check (Mac: sign-up, password change and reset; Windows: sign-up) | 5 characters of a password hash |
| School's Canvas (chosen by the user) | assignments | the user's Canvas token, to their school only |
| Google (Classroom API and sign-in; Mac, if linked) | the student's assignments | read-only sign-in token; course names, assignment titles, due dates and handed-in state are read and held in memory (not saved) |
| Anthropic / OpenAI (ChatGPT) / Google Gemini (user's own key, 18+) | AI features | scrubbed goal, assignment, reminder and event titles |

No analytics, advertising, crash-reporting or tracking SDKs. No cookies in the app; the website sets none.

## What goes to other services, and when

| Service | What is sent | When |
|---|---|---|
| Gmail SMTP (through Supabase) | the user's email and a 6-digit code | sign-up and every new sign-in |
| Have I Been Pwned | first 5 characters of the password's SHA-1 (k-anonymity) | Mac sign-up, password change and reset; Windows sign-up |
| Google (accounts.google.com, oauth2.googleapis.com, classroom.googleapis.com) | the sign-in (PKCE, no client secret), then the refresh token to get access tokens, and read-only requests for courses, course work and the student's own submissions; unlinking sends a revoke request | when Google Classroom is linked, refreshed (when Locken opens and on request) or unlinked |
| The student's school Canvas (their own host) | their Canvas token, sent only to that host over HTTPS; paging links are followed only on the same host | when Canvas is linked or refreshed |
| AI providers the user connects (Claude, ChatGPT or Gemini; on Windows Intelligent Rephrase and session steps: goal, length, workspace app; the Assistant: typed message, last 8 turns and the facts it shows (session, steps, habits, focus totals, Canvas assignments); and the week digest: the next 7 days' Canvas titles, courses and due times, when Plan My Week is pressed) | email addresses, US-style phone numbers and web links are replaced with placeholders first (`AITaskFormatter.scrubPersonalInfo`, applied to every request in `ask`); then the goal or assignment text they enter, the session length, the work app's name, the current date and time, and up to 8 upcoming Canvas assignment titles with course names and due dates; in the Test App, when the user presses a digest button, their open reminders' titles, due dates, list names and priority (never reminder notes; up to 60) or the next 7 days' Canvas assignment and calendar event titles, times and course names; all with the user's own key. Digests are kept in memory only; each key goes only to its own provider, and Gemini's in a header, not the URL | only when the user has added a key and uses an AI feature |
| AI provider, from the Assistant tab (Mac) | the student's spoken words as text (never audio) and the last 12 turns, the date and time, the running session's goal and time left, the focus steps (their text and whether done, up to 12), today's habits (name, done or not, streak), the open Reminders (up to 12: title and due date, never their notes), totals of focus time and screen time, overall and by category (never app or website names), the next 10 Canvas assignments not yet checked off (title, course, due), and with Apple Calendar connected the next 7 days' event titles and times; scrubbed by `scrubPersonalInfo` like every AI request; 18+ only | each time the student talks or types to the Assistant |
| GitHub releases (Kokoro voice files, `Jud/kokoro-coreml`, tag `models-2026-03-23`) | a standard download request (reveals the IP address) | once, when the student clicks Download voice |
| ElevenLabs (api.elevenlabs.io, Mac and Windows Assistant, only with the student's own key; on Windows the request is made by Rust) | the key in the `xi-api-key` header; when the key is saved, the clone IDs to look up their names; while an ElevenLabs voice is picked, the text of each reply Locken is about to say (up to 1000 characters per sentence group, never the student's words, audio or anything else) | when the key is saved, and each time the Assistant speaks with an ElevenLabs voice |
| YouTube oEmbed (youtube.com/oembed) | the video ID of a link the student pastes into the "is it for school?" check, to get its title and channel (no account or key) | only when that check runs during a session |
| Vercel (locken-app.vercel.app) | standard web requests | update checks (`version.json`), downloads, the website |
| Spotify's image server | a standard request for the album artwork of the song playing in Spotify (reveals the IP address) | when Spotify is playing and the profile card is shown |

- **Nobody receives:** no analytics, ad networks, crash reporters or tracking pixels, in either app or on the website. The owner's admin view (above) is computed from Supabase's own sign-in records and is disclosed in the Privacy Policy.
- **Disclosure:** the Mac app's Settings privacy card says what goes where, in plain words.

## Input handling

- **Sign-in fields:** emails are checked for format and length (≤100); names and inputs have control characters stripped and are length-capped.
- **Server side:** the database enforces ownership through RLS and column grants, and the waitlist email length (≤254).
- **Web views (Test App):** they only load the app's bundled `Web` folder, so a page can't navigate anywhere else.
- **Tab blocker:** the site list is reduced to host and path characters before it goes into AppleScript, so a list entry can't run commands (unit-tested).
- **Canvas descriptions:** HTML is stripped before display, and nothing from Canvas is rendered as HTML.

## Backups and exports

- There's no cloud backup. The fake Google Drive backup was removed on 2026-10-07.
- **Download My Data (Test App, Settings → Data on this Mac):** saves one JSON file with the account ID and email, every per-account file and setting on the Mac (`AccountScope.exportData`, which shares its file and key lists with Delete Account), and the account's own server rows: profile and feedback (`AuthManager.serverDataForExport`, read under RLS). Secrets (session, Canvas token or feed, AI key, ElevenLabs key) are left out. The audit-log record is available by email. The Windows app has no export yet; Windows users email us.

## Rules for changes

- New data needs a row in the right table above, with where it lives, who can read it, how long it's kept and how it's deleted.
- Anything new that leaves the Mac needs a line in the Settings privacy card and in the "other services" table.
- New server tables need RLS, owner-scoped policies for `authenticated`, no grants to `anon`, and a check against the security advisors.
