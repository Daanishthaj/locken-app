# Security policy

Locken is a free focus app for students. The Mac app that ships is the one in `LockenTestApp/`; a Windows test build lives in `windows/` (Tauri). The old Locken app (`KissaFocus/`) was discontinued on 2026-10-14. Its code is deleted (it remains in git history), its download and installer are off the website, and `version.json` tells existing copies they're discontinued. Turning off Supabase's legacy API keys ends its sign-in. Sections below that mention "the main app" describe that old app. There's also a website (`web/`, hosted on Vercel) and one Supabase project (`isohdbjcvluvaflmrfeg`) for accounts.

This file is the entry point. The detail lives in four companion documents:

| Document | What it covers |
|---|---|
| [AUTH.md](AUTH.md) | How sign-up, sign-in, two-step codes, sessions, sign-out and account deletion work |
| [DATA_SECURITY.md](DATA_SECURITY.md) | Every piece of data Locken handles: where it lives, who can read it, how long it's kept and how it's deleted |
| [THREAT_MODEL.md](THREAT_MODEL.md) | What we protect, from whom, the trust boundaries, and the risks we've accepted |
| [SECURITY_CHECKLIST.md](SECURITY_CHECKLIST.md) | The pre-ship checklist with Locken's current status on every item |

Read all five before changing sign-in, the database, the updater, anything that sends data off the Mac, or anything that controls other apps.

## Supported versions

Only the latest published build gets security fixes. The website's `version.json` names it.

## Reporting a vulnerability

- Don't open a public issue, and don't test against other people's accounts.
- Contact: **daanu.focus@gmail.com**. Put "Locken security" in the subject.
- Include what you found, how to reproduce it, and what an attacker could do with it.
- You'll get a reply within 7 days. Fixes for anything that exposes account data ship before anything else.

## Security principles

These hold for every change. The reasons and details are in the companion documents.

1. **Only the public key ships.** The app carries only Supabase's publishable key (`sb_publishable_…`), sent on the `apikey` header and never as a bearer token; it can be revoked and rotated on its own. The admin key (the new secret key, with the legacy service-role key as a fallback until legacy keys are turned off) exists only in the environments of the `delete-account` and `admin-overview` Edge Functions. The discontinued old app carried the legacy anon key, which is why turning legacy keys off ends it.
2. **The server decides who you are.** Identity comes from the verified access token (`auth.uid()` in policies, `GET /auth/v1/user` in code), never from anything the client sends.
3. **Row Level Security on every table.** Policies are scoped to `auth.uid()`. The anon role has no privileges on account tables at all.
4. **Data stays on the Mac by default.** Focus stats, screen usage, notes, habits and reminders never leave it. Accounts hold only email, name and avatar.
5. **Secrets go in the Keychain.** Session tokens, Canvas tokens, AI keys and the optional ElevenLabs key live there, never in UserDefaults or plain files. On Windows the AI key and the optional ElevenLabs key sit in Credential Manager and only Rust reads them and calls the provider, so the web view never holds them.
6. **One error for a wrong email or password.** Sign-up and resets never reveal whether an account exists.
7. **Sign-out reaches the server.** The session is revoked, not just forgotten locally.
8. **Users see friendly errors.** Raw server and system errors stay in logs.
9. **No Full Disk Access.** The distraction blocker closes only games, social media and YouTube, never work apps.
10. **Every download is verified.** The installer checks the DMG against the published SHA-256. The in-app updater also requires an Ed25519 signature made with the release key, which lives only in the publisher's Keychain (`scripts/release-signing.swift`). On the sign-in screen (signed out, nothing in progress) a signed update installs automatically instead of asking (`AppUpdater.installIfOnSignInScreen`); the checks are the same as clicking Update, and a build that fails them is never installed. The installer script runs in its own session (`posix_spawn` with `POSIX_SPAWN_SETSID`), so it isn't stopped when Locken quits, and logs each step to `~/Library/Logs/Locken/updater.log`. Neither strips macOS quarantine flags.
11. **Secrets can't be committed.** `scripts/git-hooks/pre-commit` blocks API keys, private keys, service-role keys and `.env` files. Enable it after cloning: `git config core.hooksPath scripts/git-hooks`.
