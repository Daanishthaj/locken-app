# Authentication

The app uses Supabase Auth on project `isohdbjcvluvaflmrfeg` through its REST API, with only the publishable key (`sb_publishable_…` on the `apikey` header; a signed-in user's own token goes on `Authorization`). Identity always comes from the server: an app never trusts a user ID it holds itself.

## Accounts are required

The Mac app (`LockenTestApp/`) and the Windows app both need an account: the Mac's `AuthGate` shows the sign-in screen until a server-verified session exists. There is no guest mode.

## Sign-up

| Step | Mac app (`AuthManager`) |
|---|---|
| Details | Email, password, birth month and year (a neutral age screen for COPPA: no hint of the cutoff; under-13s are stopped and the Mac stops offering sign-up and Google sign-in), an unchecked "I agree to the Terms of Service and Privacy Policy" box with links to the in-app documents, and for ages 13–17 a parent-or-guardian agreement box; all required before Google sign-up too |
| Password rules | `PasswordPolicy`: 8+ characters (NIST SP 800-63B), up to 64; blocks common, breached, repetitive and sequential passwords and ones containing "locken" or the email name; breached check through Have I Been Pwned k-anonymity (only the first 5 SHA-1 characters leave the Mac) |
| Confirmation | Supabase emails a 6-digit code (Confirm signup template uses `{{ .Token }}`) |
| Existing email | Same reply as a new one |

## Sign-in

1. Email and password go to `POST /auth/v1/token?grant_type=password`.
2. Every new sign-in also needs a 6-digit code sent by email (OTP length 6, expiry 600 s). In the Test App it's entered with CodeSlots.
3. If the account has an authenticator app (TOTP), the Mac app asks for that code before signing in, which raises the session to `aal2`.
4. **Errors:** a wrong email and a wrong password give the same message ("Email or password is incorrect.").
   - **Bot check (Cloudflare Turnstile, built 2026-10-18, off until configured):** sign-up, password sign-in, email codes, resend and reset send a single-use Turnstile token as `gotrue_meta_security.captcha_token`; Supabase verifies it with the secret key (dashboard only, never in the apps). Invisible for most people; Cloudflare shows a checkbox only for suspicious requests. Mac: `TurnstileGate` runs the widget in its own web view, loaded with the `https://locken-app.vercel.app/` origin, limited to Cloudflare's challenge frames; site key in Info.plist `LockenTurnstileSiteKey`. Windows: `src/turnstile.js`, site key in `TURNSTILE_SITE_KEY`, CSP allows only `https://challenges.cloudflare.com` for its script and frame.
5. **Consent gate (since 2026-10-15):** any signed-in account with no birth month/year or no agreement on record on this Mac or on the account (checked first; since 2026-10-18 the answer is stored on `profiles` and the account's answer wins, so another Mac or PC can't be given a different one) (for example a new Google account created from the Sign In tab) sees `ConsentGateView` before the app opens: date of birth, the unchecked Terms and Privacy box, and the guardian box for 13–17. Under 13, the account is deleted (server and Mac) and sign-up is blocked on that Mac. The agreement time is kept per account (`legal.agreedAt`).
6. **Mistyped email domains (since 2026-10-16):** sign-up stops addresses whose domain looks like a typo of a common provider (`gmail.comew`, `gmial.com`, `gmail.co`) and asks "Did you mean …@gmail.com?", so the confirmation code doesn't bounce. It checks the format only, so it says nothing about whether an account exists.
7. **Google:** "Continue with Google" runs OAuth with PKCE through `ASWebAuthenticationSession` and the redirect `locken://auth-callback`, which is allowed in Supabase's Site URL and Redirect URLs.

## Rate limits

- **Server:** Supabase's per-IP limits on sign-in, sign-up, OTP and reset; at most one code email per user every 60 s.
- **Mac app:** after 5 failed sign-ins, sign-ups, code checks, code resends, authenticator confirmations or Google exchanges, a 30 s pause that doubles with each further failure, up to 5 minutes. The count and pause are saved in UserDefaults (`auth.throttle.*`), so quitting Locken doesn't reset them.

## Sessions

- **Storage:** access and refresh tokens are stored only in the macOS Keychain, marked `ThisDeviceOnly`. They're in the login (file-based) keychain, where macOS doesn't enforce that flag; moving to the data-protection keychain is a planned change.
- **Launch:** the app checks the token with `GET /auth/v1/user`. A 401/403 tries one refresh, and if that is refused the user is signed out.
- **Offline:** with no connection the session is kept, and the Test App opens for the last verified account. It never signs someone out just for being offline.
- **No code needed on reopen:** the session persists until Sign Out.

## Sign-out

`POST /auth/v1/logout?scope=local` with the access token. If that token has expired, the app refreshes once and logs out with the fresh token, so the refresh token can't be reused. The Keychain items are then deleted.

**Sign out everywhere (Test App, Settings → Account):** the same call with `scope=global`, which revokes every refresh token for the account, on every Mac. It asks for confirmation first.

## Forgot password (sign-in screen)

1. **Forgot password?** under the password field uses the email typed above it and sends a 6-digit code through `POST /auth/v1/otp` (`create_user: false`). This is the same template as sign-in codes, so the email looks like a sign-in code. The screen says "If there's a Locken account for …" whatever the server answers, so the app never reveals which emails have accounts.
2. The code is checked with `POST /auth/v1/verify` (type `email`). The session it returns is kept **in memory only** until the new password is saved, so quitting halfway leaves nothing signed in.
3. If the account has an authenticator app, its code is required next (challenge/verify to `aal2`), so someone with only the inbox can't change the password.
4. The new password goes through `PasswordPolicy` and the Have I Been Pwned check, then `PUT /auth/v1/user`. Then `POST /auth/v1/logout?scope=others` signs out every other Mac, and this Mac is signed in with that session.
5. **Back to sign in** revokes the half-finished session. Every step counts toward the client backoff.

**Known limit:** Supabase itself answers `/otp` with 422 for an unknown email and 200 for a real one. The app hides this, but someone calling the API directly can tell. Mitigations are Supabase's rate limits and, later, CAPTCHA.

## Password change (Test App, Settings → Account)

1. `GET /auth/v1/reauthenticate` emails a 6-digit code to the account's address.
2. The new password goes through the same `PasswordPolicy` and Have I Been Pwned check as sign-up.
3. `PUT /auth/v1/user` with `password` and the code as `nonce`.
4. On success, `POST /auth/v1/logout?scope=others` signs out every other Mac.
5. Failures count toward the client backoff, and the server rate-limits code emails. An expired access token is refreshed once.

**Server setting needed:** the code is only enforced by the server when Supabase's "Secure password change" is on (Authentication → Providers → Email). With it off, the server accepts the new password without checking the code. Turn it on.

## Account deletion

1. Settings → Delete Account on Mac, or Delete account in the Windows app, with a confirmation.
2. The app calls the `delete-account` Edge Function (`LockenTestApp/Supabase/functions/delete-account/index.ts`):
   - `verify_jwt` is on
   - the user is looked up from the token, never the request body
   - accounts with an authenticator app must be at `aal2`
   - the admin (secret or service-role) key exists only in the function's environment; `admin-overview` is the only other function that uses it
3. Deleting the auth user cascades to `profiles`, `focus_sessions` and `feedback`. Audit-log rows (IDs and field names only) age out after 24 months.
4. After a successful delete:
   - **Mac app:** erases that account's local files, settings, Keychain items and pending notifications.
   - **Windows app:** removes the session, daily stats and birthday for that account.
5. **Tested:** no token, the anon key and a forged token all get 401; GET gets 405; a throwaway user was deleted with cascade.

## Server-side rules

- `handle_new_user` trigger creates each profile.
- `focus_sessions.user_id` defaults to `auth.uid()` and is NOT NULL.
- **Owner-only policies** for the `authenticated` role:
  - `profiles`: read own; update own, only `full_name`, `avatar_url`, `birth_month`, `birth_year` and `terms_agreed_at` (column grants; the last three are write-once, under-13 refused, agreement time set by the server, via trigger `private.guard_profile_consent`); no insert or delete rights (the trigger creates profiles, the cascade removes them)
  - `focus_sessions`: read, insert and delete own; update only `session_name`, `duration_minutes`, `completed` (never the owner or id). Migration `20261012_least_privilege_profiles_and_sessions.sql`. No app writes here today.
  - `feedback`: insert own (rate-limited by `feedback_rate_limit`) and read own (for Download My Data, migration `20261018_feedback_read_own.sql`); no update or delete.
  - `admins`: RLS on with no policies, so only the server (`admin-overview`) can read it.
- **Restrictive "Require MFA when enrolled" policies** call `private.mfa_requirement_met()`, a SECURITY DEFINER helper with an empty search path in a schema the API doesn't expose.
- **Anon role:** no privileges on any account table (migration `20261010_harden_anon_grants_and_close_waitlist.sql`).

## Windows app (`windows/`, test build)

Same Supabase project and the same rules as the Mac app, in `windows/src/auth.js` and `windows/src-tauri/src/secrets.rs`:

- **Keys:** only the publishable key ships. No service-role key anywhere in `windows/`.
- **Two-factor (Windows, since 2026-10-19):** after the emailed code, an account with a verified authenticator app (TOTP) must enter its 6-digit code (challenge + verify, AAL2 session) before the app opens, also when a stored session is still at AAL1 at launch. Settings → Two-Factor Authentication sets it up (QR code shown only as an image) or turns it off. The server rule `private.mfa_requirement_met()` (migration `20261019_require_mfa_when_enrolled.sql`) blocks `profiles`, `focus_sessions` and `feedback` for enrolled accounts below AAL2.
- **Backoff:** 5 wrong passwords or codes lock the form for 30 s, doubling up to 5 minutes, saved across restarts (same as the Mac).
- **Sign-in:** password first, then an emailed code (`/auth/v1/otp`, `create_user: false`) before the PC is trusted. The password session is logged out at once. Wrong email and wrong password both say "Email or password is incorrect."
- **Sign-up:** birth month and year first (under 13 is refused and the PC remembers that sign-up isn't available), an unticked "I agree to the Terms of Service and Privacy Policy" box and, for ages 13–17, a parent-or-guardian agreement box (both required, like the Mac; the agreement time is kept locally), typo-domain check, password rules (8+ characters, letters and numbers, not the email) and the Have I Been Pwned range check. The same screen shows whether or not the email already has an account.
- **Google sign-in (Windows, since 2026-10-18):** same PKCE flow as the Mac. The browser opens Supabase's `/auth/v1/authorize?provider=google` (the only Supabase page the opener may open, besides Locken's own site); Google returns to `locken://auth-callback?code=…`, which `tauri-plugin-deep-link` hands to the app (`tauri-plugin-single-instance` forwards it to the running copy). The code is exchanged with the verifier that stayed in memory, the session is dropped, and the emailed code is still required. Sign-up through Google asks the age and agreements first, as on the Mac.
- **Forgot password (Windows, since 2026-10-18):** emailed code (`/auth/v1/otp`, same reply for any email), `/auth/v1/verify`, then the new password (`PUT /auth/v1/user`, HIBP-checked) and `logout?scope=others`. Accounts with an authenticator app are told to reset on the Mac.
- **Age check on a new PC:** after the first sign-in, the app takes the account's birth month and year if it has one (same answer as the Mac); otherwise it asks, and saves the answer to the account; under 13 deletes the account (like the Mac's consent gate) and blocks sign-up on that PC.
- **Window permissions:** the app's own commands (sign-in storage, blocker, check-in) are declared in `build.rs`, so they're denied unless granted; only the main window gets them (`capabilities/default.json`), and the check-in popup can only send its answer and close (`capabilities/checkin.json`).
- **Identity:** always from `GET /auth/v1/user` with the access token; refreshed once on a 401/403.
- **Tokens:** access and refresh tokens in Windows Credential Manager (`keyring` crate, service `app.locken.windows.session`), never in the web view's localStorage.
- **Sign-out:** `POST /auth/v1/logout` first (refreshing once on a 401), then the tokens are deleted.
- **Account deletion:** "Delete account" calls the same `delete-account` Edge Function, which takes the user from the verified token; then the local session, stats and birthday for that account are removed.
- **Rate limits:** Supabase's server limits, plus client backoff of 1, 2, 4… up to 16 seconds after each failure.
- **Web view:** CSP allows only the app's own files, IPC, Supabase and the Pwned Passwords API.

## Not done yet

- **Leaked-password protection in Supabase** needs the Pro plan. Both apps check breached passwords themselves instead.
- **Authenticator apps on Windows:** the Windows app doesn't yet ask for a TOTP code; accounts with one get an aal1 session there, and the server's "Require MFA when enrolled" policies still block their data.
- **CAPTCHA on sign-up** (Cloudflare Turnstile through Supabase) needs a Turnstile account.
