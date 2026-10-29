// Sign-in for Locken on Windows, against the same Supabase project as the Mac app.
// Rules (docs/AUTH.md): only the publishable key ships; identity always comes from GET /auth/v1/user;
// one message for a wrong email or password; sign-out revokes the session on the server;
// tokens live in Windows Credential Manager (Rust `secrets.rs`), never in localStorage.
import { invoke } from '@tauri-apps/api/core';
import { captchaToken } from './turnstile.js';

const PROJECT_URL = 'https://isohdbjcvluvaflmrfeg.supabase.co';
const PUBLISHABLE_KEY = 'sb_publishable__dafcMM6U-IfaRH_t1JtPg_3oafX8zK';
export const INVALID_CREDENTIALS = 'Email or password is incorrect.';

export class AuthError extends Error {}

// Auth endpoints Supabase guards with the bot check once CAPTCHA protection is on (same list as the Mac app).
const CAPTCHA_PATHS = ['/auth/v1/signup', '/auth/v1/token?grant_type=password', '/auth/v1/otp', '/auth/v1/resend', '/auth/v1/recover'];

async function request(path, { body, token, method } = {}) {
  if (body !== undefined && CAPTCHA_PATHS.some((p) => path.startsWith(p))) {
    let captcha;
    try { captcha = await captchaToken(); } catch (error) { throw new AuthError(error.message); }
    if (captcha) body = { ...body, gotrue_meta_security: { captcha_token: captcha } };
  }
  const headers = { apikey: PUBLISHABLE_KEY, 'Content-Type': 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;
  let response;
  try {
    response = await fetch(PROJECT_URL + path, {
      method: method || (body === undefined ? 'GET' : 'POST'),
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  } catch {
    throw new AuthError("Can't reach Locken. Check your internet connection.");
  }
  let json = {};
  try { json = await response.json(); } catch { /* empty body */ }
  return { status: response.status, json };
}

export function isValidEmail(email) {
  return /^[^\s@]{1,64}@[^\s@]+\.[A-Za-z]{2,}$/.test(email.trim()) && email.length <= 254;
}

const COMMON_DOMAINS = ['gmail.com', 'outlook.com', 'hotmail.com', 'yahoo.com', 'icloud.com'];
/** "name@gmail.comew" → "name@gmail.com", so a mistyped domain doesn't swallow the code. */
export function emailTypoSuggestion(email) {
  const [local, domain = ''] = email.trim().toLowerCase().split('@');
  const match = COMMON_DOMAINS.find((d) => domain !== d && domain.startsWith(d));
  return match ? `${local}@${match}` : null;
}

export function passwordProblem(password, email) {
  if (password.length < 8) return 'Use at least 8 characters.';
  if (!/[A-Za-z]/.test(password) || !/[0-9]/.test(password)) return 'Use letters and numbers.';
  if (password.toLowerCase() === email.trim().toLowerCase()) return "Don't use your email as the password.";
  return null;
}

/** Have I Been Pwned range check: only the first 5 characters of the SHA-1 leave the device. */
export async function isBreached(password) {
  try {
    const digest = await crypto.subtle.digest('SHA-1', new TextEncoder().encode(password));
    const hex = [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('').toUpperCase();
    const response = await fetch(`https://api.pwnedpasswords.com/range/${hex.slice(0, 5)}`, { headers: { 'Add-Padding': 'true' } });
    if (!response.ok) return false;
    const text = await response.text();
    return text.split('\n').some((line) => line.startsWith(hex.slice(5)) && !line.trim().endsWith(':0'));
  } catch {
    return false;
  }
}

async function storeTokens(json) {
  if (!json.access_token || !json.refresh_token) throw new AuthError("Locken couldn't finish signing in. Try again.");
  await invoke('save_session', { access: json.access_token, refresh: json.refresh_token });
}

async function sendEmailCode(email) {
  const { status } = await request('/auth/v1/otp', { body: { email, create_user: false } });
  if (status === 429) throw new AuthError('A code was just sent. Wait a minute before asking for another.');
  if (status !== 200) throw new AuthError("Couldn't send your code. Try again.");
}

// Client-side backoff on top of Supabase's server limits (checklist item 13): after 5 wrong tries, wait 30 s,
// doubling each time up to 5 minutes (the Mac's rule). Kept across restarts, cleared by a successful sign-in.
const THROTTLE_KEY = 'locken.auth.throttle';
function throttleState() { try { return { failures: 0, lockedUntil: 0, ...JSON.parse(localStorage.getItem(THROTTLE_KEY) || '{}') }; } catch { return { failures: 0, lockedUntil: 0 }; } }
export function checkThrottle() {
  const wait = Math.ceil((throttleState().lockedUntil - Date.now()) / 1000);
  if (wait > 0) throw new AuthError(`Too many attempts. Try again in ${wait > 90 ? `${Math.ceil(wait / 60)} minutes` : `${wait} seconds`}.`);
}
export function recordFailure() {
  const state = throttleState();
  state.failures += 1;
  if (state.failures >= 5) state.lockedUntil = Date.now() + Math.min(5 * 60, 30 * 2 ** (state.failures - 5)) * 1000;
  try { localStorage.setItem(THROTTLE_KEY, JSON.stringify(state)); } catch { /* memory only */ }
}
export function clearThrottle() { try { localStorage.removeItem(THROTTLE_KEY); } catch { /* nothing to clear */ } }

/** Password first, then an emailed code before this PC is trusted (same as the Mac app). */
export async function signIn(email, password) {
  checkThrottle();
  email = email.trim().toLowerCase();
  const { status, json } = await request('/auth/v1/token?grant_type=password', { body: { email, password } });
  if (status !== 200) {
    if (status !== 429) recordFailure();
    throw new AuthError(status === 429 ? 'Too many attempts. Wait a minute and try again.' : INVALID_CREDENTIALS);
  }
  // The password session only proves the password; drop it and require the emailed code.
  await request('/auth/v1/logout?scope=local', { body: {}, token: json.access_token });
  await sendEmailCode(email);
  return { email, isNewAccount: false };
}

export async function signUp(email, password) {
  email = email.trim().toLowerCase();
  const { status, json } = await request('/auth/v1/signup', { body: { email, password } });
  if (status === 429) throw new AuthError('Too many attempts. Wait a minute and try again.');
  if (status === 200 && json.access_token) {
    await request('/auth/v1/logout?scope=local', { body: {}, token: json.access_token });
    await sendEmailCode(email);
    return { email, isNewAccount: false };
  }
  // Same screen whether or not the email already has an account.
  if (status === 200 || status === 400 || status === 422) return { email, isNewAccount: true };
  throw new AuthError("Couldn't create the account right now. Try again.");
}

export async function resendCode({ email, isNewAccount }) {
  if (isNewAccount) {
    const { status } = await request('/auth/v1/resend', { body: { type: 'signup', email } });
    if (status !== 200) throw new AuthError("Couldn't send your code. Try again.");
  } else {
    await sendEmailCode(email);
  }
}

export async function verifyCode({ email, isNewAccount }, code) {
  checkThrottle();
  const { status, json } = await request('/auth/v1/verify', {
    body: { type: isNewAccount ? 'signup' : 'email', email, token: code.trim() },
  });
  if (status !== 200 || !json.access_token) {
    recordFailure();
    throw new AuthError("That code didn't match or has expired. Check your email or send a new one.");
  }
  clearThrottle();
  await storeTokens(json);
  return currentUser();
}

// ---------- Google (same flow as the Mac app) ----------
// The browser opens Supabase's Google page with a PKCE challenge; Google sends the person back to
// locken://auth-callback?code=…, which Windows hands to this app (deep link). The code is exchanged here with the
// verifier that never left this app, then an emailed code is still required, like every other sign-in.
export const GOOGLE_REDIRECT = 'locken://auth-callback';
let googleVerifier = null;

function base64Url(bytes) {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/** The Google sign-in page to open in the browser. */
export async function googleSignInUrl() {
  const random = crypto.getRandomValues(new Uint8Array(32));
  googleVerifier = base64Url(random);
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(googleVerifier)));
  const params = new URLSearchParams({
    provider: 'google',
    redirect_to: GOOGLE_REDIRECT,
    code_challenge: base64Url(digest),
    code_challenge_method: 's256',
  });
  return `${PROJECT_URL}/auth/v1/authorize?${params}`;
}

/** Finishes Google sign-in from the locken:// link: exchanges the code, then sends the emailed code. */
export async function finishGoogleSignIn(link) {
  let code = null;
  try {
    const url = new URL(link);
    if (url.protocol === 'locken:' && url.host === 'auth-callback') code = url.searchParams.get('code');
  } catch { /* not a link we handle */ }
  if (!code) return null;
  const verifier = googleVerifier;
  googleVerifier = null;
  if (!verifier) throw new AuthError('Google sign-in timed out. Choose Continue with Google again.');
  const { status, json } = await request('/auth/v1/token?grant_type=pkce', { body: { auth_code: code, code_verifier: verifier } });
  if (status !== 200 || !json.access_token) throw new AuthError("Google sign-in didn't finish. Try again.");
  const email = String(json.user?.email || '').toLowerCase();
  // Google proved the account; this PC is trusted only after the emailed code, as with a password.
  await request('/auth/v1/logout?scope=local', { body: {}, token: json.access_token });
  if (!email) throw new AuthError("Google sign-in didn't finish. Try again.");
  await sendEmailCode(email);
  return { email, isNewAccount: false };
}

// ---------- Forgot password (same steps as the Mac app) ----------
let recovery = null; // { access, refresh } kept in memory only until the new password is saved

/** Step 1: emails a 6-digit code. Same answer whether or not the email has an account. */
export async function startPasswordReset(email) {
  email = email.trim().toLowerCase();
  if (!isValidEmail(email)) throw new AuthError('Enter your email above, then choose Forgot password.');
  const { status } = await request('/auth/v1/otp', { body: { email, create_user: false } });
  if (status === 429) throw new AuthError('A code was just sent. Wait a minute before asking for another.');
  return email;
}

/** Step 2: the emailed code. Accounts with an authenticator app finish the reset on the Mac app. */
export async function verifyResetCode(email, code) {
  const { status, json } = await request('/auth/v1/verify', { body: { type: 'email', email, token: code.trim() } });
  if (status !== 200 || !json.access_token) {
    throw new AuthError("That code didn't match or has expired. Check your email or send a new one.");
  }
  const { json: user } = await request('/auth/v1/user', { token: json.access_token });
  const hasAuthenticator = (user.factors || []).some((f) => f.factor_type === 'totp' && f.status === 'verified');
  if (hasAuthenticator) {
    await request('/auth/v1/logout?scope=local', { body: {}, token: json.access_token });
    throw new AuthError('This account uses an authenticator app. Reset the password in Locken on your Mac.');
  }
  recovery = { access: json.access_token, refresh: json.refresh_token };
}

/** Step 3: the new password. Signs out every other device and signs in here. */
export async function finishPasswordReset(email, password) {
  if (!recovery) throw new AuthError('Start again from Forgot password.');
  const problem = passwordProblem(password, email);
  if (problem) throw new AuthError(problem);
  if (await isBreached(password)) throw new AuthError('This password has appeared in a data breach. Choose a different one.');
  const { status, json } = await request('/auth/v1/user', { body: { password }, token: recovery.access, method: 'PUT' });
  if (json.error_code === 'same_password') throw new AuthError("Choose a password that's different from your old one.");
  if (status === 429) throw new AuthError('Too many attempts. Wait a minute and try again.');
  if (status !== 200) throw new AuthError("Couldn't save your new password. Start again from Forgot password.");
  await request('/auth/v1/logout?scope=others', { body: {}, token: recovery.access });
  await storeTokens({ access_token: recovery.access, refresh_token: recovery.refresh });
  recovery = null;
  return currentUser();
}

export function cancelPasswordReset() { recovery = null; }

/** The verified user for the stored session, refreshing it once if the access token expired. */
export async function currentUser() {
  const session = await invoke('load_session');
  if (!session) return null;
  let { status, json } = await request('/auth/v1/user', { token: session.access });
  if (status === 401 || status === 403) {
    const refreshed = await request('/auth/v1/token?grant_type=refresh_token', { body: { refresh_token: session.refresh } });
    if (refreshed.status !== 200) {
      if (refreshed.status === 400 || refreshed.status === 401) await invoke('clear_session');
      return null;
    }
    await storeTokens(refreshed.json);
    ({ status, json } = await request('/auth/v1/user', { token: refreshed.json.access_token }));
  }
  if (status !== 200 || !json.id) return null;
  const latest = await invoke('load_session');
  const totp = (json.factors || []).find((f) => f.factor_type === 'totp' && f.status === 'verified');
  // An account with an authenticator app is signed in only at AAL2 (after its 6-digit code), as on the Mac.
  return { id: json.id, email: json.email, totpFactor: totp?.id || null, needsMFA: Boolean(totp) && assuranceLevel(latest?.access) !== 'aal2' };
}

/** The `aal` claim of an access token (the server checks the token itself; this only picks the next screen). */
function assuranceLevel(token) {
  try {
    const payload = token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
    return JSON.parse(atob(payload.padEnd(payload.length + ((4 - (payload.length % 4)) % 4), '='))).aal || null;
  } catch { return null; }
}

// ---------- Authenticator app (TOTP), same calls as the Mac app ----------
/** Challenge + verify with the stored session; on success the server returns an AAL2 session, which replaces it. */
async function challengeAndVerify(factorId, code) {
  if (!/^[0-9a-f-]{36}$/i.test(factorId) || !/^\d{6}$/.test(code.trim())) return false;
  const challenge = await withSession(`/auth/v1/factors/${factorId}/challenge`, { body: {} });
  if (challenge?.status !== 200 || !challenge.json.id) return false;
  const verified = await withSession(`/auth/v1/factors/${factorId}/verify`, { body: { challenge_id: challenge.json.id, code: code.trim() } });
  if (verified?.status === 429) throw new AuthError('Too many attempts. Wait a minute and try again.');
  if (verified?.status !== 200 || !verified.json.access_token) return false;
  await storeTokens(verified.json);
  return true;
}

/** Second sign-in step for accounts with an authenticator app. */
export async function verifyMFA(factorId, code) {
  checkThrottle();
  if (!(await challengeAndVerify(factorId, code))) recordFailure();
  else return currentUser();
  throw new AuthError("That code didn't match. Check your authenticator app and try again.");
}

/** Starts adding an authenticator app: the QR code (an SVG data: URL) and the key to type instead. */
export async function beginTOTPEnrollment() {
  const result = await withSession('/auth/v1/factors', { body: { factor_type: 'totp', friendly_name: `Locken ${Math.floor(Date.now() / 1000)}` } });
  const totp = result?.json?.totp;
  if (result?.status !== 200 || !result.json.id || !totp?.qr_code || !totp?.secret) throw new AuthError("Couldn't start authenticator setup. Try again.");
  return { factorId: result.json.id, qr: String(totp.qr_code), secret: String(totp.secret) };
}

/** Finishes adding the authenticator app once its first code checks out. */
export async function confirmTOTPEnrollment(factorId, code) {
  if (!(await challengeAndVerify(factorId, code))) throw new AuthError("That code didn't match. Check your authenticator app and try again.");
}

export async function removeTOTP(factorId) {
  if (!/^[0-9a-f-]{36}$/i.test(factorId)) return;
  const result = await withSession(`/auth/v1/factors/${factorId}`, { method: 'DELETE' });
  if (result?.status !== 200) throw new AuthError("Couldn't remove the authenticator app. Try again.");
}

/** Revokes the refresh token on the server first, then forgets it locally. */
export async function signOut() {
  const session = await invoke('load_session');
  if (session) {
    try {
      let { status } = await request('/auth/v1/logout?scope=local', { body: {}, token: session.access });
      if (status === 401) {
        const refreshed = await request('/auth/v1/token?grant_type=refresh_token', { body: { refresh_token: session.refresh } });
        if (refreshed.status === 200) {
          await request('/auth/v1/logout?scope=local', { body: {}, token: refreshed.json.access_token });
        }
      }
    } catch { /* offline: still forget it locally */ }
  }
  await invoke('clear_session');
}

/** Locken is for people 13 and older (US COPPA), same rule as the Mac app. */
export const MINIMUM_AGE = 13;

/** Age in whole years for a birth month (1-12) and year, as of today. The day isn't asked, so in the birthday month
 * itself the lower age is used (the same as the Mac app and the server). */
export function ageFrom(month, year, today = new Date()) {
  let age = today.getFullYear() - year;
  if (today.getMonth() + 1 <= month) age -= 1;
  return age;
}

/** Calls the API with the stored session, refreshing it once if the access token expired. */
async function withSession(path, options = {}) {
  const session = await invoke('load_session');
  if (!session) return null;
  let result = await request(path, { ...options, token: session.access });
  if (result.status === 401) {
    const refreshed = await request('/auth/v1/token?grant_type=refresh_token', { body: { refresh_token: session.refresh } });
    if (refreshed.status !== 200) return null;
    await storeTokens(refreshed.json);
    result = await request(path, { ...options, token: refreshed.json.access_token });
  }
  return result;
}

/**
 * The account's birth month and year and Terms agreement, kept on the account so every Mac and PC uses the same
 * answer. RLS limits the row to the signed-in user. null when the server can't be reached.
 */
export async function fetchConsent(userId) {
  const result = await withSession(`/rest/v1/profiles?select=birth_month,birth_year,terms_agreed_at&id=eq.${encodeURIComponent(userId)}`);
  if (!result || result.status !== 200 || !Array.isArray(result.json) || !result.json[0]) return null;
  const row = result.json[0];
  return { month: row.birth_month, year: row.birth_year, agreedAt: row.terms_agreed_at };
}

// ---------- Settings: account security, feedback, data (same calls as the Mac app) ----------
/** Signs out every device on this account, this one included (the session is revoked on the server). */
export async function signOutEverywhere() {
  await withSession('/auth/v1/logout?scope=global', { body: {} });
  await invoke('clear_session');
}

/** Emails a 6-digit code that confirms a password change. */
export async function sendPasswordChangeCode() {
  const result = await withSession('/auth/v1/reauthenticate', { method: 'GET' });
  if (result?.status === 429) throw new AuthError('Too many attempts. Wait a minute and try again.');
  if (result?.status !== 200) throw new AuthError("Couldn't send a code right now. Try again.");
}

/** Changes the password with the emailed code, then signs out every other device. */
export async function changePassword(email, password, code) {
  const problem = passwordProblem(password, email);
  if (problem) throw new AuthError(problem);
  if (await isBreached(password)) throw new AuthError('This password has appeared in a data breach. Choose a different one.');
  const result = await withSession('/auth/v1/user', { body: { password, nonce: code.trim() }, method: 'PUT' });
  if (result?.json?.error_code === 'same_password') throw new AuthError("Choose a password that's different from your current one.");
  if (result?.status === 429) throw new AuthError('Too many attempts. Wait a minute and try again.');
  if ([400, 401, 403, 422].includes(result?.status)) throw new AuthError("That code didn't match or has expired. Send a new one.");
  if (result?.status !== 200) throw new AuthError("Couldn't change your password right now. Try again.");
  await withSession('/auth/v1/logout?scope=others', { body: {} });
}

/** Sends a star rating and message to Locken's feedback table (RLS: only the sender can read it back). */
export async function submitFeedback(rating, message, appVersion) {
  const body = { message: String(message).slice(0, 2000), app_version: String(appVersion).slice(0, 20) };
  if (rating) body.rating = Math.min(Math.max(rating, 1), 5);
  const result = await withSession('/rest/v1/feedback', { body });
  if (!result || (result.status !== 201 && result.status !== 204)) throw new AuthError("Couldn't send your feedback right now. Try again.");
}

/** This account's own rows on Locken's servers, for Download My Data. */
export async function serverDataForExport() {
  const profile = await withSession('/rest/v1/profiles?select=id,email,full_name,avatar_url,plan,created_at,birth_month,birth_year,terms_agreed_at');
  const feedback = await withSession('/rest/v1/feedback?select=rating,message,app_version,created_at&order=created_at.desc');
  return { profile: profile?.json ?? null, feedback: feedback?.json ?? null };
}

/** Saves this PC's answer to the account. The server keeps the first answer only and refuses under-13 ages. */
export async function saveConsent(userId, { month, year, agreed }) {
  const body = {};
  if (month && year) Object.assign(body, { birth_month: month, birth_year: year });
  if (agreed) body.terms_agreed_at = 'now';
  if (!Object.keys(body).length) return false;
  const result = await withSession(`/rest/v1/profiles?id=eq.${encodeURIComponent(userId)}`, { body, method: 'PATCH' });
  return Boolean(result) && (result.status === 200 || result.status === 204);
}

/**
 * Permanently deletes the signed-in account through the `delete-account` Edge Function, which takes the user
 * from the verified token (never from anything this app sends). Then forgets the session on this PC.
 */
export async function deleteAccount() {
  const session = await invoke('load_session');
  if (!session) throw new AuthError('Sign in again, then delete the account.');
  let { status } = await request('/functions/v1/delete-account', { body: {}, token: session.access });
  if (status === 401) {
    const refreshed = await request('/auth/v1/token?grant_type=refresh_token', { body: { refresh_token: session.refresh } });
    if (refreshed.status !== 200) throw new AuthError('Sign in again, then delete the account.');
    await storeTokens(refreshed.json);
    ({ status } = await request('/functions/v1/delete-account', { body: {}, token: refreshed.json.access_token }));
  }
  if (status === 403) throw new AuthError('Enter your authenticator code first: sign out, sign back in, then delete the account.');
  if (status !== 200) throw new AuthError("Couldn't delete your account right now. Try again.");
  await invoke('clear_session');
}

// ---------- Admin (owner only; same Edge Function as the Mac app) ----------
// admin-overview checks on the server that the caller's verified account is listed in public.admins (and at aal2 when
// it has an authenticator app); everyone else gets 403, so these calls give nobody anything.

/** True only when the server says this account is an admin. Quiet: any failure means no Admin page. */
export async function isAdmin() {
  const result = await withSession('/functions/v1/admin-overview', { body: { check: true } }).catch(() => null);
  return result?.status === 200 && result.json?.admin === true;
}

/** Accounts, feedback, events and server health for the Admin page. */
export async function adminOverview() {
  const result = await withSession('/functions/v1/admin-overview', { body: {} });
  if (!result) throw new AuthError('Sign in again to continue.');
  if (result.status === 403) throw new AuthError(result.json?.error === 'Enter your authenticator code first' ? 'Enter your authenticator code first: sign out and back in.' : "This account isn't an admin.");
  if (result.status !== 200) throw new AuthError("Couldn't load the overview. Try again.");
  return result.json;
}

/** Bans (sign-in refused, every session ended) or unbans an account. The server refuses your own and admins'. */
export async function adminSetBan(userId, banned) {
  const result = await withSession('/functions/v1/admin-overview', { body: { action: banned ? 'ban' : 'unban', userId } });
  if (!result) throw new AuthError('Sign in again to continue.');
  if (result.status === 403) throw new AuthError("This account isn't an admin.");
  if (result.status !== 200) throw new AuthError(typeof result.json?.error === 'string' ? result.json.error.slice(0, 200) : "Couldn't change that account. Try again.");
}
