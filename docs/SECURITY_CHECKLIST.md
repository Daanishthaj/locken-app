# Security checklist

Check every item before shipping a build or merging a change to sign-in, data, the database, the updater or the website. Update the status column when something changes. Last full review: 2026-10-12.

✅ done · ⚠️ partly done or accepted risk · ❌ not done

## Auth and login (5 rules)

| # | Rule | Status | Evidence |
|---|---|---|---|
| A1 | No service-role or secret key in any client bundle | ✅ | The Mac and Windows apps ship only the publishable key (`AuthManager.swift`, `windows/src/auth.js`, `apikey` header only); the admin key (secret key, legacy service role as fallback) only in the `delete-account` and `admin-overview` Edge Function envs; source and full git history scanned for `service_role`, `sk_`, `sk-ant-`, `AIza` |
| A2 | User ID read from the verified session, never the request | ✅ | Policies use `auth.uid()`; `focus_sessions.user_id` defaults to it; `delete-account` uses `getUser(jwt)` |
| A3 | RLS on for every table, policies scoped to `auth.uid()` | ✅ | `profiles`, `focus_sessions`, `feedback`, `admins`, `waitlist_subscribers` and `audit.log` all RLS on; anon has no privileges on any of them (migration `20261010_harden_anon_grants_and_close_waitlist`); `admins` and `audit.log` have no policies, so only the server reads them |
| A4 | Sign-out reaches the server | ✅ | `POST /auth/v1/logout`, refreshing once if the token expired, in the Mac and Windows apps |
| A5 | One error for wrong email and wrong password; sign-up and reset don't reveal accounts | ✅ | "Email or password is incorrect."; sign-up replies the same for existing emails |

## Pre-ship checklist

| # | Item | Status | Evidence |
|---|---|---|---|
| 1 | Secrets out of source, bundles and git; `.env` git-ignored | ✅ | Keys in the Keychain or the Edge Function env; `.env` files ignored and never committed. 2026-10-12: tree, new commits, `web/dist` and every JWT in source scanned; the only JWT is the anon key (`role: anon`); GitHub repo is private |
| 2 | Git history scanned for leaked secrets | ✅ | Full `git log -p` scan clean except the public anon key |
| 3 | Authentication on everything that isn't public | ✅ | Account tables and `delete-account` need a valid user token; the website is public by design |
| 4 | Permissions checked on the server | ✅ | RLS, column grants and restrictive MFA policies; the UI isn't trusted |
| 5 | Each user can only reach their own data | ✅ | Server: owner-only RLS. Mac app: per-account local files, UserDefaults keys and Keychain items (`AccountScope`); Windows: per-account stats keyed by user ID |
| 6 | Database and storage locked down; security advisors run | ⚠️ | No storage buckets; SECURITY DEFINER helper in a non-exposed schema; signed-in users can only read profiles and update name/photo and, once, birth month/year and the agreement time (trigger-checked, under-13 refused), and can't change a session's owner or id (migration `20261012_least_privilege_profiles_and_sessions`). Advisors (2026-10-12): "Leaked Password Protection Disabled" (needs Supabase Pro) and the intended no-policy waitlist table |
| 7 | Admin routes protected server-side | ✅ | The admin console calls `admin-overview`, which checks the user from the token, requires aal2 with 2FA, and returns data only to accounts in `public.admins` (403 for everyone else, 401 without a user token); the Mac app shows the Admin tab only after that check; the old website `?admin=true` backdoor was removed |
| 8 | No debug mode in production | ✅ | No token or personal-data logging; web views aren't set inspectable (`isInspectable` defaults to off) |
| 9 | Detailed errors hidden from users | ✅ | Friendly messages for auth, Canvas, AI and updates; raw errors and status codes not shown |
| 10 | Inputs validated server-side; output escaped | ✅ | Column grants, NOT NULL `user_id`, waitlist email length check; Canvas HTML stripped; tab-blocker site list sanitised before AppleScript (unit-tested); website uses `textContent` |
| 11 | File uploads secured | ✅ | Not applicable: Locken accepts no uploads and has no storage buckets |
| 12 | No SQL injection | ✅ | Supabase REST only, no string-built SQL in the apps |
| 13 | Rate limits on login, sign-up, OTP and reset, plus client backoff | ✅ | Supabase server limits (one code email per user per 60 s); Mac backoff 30 s doubling to 5 min, saved across relaunches, covering sign-in, sign-up, codes, resends, authenticator setup and the Google exchange; Windows backoff 1 s doubling to 16 s; the unthrottled waitlist insert was closed. CAPTCHA site key in both apps, not enforced until the Supabase switch; Windows the same backoff (password, emailed code and authenticator code), saved across restarts |
| 14 | Security headers and CORS; native equivalents | ✅ | `web/vercel.json`: CSP, HSTS, X-Frame-Options, X-Content-Type-Options, Referrer-Policy, COOP; Permissions-Policy; no third-party scripts. Apps: App Transport Security default; Mac web views locked to bundled pages; Windows web view CSP limited to its own files, IPC, Supabase and HIBP |
| 15 | Tested as an untrusted user | ✅ | 2026-10-18: the publishable key gets permission denied on `profiles`, `feedback`, `focus_sessions`, `admins`, `waitlist_subscribers` and `rpc/admin_analytics`; `delete-account` and `admin-overview` return 401 without a user token; another user's feedback reads as 0 rows. 2026-10-12: anon key gets 401 reading `profiles`, `focus_sessions`, `waitlist_subscribers` and inserting into `focus_sessions` and the waitlist; `rpc/mfa_requirement_met` isn't exposed (404); `auth/v1/admin/users` refuses the anon key (403); `delete-account` returns 401 with no token or the anon key |

## Release-only items

| Item | Status | Note |
|---|---|---|
| Update signing | ✅ | In-app updates need an Ed25519 signature from the release key (`scripts/release-signing.swift sign …` before publishing) |
| Secret scanning before commits | ✅ | `scripts/git-hooks/pre-commit`; run `git config core.hooksPath scripts/git-hooks` after cloning |
| Dependency audit | ✅ | `.github/workflows/security.yml` runs OSV-Scanner on every lockfile (website, Windows npm and Cargo, web components) on every push and every Monday; it also flags known malicious packages. 2026-10-19: 0 issues that reach a shipped app. Six Cargo advisories (glib, proc-macro-error, zbus_names, zvariant, zvariant_derive) are Linux-only and listed with reasons in `windows/src-tauri/osv-scanner.toml`. The Mac app has no third-party Swift packages |
| Code scan | ✅ | The same workflow runs Semgrep (default, secrets, JavaScript, React, Rust, Swift rules) on the Mac app, Windows app, website, Supabase and scripts; any finding fails the run. 2026-10-19: 0 findings on 182 files |
| Swift packages pinned | ✅ | The Mac app's one package, `KokoroCoreML` (Assistant voice), is pinned to exactly `0.11.2` and its resolved commits are in `Package.resolved`; its voice files are pinned by tag and SHA-256. OSV-Scanner doesn't read SwiftPM, so review the package diff before raising the version |
| Developer ID signing, Hardened Runtime, notarization | ⚠️ | Deferred while Locken is free-only; users open it with right-click → Open |
| Published DMG matches the current build | ✅ | The live `Locken.dmg` and `version.json` are the signed current Locken build (`com.locken.LockenTestApp`); checked by sha256 after every release |
| Supabase leaked-password protection | ⚠️ | Needs the Pro plan; the Mac and Windows apps run their own Have I Been Pwned check |
| Supabase "secure email change" and "secure password change" | ❓ | Check in the dashboard (Authentication → Providers → Email); not readable through the tools available here. The Test App's password change relies on "secure password change" to enforce its emailed code |
| Licenses confirmed for every asset | ⚠️ | See `CREDITS.md`: the BubbledotICG font, the 3D orb (Supavec, Apache-2.0), the site's models and video, and `HumanBrain.usdz` |

## Common vibe-coding holes (checked 2026-10-19)

From a list of the security holes most often found in AI-built apps. Each one, and where Locken stands:

| Hole | Status | Where |
|---|---|---|
| Vulnerable dependencies, malicious packages | ✅ | OSV-Scanner in CI (above) |
| Prompt injection, AI access without permission | ✅ | AI features use the student's own key, are 18+ only, strip personal details, and their output is shown as text only |
| Database permissions too broad, poor tenant isolation | ✅ | RLS on every table with `auth.uid()` policies; app roles can update only `full_name` and `avatar_url`; anonymous probes refused |
| Missing audit logs | ✅ | `audit.log` records account-data changes (column names only), readable by the server only |
| No security monitoring | ⚠️ | Weekly CI scans and the Supabase security advisor; live alerting on the database needs a paid Supabase plan |
| No backups | ⚠️ | Free Supabase plan has no automatic backups. Needs either the Pro plan (daily backups) or a scheduled export Mohammed Sir sets up with his own database password |
| Exposed internal dashboards | ✅ | The admin page and `admin-overview` function check the `admins` table on the server |
| Missing security headers, insecure cookies | ✅ | Live site sends CSP, HSTS (preload), X-Frame-Options DENY, nosniff, Referrer-Policy, Permissions-Policy, COOP; the site sets no cookies; the apps keep tokens in Keychain / Credential Manager |
| Unencrypted sensitive data | ✅ | TLS everywhere; tokens in the system keychain; local data relies on FileVault / BitLocker (stated in the Privacy Policy) |
| Unreviewed AI code | ✅ | Semgrep on every push; changes reviewed with `/ponytail-review` before release |
| Mass assignment | ✅ | Column-level grants on `profiles`; consent fields are write-once and set by a server trigger |
| Command injection, insecure deserialization | ✅ | Windows opens only allow-listed apps; Mac web view bridges accept known strings only; JSON only, no native deserializers |
| Misconfigured auth | ✅ | The five auth rules above |

## How to re-run the checks

```bash
# Anonymous access must be refused (expect 401 for each).
KEY=<anon key from SupabaseConfig>
for t in profiles focus_sessions waitlist_subscribers; do curl -s -o /dev/null -w "$t %{http_code}\n" "https://isohdbjcvluvaflmrfeg.supabase.co/rest/v1/$t?select=*" -H "apikey: $KEY" -H "Authorization: Bearer $KEY"; done
```

```bash
# Secrets must not appear in source.
grep -rnE "service_role\"|sk_live|sk-ant-api[0-9]|sk-proj-[A-Za-z0-9_-]{20}|AIzaSy[A-Za-z0-9_-]{30}" LockenTestApp windows/src windows/src-tauri/src web/src
# Or let the pre-commit hook check staged changes: scripts/git-hooks/pre-commit
```

```bash
# Unit tests (Canvas host locking, tab-blocker injection, input validation).
xcodebuild -project LockenTestApp.xcodeproj -scheme LockenTestApp -configuration Debug build
```

Also run the Supabase security advisors (dashboard → Advisors, or the Supabase MCP `get_advisors`) after any database change.

## Privacy and compliance checks (added 2026-10-15)

- [x] Every account passes the age screen and the Terms/Privacy clickwrap before using the app, including Google accounts created from the Sign In tab (`ConsentGateView`).
- [x] Download My Data exports all per-account data; Delete Account erases the same list (`AccountScope.perAccountFiles` / `perAccountDefaultsKeys`).
- [x] Server audit log (`audit.log`) records account-data changes without values; unreadable by app roles.
- [x] AI text is scrubbed of emails, phone numbers and links before sending.
- [x] Bundled web pages load nothing from other servers (the hero image is bundled); the only outside image is Spotify album artwork on the profile card, disclosed in the Privacy Policy.
- [x] Deleted the 3 old `public.waitlist_subscribers` emails (2026-10-15).
- [x] Waitlist checked again (2026-10-18): 0 rows, closed to the public key since 2026-10-10.

## Emails to users (added 2026-10-18)

Locken sends only service emails today: sign-in codes, security notices, account notices and changes to the Terms (Terms §"communications"). These don't need opt-in. The Privacy Policy promises **no marketing unless you opt in**, and Locken has no opt-in today, so:

- **No "we launched", newsletter, promo or feature-announcement emails** to users or the old waitlist. Tell people about launches in the app (What's New) instead.
- If marketing email is ever wanted, all of these come first:
  - [ ] An opt-in checkbox, unticked by default, with the date and wording saved per person.
  - [ ] Every email has a working one-click unsubscribe, honored within 10 days (CAN-SPAM), and a postal address.
  - [ ] An honest subject line and "From" name; no emails to anyone under 13; nothing to people who unsubscribed.
  - [ ] The Privacy Policy updated to describe it, in the same change.

## Turning on the bot check (Cloudflare Turnstile)

Both apps already send a Turnstile token when a site key is set. Do these **in this order**, or sign-in breaks for anyone on an older version:

1. [x] Widget `Locken sign-in` created 2026-10-27 through the Cloudflare API (account `1d8d09aaec4cc5452cddc481c52e20cb`), mode **Managed**, hostnames `locken-app.vercel.app`, `tauri.localhost`, `localhost`, `127.0.0.1`. Site key `0x4AAAAAAFo_JiXIrKghT2dE`; secret checked against siteverify and not stored anywhere outside Cloudflare.
2. [x] Put the **site key** (public) in `LockenTestApp/Info.plist` → `LockenTurnstileSiteKey`, and in `windows/src/turnstile.js` → `TURNSTILE_SITE_KEY`.
3. [ ] Test a sign-in on both apps, release the Mac update and the Windows build, and wait until most users have updated.
4. [ ] Update the Privacy Policy: Cloudflare checks sign-in requests for bots and receives the IP address and browser signals for that check.
5. [ ] Owner, last: Supabase → Authentication → Attack Protection → **Enable CAPTCHA protection**, provider Turnstile, paste the **secret key** there (never in the apps or git).
