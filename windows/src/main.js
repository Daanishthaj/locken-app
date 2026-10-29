import { invoke } from '@tauri-apps/api/core';
import { emitTo, listen } from '@tauri-apps/api/event';
import { getCurrentWindow } from '@tauri-apps/api/window';
import * as auth from './auth.js';
import { openUrl } from '@tauri-apps/plugin-opener';
import { onOpenUrl, getCurrent } from '@tauri-apps/plugin-deep-link';
import { playLaunchReveal, launchRevealCss } from './launch-reveal.js';
import { playReceiptIntro, receiptCss } from './receipt.js';
import { createFluidGlassTime } from '../../shared/fluidglass-time.js';
import { mountGradualBlur } from './gradual-blur.js';
import { initAssistant, showAssistant, refreshAssistantSettings, resetAssistant, eraseAssistantData } from './assistant.js';
import { showAdmin, resetAdmin } from './admin.js';
import { mountButtonGlow } from './glow.js';
import { playFocusSound, unlockFocusSound } from './focus-sound.js';
import { LEGAL_DOCS, legalDocForLink, renderMarkdown } from './legal.js';

const $ = (id) => document.getElementById(id);
const screens = ['auth', 'code', 'mfa', 'reset', 'age', 'delete', 'too-young', 'credits', 'main'];
let user = null;
let weekDigest = null; // the Analytics week digest { text, written }, this run and account only
let pendingCode = null; // { email, isNewAccount }
let authMode = 'signin';
let session = null; // { goal, minutes, startedAt, endsAt, blocked, checkins, nextCheckIn }
let goalSource = 'manual'; // New: 'canvas' (pick an assignment) or 'manual' (type a goal)
let selectedAssignment = null; // the Canvas assignment picked on New
let tick = null;
let failures = 0;
let pendingBirth = null; // { month, year } from sign-up, saved once the account is verified
const SIGNUP_BLOCKED = 'locken.signupBlocked';

function show(name) {
  for (const s of screens) $(`screen-${s}`).hidden = s !== name;
  // Signed out: nothing of the last account's Assistant or Admin stays on screen.
  if (name !== 'main' && !user) { resetAssistant(); resetAdmin(); setAdmin(false); }
  // The sign-in screens are full-window like the Mac app's, without the top bar.
  document.body.classList.toggle('signed-out', ['auth', 'code', 'reset'].includes(name));
  const focusable = $(`screen-${name}`).querySelector('input, button');
  focusable?.focus();
}

/** Client-side backoff on top of Supabase's server rate limits: 1s, 2s, 4s… after each failure. */
async function guarded(button, errorEl, action) {
  errorEl.textContent = '';
  button.disabled = true;
  try {
    await action();
    failures = 0;
  } catch (error) {
    failures += 1;
    errorEl.textContent = error instanceof auth.AuthError ? error.message : 'Something went wrong. Try again.';
    await new Promise((r) => setTimeout(r, Math.min(1000 * 2 ** (failures - 1), 16000)));
  } finally {
    button.disabled = false;
  }
}

// ---------- Stats (per account, on this PC only) ----------
const today = () => new Date().toLocaleDateString('en-CA');
function statsKey() { return `locken.stats.${user.id}`; }
function loadStats() {
  try {
    const all = JSON.parse(localStorage.getItem(statsKey()) || '{}');
    return all[today()] || { minutes: 0, sessions: 0, blocked: 0 };
  } catch { return { minutes: 0, sessions: 0, blocked: 0 }; }
}
function saveStats(update) {
  let all = {};
  try { all = JSON.parse(localStorage.getItem(statsKey()) || '{}'); } catch { /* start fresh */ }
  const day = all[today()] || { minutes: 0, sessions: 0, blocked: 0 };
  all[today()] = update(day);
  localStorage.setItem(statsKey(), JSON.stringify(all));
}
/** Today's numbers show in the dashboard's stat cards; refresh the open one. */
function renderStats() {
  if (!$('metric-card').hidden) renderMetric($('metric-title').textContent);
}

const birthKey = (id) => `locken.birth.${id}`;

/** The birth month and year as numbers, or an error message. */
function readBirth(monthId, yearId) {
  const month = Number($(monthId).value);
  const year = Number($(yearId).value.trim());
  const thisYear = new Date().getFullYear();
  if (!month || !Number.isInteger(year) || year < thisYear - 120 || year > thisYear) {
    return { error: 'Enter your birth month and year.' };
  }
  return { month, year };
}

/** Under 13: no account on this PC (the same rule as the Mac app), and remember that sign-up isn't available. */
function refuseUnder13() {
  localStorage.setItem(SIGNUP_BLOCKED, '1');
  show('too-young');
}

/**
 * Makes this PC and the account agree on the birth month and year: the account's answer replaces this PC's, and if
 * the account has none yet, this PC's is uploaded. Offline, this PC's answer stands.
 */
async function syncBirth() {
  const server = await auth.fetchConsent(user.id).catch(() => null);
  if (!server) return;
  const local = JSON.parse(localStorage.getItem(birthKey(user.id)) || 'null');
  if (server.month && server.year) {
    localStorage.setItem(birthKey(user.id), JSON.stringify({ month: server.month, year: server.year, agreedAt: server.agreedAt || local?.agreedAt }));
  } else if (local) {
    await auth.saveConsent(user.id, { month: local.month, year: local.year, agreed: Boolean(local.agreedAt) }).catch(() => false);
  }
}

async function enterApp(verified) {
  user = verified;
  weekDigest = null;
  if (pendingBirth) {
    localStorage.setItem(birthKey(user.id), JSON.stringify(pendingBirth));
    pendingBirth = null;
  }
  await syncBirth();
  if (!localStorage.getItem(birthKey(user.id))) {
    show('age');
    return;
  }
  renderStats();
  renderGreeting();
  show('main');
  showPage('dashboard');
  restoreRunningSession();
  checkAdmin();
}

// ---------- Admin page: only for accounts the server says are admins (it checks again on every call) ----------
let adminUser = false;
function setAdmin(on) {
  adminUser = on;
  $('nav-admin').hidden = !on;
  $('rail-icons-bottom').classList.toggle('two', on);
  lastRailProps = {};
  updateRail();
  if (!on && shownPage === 'admin') showPage('dashboard');
}
async function checkAdmin() {
  const id = user?.id;
  const admin = await auth.isAdmin();
  if (user?.id === id) setAdmin(admin);
}

$('age-form').addEventListener('submit', (event) => {
  event.preventDefault();
  guarded($('age-submit'), $('age-error'), async () => {
    const birth = readBirth('age-month', 'age-year');
    if (birth.error) throw new auth.AuthError(birth.error);
    if (auth.ageFrom(birth.month, birth.year) < auth.MINIMUM_AGE) {
      // Same as the Mac app: an account that turns out to belong to someone under 13 is deleted, not just signed out.
      try { await auth.deleteAccount(); } catch { await auth.signOut(); }
      localStorage.removeItem(statsKey());
      user = null;
      refuseUnder13();
      return;
    }
    // Same consent as sign-up and the Mac app's ConsentGateView: the agreement box, plus a guardian's for 13–17.
    if (!$('age-agree-terms').checked) throw new auth.AuthError('Tick the box to agree to the Terms of Service and Privacy Policy.');
    if (auth.ageFrom(birth.month, birth.year) < 18 && !$('age-agree-guardian').checked) {
      throw new auth.AuthError('Your parent or guardian needs to agree to the terms too. Tick the second box with them.');
    }
    localStorage.setItem(birthKey(user.id), JSON.stringify({ ...birth, agreedAt: new Date().toISOString() }));
    await auth.saveConsent(user.id, { month: birth.month, year: birth.year, agreed: true }).catch(() => false);
    renderStats();
    renderGreeting();
    show('main');
    showPage('dashboard');
  });
});

// ---------- Sign in / create account ----------
function setAuthMode(mode) {
  authMode = mode;
  const signUp = mode === 'signup';
  for (const pill of document.querySelectorAll('.pill')) pill.setAttribute('aria-checked', String(pill.dataset.mode === mode));
  $('auth-submit').textContent = signUp ? 'Create Account' : 'Sign In';
  $('auth-password').autocomplete = signUp ? 'new-password' : 'current-password';
  $('auth-password').placeholder = signUp ? 'At least 8 characters' : 'Your password';
  $('forgot-row').hidden = signUp;
  $('legal-signin').hidden = signUp;
  $('birth-fields').hidden = !signUp;
  $('consent-fields').hidden = !signUp;
  $('auth-error').textContent = '';
  $('auth-notice').textContent = '';
  updateGoogleButton();
}
for (const pill of document.querySelectorAll('.pill')) pill.addEventListener('click', () => setAuthMode(pill.dataset.mode));

/** Sign-up details (age and agreements), checked the same way for email and Google sign-up. */
function readSignUpDetails() {
  if (localStorage.getItem(SIGNUP_BLOCKED)) throw new auth.AuthError("Sign-up isn't available on this PC.");
  const birth = readBirth('birth-month', 'birth-year');
  if (birth.error) throw new auth.AuthError(birth.error);
  if (auth.ageFrom(birth.month, birth.year) < auth.MINIMUM_AGE) return { tooYoung: true };
  // Same consent as the Mac app: an unticked agreement box, and a parent or guardian's agreement for 13–17.
  if (!$('agree-terms').checked) throw new auth.AuthError('Tick the box to agree to the Terms of Service and Privacy Policy.');
  if (auth.ageFrom(birth.month, birth.year) < 18 && !$('agree-guardian').checked) {
    throw new auth.AuthError('Your parent or guardian needs to agree to the terms too. Tick the second box with them.');
  }
  return { ...birth, agreedAt: new Date().toISOString() };
}

// Google can also create an account from Sign In, so it's off on a PC where sign-up has been stopped.
function updateGoogleButton() {
  $('google').disabled = Boolean(localStorage.getItem(SIGNUP_BLOCKED));
}

$('auth-form').addEventListener('submit', (event) => {
  event.preventDefault();
  const email = $('auth-email').value;
  const password = $('auth-password').value;
  guarded($('auth-submit'), $('auth-error'), async () => {
    if (!auth.isValidEmail(email)) throw new auth.AuthError('Enter a valid email address.');
    if (authMode === 'signup') {
      const typo = auth.emailTypoSuggestion(email);
      if (typo) throw new auth.AuthError(`Did you mean ${typo}? Check the email and try again.`);
      const details = readSignUpDetails();
      if (details.tooYoung) {
        refuseUnder13();
        return;
      }
      pendingBirth = details;
      const problem = auth.passwordProblem(password, email);
      if (problem) throw new auth.AuthError(problem);
      if (await auth.isBreached(password)) throw new auth.AuthError('This password has appeared in a data breach. Choose a different one.');
      pendingCode = await auth.signUp(email, password);
    } else {
      if (!password) throw new auth.AuthError(auth.INVALID_CREDENTIALS);
      pendingCode = await auth.signIn(email, password);
    }
    $('auth-password').value = '';
    $('code-hint').textContent = `If ${pendingCode.email} has a Locken account, we emailed it a 6-digit code. Enter it below.`;
    $('code-input').value = '';
    show('code');
  });
});

$('code-form').addEventListener('submit', (event) => {
  event.preventDefault();
  $('code-notice').textContent = '';
  guarded($('code-submit'), $('code-error'), async () => {
    const code = $('code-input').value;
    if (!/^\d{6,10}$/.test(code.trim())) throw new auth.AuthError('Enter the code from your email.');
    const verified = await auth.verifyCode(pendingCode, code);
    if (!verified) throw new auth.AuthError("Your code worked, but Locken couldn't finish signing in. Try again.");
    pendingCode = null;
    if (verified.needsMFA) { openMFA(verified); return; }
    const welcome = playReceiptIntro();
    await enterApp(verified);
    await welcome;
  });
});

// ---------- Authenticator code (accounts with two-factor authentication) ----------
let mfaFactor = null;
function openMFA(verified) {
  mfaFactor = verified.totpFactor;
  $('mfa-input').value = '';
  $('mfa-error').textContent = '';
  show('mfa');
  $('mfa-input').focus();
}
$('mfa-form').addEventListener('submit', (event) => {
  event.preventDefault();
  guarded($('mfa-submit'), $('mfa-error'), async () => {
    const code = $('mfa-input').value.trim();
    if (!/^\d{6}$/.test(code)) throw new auth.AuthError('Enter the 6-digit code from your authenticator app.');
    const verified = await auth.verifyMFA(mfaFactor, code);
    if (!verified || verified.needsMFA) throw new auth.AuthError("Locken couldn't finish signing in. Try again.");
    mfaFactor = null;
    const welcome = playReceiptIntro();
    await enterApp(verified);
    await welcome;
  });
});
$('mfa-back').addEventListener('click', async () => { mfaFactor = null; await auth.signOut(); show('auth'); });

$('code-resend').addEventListener('click', () => {
  $('code-notice').textContent = '';
  guarded($('code-resend'), $('code-error'), async () => {
    await auth.resendCode(pendingCode);
    $('code-notice').textContent = 'A new code is on its way.';
  });
});

$('code-back').addEventListener('click', () => { pendingCode = null; show('auth'); });

// ---------- Google sign-in ----------
$('google').addEventListener('click', () => {
  $('auth-error').textContent = '';
  if (authMode === 'signup') {
    // A new account through Google needs the same age check and agreement first.
    try {
      const details = readSignUpDetails();
      if (details.tooYoung) { refuseUnder13(); return; }
      pendingBirth = details;
    } catch (error) {
      $('auth-error').textContent = error.message;
      return;
    }
  }
  $('google-info').hidden = false;
  $('google-continue').focus();
});
$('google-cancel').addEventListener('click', () => { $('google-info').hidden = true; });
$('google-continue').addEventListener('click', async () => {
  $('google-info').hidden = true;
  try {
    await openUrl(await auth.googleSignInUrl());
    $('auth-notice').textContent = 'Finish signing in with Google in your browser, then come back here.';
  } catch {
    $('auth-error').textContent = "Couldn't open Google sign-in. Try again.";
  }
});

/** A locken:// link from Google's sign-in page: exchange it, then ask for the emailed code. */
async function handleSignInLink(urls) {
  const link = (urls || []).find((u) => String(u).startsWith('locken://'));
  if (!link || user) return;
  $('auth-notice').textContent = '';
  try {
    const result = await auth.finishGoogleSignIn(link);
    if (!result) return;
    pendingCode = result;
    $('code-hint').textContent = `We emailed a 6-digit code to ${result.email}. Enter it below.`;
    $('code-input').value = '';
    show('code');
  } catch (error) {
    show('auth');
    $('auth-error').textContent = error instanceof auth.AuthError ? error.message : "Google sign-in didn't finish. Try again.";
  }
}
onOpenUrl(handleSignInLink).catch(() => {});

// ---------- Forgot password ----------
let resetEmail = null;
let resetStep = 'code';
$('forgot').addEventListener('click', () => {
  guarded($('forgot'), $('auth-error'), async () => {
    resetEmail = await auth.startPasswordReset($('auth-email').value);
    resetStep = 'code';
    $('reset-title').textContent = 'Check your email';
    $('reset-hint').textContent = `If there's a Locken account for ${resetEmail}, we sent it a 6-digit code. Enter it to choose a new password.`;
    $('reset-code-form').hidden = false;
    $('reset-password-form').hidden = true;
    $('reset-code').value = '';
    $('reset-error').textContent = '';
    show('reset');
  });
});
function submitReset() {
  guarded($('reset-submit'), $('reset-error'), async () => {
    if (resetStep === 'code') {
      const code = $('reset-code').value;
      if (!/^\d{6,10}$/.test(code.trim())) throw new auth.AuthError('Enter the code from your email.');
      await auth.verifyResetCode(resetEmail, code);
      resetStep = 'password';
      $('reset-title').textContent = 'Choose a new password';
      $('reset-hint').textContent = 'Saving it signs you out on every other device.';
      $('reset-code-form').hidden = true;
      $('reset-password-form').hidden = false;
      $('reset-password').focus();
    } else {
      const verified = await auth.finishPasswordReset(resetEmail, $('reset-password').value);
      $('reset-password').value = '';
      resetEmail = null;
      if (verified) enterApp(verified); else show('auth');
    }
  });
}
$('reset-submit').addEventListener('click', submitReset);
$('reset-code-form').addEventListener('submit', (event) => { event.preventDefault(); submitReset(); });
$('reset-password-form').addEventListener('submit', (event) => { event.preventDefault(); submitReset(); });
$('reset-back').addEventListener('click', () => { auth.cancelPasswordReset(); resetEmail = null; show('auth'); });


$('sign-out').addEventListener('click', async () => {
  $('sign-out').disabled = true;
  await auth.signOut();
  user = null;
  $('sign-out').disabled = false;
  show('auth');
});

$('delete-account').addEventListener('click', () => { $('delete-error').textContent = ''; show('delete'); });
$('delete-cancel').addEventListener('click', () => { show('main'); showPage('settings'); });
$('delete-confirm').addEventListener('click', () => {
  guarded($('delete-confirm'), $('delete-error'), async () => {
    await auth.deleteAccount();
    localStorage.removeItem(statsKey());
    localStorage.removeItem(birthKey(user.id));
    localStorage.removeItem(habitsKey());
    localStorage.removeItem(notesKey());
    localStorage.removeItem(blockKey());
    localStorage.removeItem(nameKey(user.id));
    await invoke('ai_remove_key', { account: user.id }).catch(() => {});
    await eraseAssistantData(user.id);
    await invoke('canvas_unlink', { account: user.id }).catch(() => {});
    localStorage.removeItem(checkedKey());
    user = null;
    show('auth');
    $('auth-error').textContent = 'Your account was deleted.';
  });
});

$('open-credits').addEventListener('click', () => show('credits'));
$('credits-back').addEventListener('click', () => { show('main'); showPage('settings'); });

function updateGuardianRow() {
  const birth = readBirth('birth-month', 'birth-year');
  const minor = !birth.error && auth.ageFrom(birth.month, birth.year) < 18;
  $('guardian-row').hidden = !minor;
}
function updateAgeGuardianRow() {
  const birth = readBirth('age-month', 'age-year');
  $('age-guardian-row').hidden = Boolean(birth.error) || auth.ageFrom(birth.month, birth.year) >= 18;
}
$('age-month').addEventListener('change', updateAgeGuardianRow);
$('age-year').addEventListener('input', updateAgeGuardianRow);
$('birth-month').addEventListener('change', updateGuardianRow);
$('birth-year').addEventListener('input', updateGuardianRow);

// Terms and Privacy links open the bundled document in the reader (it works offline); other links open in the default
// browser (only Locken's own site is allowed by the capability).
document.querySelectorAll('a[target="_blank"]').forEach((link) => {
  link.addEventListener('click', (event) => {
    event.preventDefault();
    const doc = legalDocForLink(link.href);
    if (doc) openLegal(doc); else openUrl(link.href).catch(() => {});
  });
});
document.querySelectorAll('[data-legal]').forEach((button) => {
  button.addEventListener('click', () => openLegal(LEGAL_DOCS.find((d) => d.key === button.dataset.legal)));
});

// ---------- Legal reader (the Mac app's LegalReaderView) ----------
let legalOpener = null;
let legalDoc = null;
function showLegal(doc) {
  legalDoc = doc;
  $('legal-title').textContent = doc.title;
  for (const tab of $('legal-tabs').children) {
    const on = tab.dataset.key === doc.key;
    tab.setAttribute('aria-checked', String(on));
    tab.tabIndex = on ? 0 : -1;
  }
  const body = $('legal-body');
  body.replaceChildren();
  // The drafts still hold details like the company name in [brackets].
  if (doc.text.includes('[Company Name]')) {
    const note = document.createElement('p');
    note.className = 'muted small';
    note.textContent = 'Draft under legal review. Details in [brackets] will be filled in before release.';
    body.append(note);
  }
  body.append(renderMarkdown(doc.text, (href) => {
    const linked = legalDocForLink(href);
    if (linked) showLegal(linked); else openUrl(href).catch(() => {});
  }));
  body.scrollTop = 0;
}
function openLegal(doc) {
  const reader = $('legal-reader');
  if (reader.hidden) legalOpener = document.activeElement;
  reader.hidden = false;
  showLegal(doc);
  $('legal-close').focus();
}
function closeLegal() {
  $('legal-reader').hidden = true;
  legalOpener?.focus?.();
}
for (const doc of LEGAL_DOCS) {
  const tab = document.createElement('button');
  tab.type = 'button';
  tab.className = 'pill';
  tab.setAttribute('role', 'radio');
  tab.dataset.key = doc.key;
  tab.textContent = doc.short;
  tab.addEventListener('click', () => showLegal(doc));
  $('legal-tabs').append(tab);
}
$('legal-close').addEventListener('click', closeLegal);
$('legal-reader').addEventListener('keydown', (event) => {
  if (event.key === 'Escape') { event.preventDefault(); closeLegal(); return; }
  // Arrow keys move between the document tabs, like a radio group.
  if ((event.key === 'ArrowRight' || event.key === 'ArrowLeft') && event.target.dataset?.key) {
    event.preventDefault();
    const i = LEGAL_DOCS.findIndex((d) => d.key === legalDoc.key);
    const next = LEGAL_DOCS[(i + (event.key === 'ArrowRight' ? 1 : LEGAL_DOCS.length - 1)) % LEGAL_DOCS.length];
    showLegal(next);
    $('legal-tabs').querySelector(`[data-key="${next.key}"]`).focus();
    return;
  }
  // The dialog is modal: Tab stays inside it.
  if (event.key === 'Tab') {
    const items = [...$('legal-reader').querySelectorAll('button, [tabindex="0"]')].filter((x) => x.tabIndex >= 0);
    const first = items[0], last = items[items.length - 1];
    if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
    else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
  }
});

// ---------- Pages (sidebar, like the Mac app) ----------
const pages = ['dashboard', 'focus', 'assistant', 'habits', 'analytics', 'notes', 'settings', 'admin'];
function showPage(name) {
  // Like the Mac: while a session runs, Home ("New") isn't shown; the Focus page stays up.
  if (name === 'dashboard' && session && !session.paused) name = 'focus';
  if (name === 'admin' && !adminUser) name = 'dashboard';
  for (const p of pages) $(`page-${p}`).hidden = p !== name;
  for (const item of document.querySelectorAll('.nav-item')) item.classList.toggle('selected', item.dataset.page === name);
  shownPage = name;
  applyTheme(name);
  updateRail();
  $('orbital').classList.remove('expanded');
  $('metric-card').hidden = true;
  if (name === 'habits') renderHabits();
  if (name === 'analytics') { renderAnalytics(); renderWeekDigest(); }
  if (name === 'notes') renderNotes();
  if (name === 'settings') { renderBlockedApps(); renderSettingsHabitFeatures(); renderTwoFactor(); refreshAssistantSettings(); }
  if (name === 'assistant') showAssistant();
  if (name === 'admin') showAdmin();
}
for (const item of document.querySelectorAll('.nav-item')) item.addEventListener('click', () => showPage(item.dataset.page));

// ---------- Collapsible sidebar (the Mac app's SidebarRail): the pages as React Bits GlassIcons buttons ----------
// The buttons run in an iframe; the app tells it what to show, and it reports presses as "select:<id>".
const RAIL_PAGES = [
  { id: 'new', label: 'New', page: 'dashboard' },
  { id: 'focus', label: 'Focus', page: 'focus' },
  { id: 'assistant', label: 'Assistant', page: 'assistant' },
  { id: 'habits', label: 'Habits', page: 'habits' },
  { id: 'analytics', label: 'Analytics', page: 'analytics' },
  { id: 'notes', label: 'Notes', page: 'notes' },
  { id: 'settings', label: 'Settings', page: 'settings' },
  { id: 'admin', label: 'Admin', page: 'admin' },
];
/** Kept apart at the bottom of the rail, like the Mac's Settings and Admin. */
const RAIL_BOTTOM = new Set(['settings', 'admin']);
/** The rail's pages for this account (Admin only for admins). */
const railPages = () => RAIL_PAGES.filter((p) => p.id !== 'admin' || adminUser);
const SIDEBAR_KEY = 'locken.sidebar.collapsed';
/** The window is too narrow for the full sidebar (it can shrink to 640 px): the rail is used instead, whatever was chosen. */
const NARROW_WINDOW = matchMedia('(max-width: 860px)');
/** What the student chose with the toggle, remembered between launches. */
let userCollapsed = false;
let railReady = false;
/** What each rail frame was last told, so an unchanged state isn't sent again. */
let lastRailProps = {};
let shownPage = 'dashboard';
/** While the rail's tiles close, before the sidebar widens. */
let railClosing = false;
function updateRail() {
  const top = $('rail-icons');
  const bottom = $('rail-icons-bottom');
  if (!top || !bottom || !railReady || !document.querySelector('.sidebar').classList.contains('collapsed')) return;
  // Same spacing rule as the Mac: the gap between buttons shrinks a little when space is short.
  const list = railPages();
  const gap = Math.max(18, Math.min(30, Math.round((top.clientHeight + bottom.clientHeight - 60 - list.length * 40) / list.length)));
  const value = (list.find((p) => p.page === shownPage) || list[0]).id;
  for (const [frame, group] of [[top, list.filter((p) => !RAIL_BOTTOM.has(p.id))], [bottom, list.filter((p) => RAIL_BOTTOM.has(p.id))]]) {
    const props = {
      items: JSON.stringify(group.map((p) => ({ id: p.id, label: p.label, icon: p.id }))),
      value,
      size: '40',
      gap: String(gap),
      closing: railClosing ? '1' : '',
    };
    const json = JSON.stringify(props);
    if (json === lastRailProps[frame.id]) continue;
    lastRailProps[frame.id] = json;
    try { frame.contentWindow.updateProps(props); } catch { delete lastRailProps[frame.id]; }
  }
}
/** While the sidebar slides (folding or unfolding), so a second press waits. */
let sidebarSliding = false;
const SLIDE_MS = 400;
function setSidebarCollapsed(collapsed, { remember = true, slide = false } = {}) {
  const frames = [$('rail-icons'), $('rail-icons-bottom')];
  const sidebar = document.querySelector('.sidebar');
  const toggle = $('side-toggle');
  toggle.setAttribute('aria-expanded', String(!collapsed));
  toggle.setAttribute('aria-label', collapsed ? 'Expand the sidebar' : 'Collapse the sidebar');
  toggle.title = collapsed ? 'Expand the sidebar' : 'Collapse the sidebar';
  if (remember) {
    userCollapsed = collapsed;
    try { localStorage.setItem(SIDEBAR_KEY, collapsed ? '1' : '0'); } catch { /* not remembered this time */ }
  }
  // The rail loads now, so its tiles are ready when it appears.
  for (const frame of frames) if (collapsed && !frame.getAttribute('src')) frame.setAttribute('src', frame.dataset.src);
  const settle = () => {
    sidebar.classList.toggle('collapsed', collapsed);
    lastRailProps = {};
    updateRail();
  };
  if (!slide || matchMedia('(prefers-reduced-motion: reduce)').matches) return settle();
  // Like the Mac: folding slides the pages out to the left while the width follows, then the rail slides in; unfolding is the reverse.
  sidebarSliding = true;
  if (collapsed) {
    sidebar.classList.add('collapsing');
    setTimeout(() => {
      sidebar.classList.add('entering');
      settle();
      sidebar.classList.remove('collapsing');
      setTimeout(() => { sidebar.classList.remove('entering'); sidebarSliding = false; }, SLIDE_MS);
    }, SLIDE_MS);
  } else {
    sidebar.classList.add('expanding');
    settle();
    setTimeout(() => { sidebar.classList.remove('expanding'); sidebarSliding = false; }, SLIDE_MS);
  }
}
/** The rail in a narrow window, otherwise what the student chose. The saved choice is never changed by the window's size. */
function fitSidebar() {
  const sidebar = document.querySelector('.sidebar');
  sidebar.classList.toggle('compact', NARROW_WINDOW.matches);
  const wanted = NARROW_WINDOW.matches || userCollapsed;
  if (sidebar.classList.contains('collapsed') !== wanted) setSidebarCollapsed(wanted, { remember: false });
}
NARROW_WINDOW.addEventListener('change', fitSidebar);
$('side-toggle').addEventListener('click', () => {
  if (railClosing || sidebarSliding || NARROW_WINDOW.matches) return;
  if (!document.querySelector('.sidebar').classList.contains('collapsed')) return setSidebarCollapsed(true, { slide: true });
  // Opening: the rail's tiles close first (their intro played backwards), then the sidebar widens. Same timing as the Mac.
  if (!railReady || matchMedia('(prefers-reduced-motion: reduce)').matches) return setSidebarCollapsed(false, { slide: true });
  railClosing = true;
  updateRail();
  setTimeout(() => { railClosing = false; setSidebarCollapsed(false, { slide: true }); }, 600);
});
// The rail page is in an iframe of this same origin, so it reports "ready" and "select:<id>" by calling this directly (a page
// from another origin can't reach it). A message listener isn't used: it would need its own origin checks.
window.__lockenRailMessage = (value) => {
  const message = String(value);
  if (message === 'ready') { railReady = true; lastRailProps = {}; updateRail(); }
  else if (message.startsWith('select:')) {
    const picked = railPages().find((p) => p.id === message.slice(7));
    if (picked) showPage(picked.page);
  }
};
window.addEventListener('resize', updateRail);
try { userCollapsed = localStorage.getItem(SIDEBAR_KEY) === '1'; } catch { /* expanded */ }
fitSidebar();
// The Mac's gradual blur along the bottom of every scrolling page.
mountGradualBlur(document.querySelector('.pages'));
// Browsers only allow sound after a click: the first one readies the focus-mode sound.
document.addEventListener('pointerdown', unlockFocusSound, { once: true });
$('focus-new').addEventListener('click', () => $('own-goal').focus());

// ---------- Keyboard shortcuts: the Mac app's menu shortcuts, with Ctrl in place of Command ----------
const SHORTCUT_PAGES = { 1: 'dashboard', 2: 'notes', 3: 'habits', 4: 'settings', 5: 'focus', 7: 'analytics' };
const modalOpen = () => ['commit-gate', 'pause-dialog', 'done-card', 'habit-editor', 'legal-reader'].some((id) => !$(id).hidden)
  || Boolean(document.querySelector('.pages.intro-playing'));
document.addEventListener('keydown', (event) => {
  if (!event.ctrlKey || event.altKey || event.metaKey || $('screen-main').hidden || modalOpen()) return;
  const key = event.key.toLowerCase();
  if (!event.shiftKey && SHORTCUT_PAGES[event.key]) {
    event.preventDefault();
    showPage(SHORTCUT_PAGES[event.key]);
  } else if (!event.shiftKey && key === 'n') {
    event.preventDefault();
    if (session) $('pause-toggle').click();
    else {
      // No session: open New with the goal field ready.
      showPage('dashboard');
      [$('goal'), $('own-goal')].find((field) => field.offsetParent)?.focus();
    }
  } else if (event.shiftKey && key === 'p' && session) {
    event.preventDefault();
    $('pause-toggle').click();
  } else if (event.shiftKey && key === 'n') {
    event.preventDefault();
    showPage('notes');
    $('note-new').click();
  }
});

// ---------- Offline and unexpected failures ----------
const updateOnline = () => { $('offline-bar').hidden = navigator.onLine; };
addEventListener('online', updateOnline);
addEventListener('offline', updateOnline);
updateOnline();
// A failed request or a bug in one card must not end in a red console error or a stuck screen. Only the kind of failure is
// noted, never its contents, which can hold tokens or what the student wrote.
addEventListener('unhandledrejection', (event) => {
  event.preventDefault();
  console.warn(`Locken: a background task failed (${event.reason?.name || 'error'})`);
});

// The Mac app's SignatureText: the name writes itself like a signature (outline drawn left to right, then filled),
// once per account each time the app runs. Reduce Motion shows it written.
const signaturePlayed = new Set();
const SVG_NS = 'http://www.w3.org/2000/svg';
async function writeSignature(target, text, key) {
  const size = 34;
  const font = `400 ${size}px "Locken Script"`;
  await document.fonts.load(font).catch(() => {});
  const measure = document.createElement('canvas').getContext('2d');
  measure.font = `${font}, "Segoe Script", cursive`;
  const m = measure.measureText(text);
  const pad = 3;
  const width = Math.ceil(m.actualBoundingBoxLeft + m.actualBoundingBoxRight) + pad * 2;
  const height = Math.ceil(m.actualBoundingBoxAscent + m.actualBoundingBoxDescent) + pad * 2;
  const svg = document.createElementNS(SVG_NS, 'svg');
  svg.setAttribute('class', 'signature');
  svg.setAttribute('viewBox', `0 0 ${width} ${height}`);
  svg.setAttribute('width', width);
  svg.setAttribute('height', height);
  svg.setAttribute('role', 'img');
  svg.setAttribute('aria-label', text);
  const words = document.createElementNS(SVG_NS, 'text');
  words.setAttribute('x', m.actualBoundingBoxLeft + pad);
  words.setAttribute('y', m.actualBoundingBoxAscent + pad);
  words.textContent = text; // textContent: never parsed as markup
  const play = !window.matchMedia('(prefers-reduced-motion: reduce)').matches && !signaturePlayed.has(`${key}|${text}`);
  if (play) {
    signaturePlayed.add(`${key}|${text}`);
    // A soft-edged wipe moves left to right with the pen, so the letters are written in reading order.
    const id = `sig-${Math.random().toString(36).slice(2, 8)}`;
    svg.innerHTML = `<defs><linearGradient id="${id}-g"><stop offset="0.85" stop-color="#fff"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>`
      + `<mask id="${id}" maskUnits="userSpaceOnUse" x="0" y="0" width="${width}" height="${height}"><rect class="sig-wipe" x="0" y="0" width="${Math.ceil(width * 1.18)}" height="${height}" fill="url(#${id}-g)"/></mask></defs>`;
    words.setAttribute('mask', `url(#${id})`);
  }
  svg.append(words);
  target.replaceChildren(svg);
  if (!play) return;
  // Start writing once the startup reveal and receipt are gone, so it plays where it can be seen.
  svg.style.visibility = 'hidden';
  while (document.querySelector('.launch, .receipt-intro')) await new Promise((resolve) => setTimeout(resolve, 100));
  svg.style.visibility = '';
  svg.classList.add('writing');
}

/** The name Locken calls you by: the one saved in Settings, else from your email, or '' if none. */
const nameKey = (id) => `locken.name.${id}`;
function displayName() {
  const saved = user ? (localStorage.getItem(nameKey(user.id)) || '').trim() : '';
  if (saved) return saved;
  const local = (user?.email || '').split('@')[0].split(/[._+-]/)[0].replace(/[^a-zA-Z]/g, '');
  return local ? local[0].toUpperCase() + local.slice(1).toLowerCase() : '';
}

function renderGreeting() {
  setupDraft = null; // the habit setup card's choices belong to whoever was signed in
  setupStart = 'Start with examples';
  const name = displayName();
  if (name) writeSignature($('greeting-name'), `${name}?`, user.id);
  else $('greeting-name').textContent = 'today?';
  $('settings-email').textContent = user?.email ? `Signed in as ${user.email}` : '';
  $('name-input').value = displayName();
  $('name-save').disabled = true;
  updateProfileCard();
  refreshAI();
  refreshCanvasStatus();
}

// ---------- Habit Tracker (the Mac app's HabitTrackerView; per account, on this PC only) ----------
const dayKey = (date) => date.toLocaleDateString('en-CA');
const habitsKey = () => `locken.habits.${user.id}`;
function loadHabits() {
  try { return JSON.parse(localStorage.getItem(habitsKey()) || '[]'); } catch { return []; }
}
function saveHabits(list) { localStorage.setItem(habitsKey(), JSON.stringify(list)); }

// Habits keep the Mac's fields: symbol, category, schedule (every day, chosen weekdays, or N times a week),
// an optional daily amount, and automatic ticking after a long enough focus session.
const HABIT_ICONS = {
  sparkles: 'M12 3l1.8 4.7L18.5 9.5l-4.7 1.8L12 16l-1.8-4.7L5.5 9.5l4.7-1.8zM18.5 15l.8 2.2 2.2.8-2.2.8-.8 2.2-.8-2.2-2.2-.8 2.2-.8z',
  brain: 'M9 4a3 3 0 0 0-3 3 3 3 0 0 0-2 5 3 3 0 0 0 2 5 3 3 0 0 0 6 1V5a3 3 0 0 0-3-1zM15 4a3 3 0 0 1 3 3 3 3 0 0 1 2 5 3 3 0 0 1-2 5 3 3 0 0 1-6 1',
  book: 'M4 5a2 2 0 0 1 2-2h13v16H6a2 2 0 0 0-2 2zM4 21V5M8 7h7',
  pencil: 'M4 20h4L19 9l-4-4L4 16zM13.5 6.5l4 4',
  cards: 'M4 7h12v13H4zM8 4h12v13',
  run: 'M13 4a1.5 1.5 0 1 0 0 .1M10 21l2-6 3 2v5M7 12l3-4 4 1 2 3 3 1M12 15l-2-3',
  dumbbell: 'M3 10v4M6 8v8M18 8v8M21 10v4M6 12h12',
  drop: 'M12 3s6 6.5 6 11a6 6 0 0 1-12 0c0-4.5 6-11 6-11z',
  leaf: 'M5 19c0-9 6-14 15-14 0 9-5 15-14 15M5 19l7-7',
  moon: 'M20 14A8 8 0 1 1 10 4a6 6 0 0 0 10 10zM17 4l.5 1.5L19 6l-1.5.5L17 8l-.5-1.5L15 6l1.5-.5z',
  'phone-off': 'M8 3h8a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H8a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1zM3 3l18 18',
  hand: 'M8 13V6a1.5 1.5 0 0 1 3 0v5M11 11V4.5a1.5 1.5 0 0 1 3 0V11M14 11V6a1.5 1.5 0 0 1 3 0v8a6 6 0 0 1-6 6h-1a5 5 0 0 1-4-2l-3-4a1.5 1.5 0 0 1 2.3-2L8 14',
};
const HABIT_CATEGORIES = ['Focus', 'Discipline', 'Academics', 'Recovery', 'Health'];
const SCHEDULE_OPTIONS = ['Every day', 'Weekdays', 'Pick days', 'Times a week'];
const DAY_NAMES = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
/** A line icon: a name from HABIT_ICONS, or a raw SVG path. */
function habitIcon(name, size = 16) {
  const svg = document.createElementNS(SVG_NS, 'svg');
  svg.setAttribute('viewBox', '0 0 24 24');
  svg.setAttribute('width', size);
  svg.setAttribute('height', size);
  svg.setAttribute('class', 'nav-svg habit-icon');
  svg.setAttribute('aria-hidden', 'true');
  const path = document.createElementNS(SVG_NS, 'path');
  path.setAttribute('d', HABIT_ICONS[name] || (name?.startsWith('M') ? name : HABIT_ICONS.sparkles));
  svg.append(path);
  return svg;
}
/** Older habits (name and ticked days only) get the Mac's defaults. */
function normalizeHabit(h) {
  return { symbol: 'sparkles', category: 'Focus', schedule: { type: 'daily' }, track: { type: 'manual' }, goalAmount: null, goalUnit: '', progress: {}, done: [], createdAt: Date.now(), ...h };
}
/** 1 = Monday … 7 = Sunday. */
const isoWeekday = (d) => ((d.getDay() + 6) % 7) + 1;
const isScheduled = (h, d) => h.schedule.type !== 'weekdays' || h.schedule.days.includes(isoWeekday(d));
function isHabitDone(h, d) {
  const key = dayKey(d);
  return h.goalAmount > 0 ? (h.progress[key] || 0) >= h.goalAmount : h.done.includes(key);
}
const startOfDay = (d) => { const x = new Date(d); x.setHours(0, 0, 0, 0); return x; };
const addDays = (d, n) => { const x = new Date(d); x.setDate(x.getDate() + n); return x; };
const mondayOf = (d) => addDays(startOfDay(d), -(isoWeekday(d) - 1));
function weekCount(h, monday, through) {
  let count = 0;
  for (let d = monday; d <= through; d = addDays(d, 1)) if (isHabitDone(h, d)) count += 1;
  return count;
}
/** Consecutive scheduled days done (or, for "times a week", weeks that hit the target). Today doesn't break a
 * streak until it's over. Same rules as the Mac's HabitMath. */
function habitStreak(h) {
  const today = startOfDay(new Date());
  if (h.schedule.type === 'times') {
    let weeks = weekCount(h, mondayOf(today), today) >= h.schedule.times ? 1 : 0;
    for (let monday = addDays(mondayOf(today), -7), i = 0; i < 260; i += 1, monday = addDays(monday, -7)) {
      if (weekCount(h, monday, addDays(monday, 6)) < h.schedule.times) break;
      weeks += 1;
    }
    return weeks;
  }
  let streak = isScheduled(h, today) && isHabitDone(h, today) ? 1 : 0;
  for (let d = addDays(today, -1), i = 0; i < 3650; i += 1, d = addDays(d, -1)) {
    if (!isScheduled(h, d)) continue;
    if (!isHabitDone(h, d)) break;
    streak += 1;
  }
  return streak;
}
function bestStreak(h) {
  const today = startOfDay(new Date());
  const keys = [...h.done, ...Object.keys(h.progress)].sort();
  const first = keys.length ? new Date(`${keys[0]}T12:00:00`) : startOfDay(new Date(h.createdAt));
  let best = 0;
  let run = 0;
  if (h.schedule.type === 'times') {
    for (let monday = mondayOf(first); monday <= today; monday = addDays(monday, 7)) {
      run = weekCount(h, monday, addDays(monday, 6)) >= h.schedule.times ? run + 1 : 0;
      best = Math.max(best, run);
    }
    return best;
  }
  for (let d = startOfDay(first); d <= today; d = addDays(d, 1)) {
    if (!isScheduled(h, d)) continue;
    if (isHabitDone(h, d)) { run += 1; best = Math.max(best, run); } else if (d < today) run = 0;
  }
  return best;
}
// Habit features (the Mac app's HabitFeatures). Reminders aren't on Windows yet, so that switch isn't shown.
const habitFeaturesKey = () => `locken.habitFeatures.${user.id}`;
const HABIT_FEATURE_ROWS = [
  { key: 'today', icon: 'M5 12.5 10 17.5 19 7', title: 'Today view', detail: "A quick strip of today's habits with a progress ring." },
  { key: 'history', icon: 'M12 3c1 4 5 5 5 10a5 5 0 0 1-10 0c0-2 1-3 2-4 0 2 1 3 2 3 0-3-1-5 1-9z', title: 'Streaks & history', detail: 'Browse past weeks and see a 12-week map for each habit.' },
  { key: 'autoTracking', icon: 'M5 19 15 9M14 4l1 2 2 1-2 1-1 2-1-2-2-1 2-1zM19 11l.6 1.4L21 13l-1.4.6L19 15l-.6-1.4L17 13l1.4-.6z', title: 'Auto-tracking', detail: 'Habits that tick themselves after a long enough focus session.' },
];
function habitFeatures() {
  try { return { today: true, history: true, autoTracking: true, hasOnboarded: false, ...JSON.parse(localStorage.getItem(habitFeaturesKey()) || '{}') }; } catch { return { today: true, history: true, autoTracking: true, hasOnboarded: false }; }
}
function saveHabitFeatures(features) { try { localStorage.setItem(habitFeaturesKey(), JSON.stringify({ ...features, hasOnboarded: true })); } catch { /* this run only */ } }
function renderFeatureToggles(container, features, onChange) {
  container.replaceChildren(...HABIT_FEATURE_ROWS.map((row) => {
    const line = el('div', 'habit-feature');
    const icon = habitIcon(row.icon, 22);
    const text = el('div', 'habit-feature-text');
    text.append(el('p', 'habit-feature-title', row.title), el('p', 'fine', row.detail));
    const toggle = el('label', 'switch');
    const input = Object.assign(document.createElement('input'), { type: 'checkbox', checked: features[row.key] });
    input.setAttribute('aria-label', row.title);
    input.addEventListener('change', () => onChange({ ...features, [row.key]: input.checked }));
    toggle.append(input, el('span'));
    line.append(icon, text, toggle);
    return line;
  }));
}
let setupDraft = null;
let setupStart = 'Start with examples';
function renderHabitSetup() {
  setupDraft ||= habitFeatures();
  renderFeatureToggles($('habit-setup-features'), setupDraft, (next) => { setupDraft = next; renderHabitSetup(); });
  radioPills($('habit-setup-start'), ['Start with examples', 'Start empty'], setupStart, (choice) => { setupStart = choice; renderHabitSetup(); });
}
/** The Mac's four example habits, with this week's ticks so the tracker isn't empty on day one. */
function exampleHabits() {
  const monday = mondayOf(new Date());
  const days = (pattern) => pattern.map((on, i) => (on && addDays(monday, i) <= new Date() ? dayKey(addDays(monday, i)) : null)).filter(Boolean);
  const created = monday.getTime();
  return [
    { name: 'Deep Focus Block (90m)', symbol: 'brain', category: 'Focus', track: { type: 'focus', minutes: 90 }, done: days([1, 1, 1, 1, 1, 1, 1]) },
    { name: 'Phone in Another Room', symbol: 'phone-off', category: 'Discipline', done: days([1, 1, 1, 1, 1, 1, 1]) },
    { name: 'Review Lecture Flashcards', symbol: 'cards', category: 'Academics', schedule: { type: 'weekdays', days: [1, 2, 3, 4, 5] }, done: days([1, 1, 0, 1, 1, 0, 0]) },
    { name: 'Evening Review by 10 PM', symbol: 'moon', category: 'Recovery', done: days([0, 1, 1, 1, 1, 1, 0]) },
  ].map((h) => normalizeHabit({ id: crypto.randomUUID(), createdAt: created, ...h }));
}
$('habit-setup-continue').addEventListener('click', () => {
  saveHabitFeatures(setupDraft || habitFeatures());
  if (setupStart === 'Start with examples' && !loadHabits().length) saveHabits(exampleHabits());
  setupDraft = null;
  renderHabits();
  renderSettingsHabitFeatures();
});
function renderSettingsHabitFeatures() {
  if (!user) return;
  renderFeatureToggles($('habit-settings-features'), habitFeatures(), (next) => { saveHabitFeatures(next); renderSettingsHabitFeatures(); });
}

let expandedHabit = null;
/** Share of scheduled days done in the last `days` days; today counts only once it's done (Mac HabitMath). */
function completionRate(h, days = 30) {
  const end = startOfDay(new Date());
  const created = startOfDay(new Date(h.createdAt || Date.now()));
  let start = addDays(end, -(days - 1));
  if (created > start) start = created;
  let due = 0;
  let done = 0;
  for (let d = start; d <= end; d = addDays(d, 1)) {
    if (!isScheduled(h, d)) continue;
    const ok = isHabitDone(h, d);
    if (ok) done += 1;
    if (d < end || ok) due += 1;
  }
  if (h.schedule.type === 'times') return Math.min(1, done / (h.schedule.times * Math.max(1, days / 7)));
  return due ? done / due : 0;
}
/** The Mac app's HabitDetailPanel: streaks, the last 30 days, and 12 weeks as a contribution grid. */
function habitDetailPanel(h) {
  const unit = h.schedule.type === 'times' ? 'weeks' : 'days';
  const panel = el('div', 'habit-detail');
  const stat = (value, label) => { const box = el('div', 'hd-stat'); box.append(el('b', '', value), el('span', '', label)); return box; };
  panel.append(stat(String(habitStreak(h)), `Current streak (${unit})`), stat(String(bestStreak(h)), `Best streak (${unit})`), stat(`${Math.round(completionRate(h) * 100)}%`, 'Last 30 days'));
  const map = el('div', 'hd-map');
  map.setAttribute('role', 'img');
  map.setAttribute('aria-label', `Last 12 weeks: ${Math.round(completionRate(h, 84) * 100)} percent done`);
  const grid = el('div', 'hd-grid');
  const today = startOfDay(new Date());
  const thisMonday = mondayOf(today);
  for (let w = 11; w >= 0; w -= 1) {
    const column = el('div', 'hd-col');
    for (let i = 0; i < 7; i += 1) {
      const day = addDays(thisMonday, i - 7 * w);
      column.append(el('span', `hd-cell${day > today ? ' future' : isHabitDone(h, day) ? ' done' : isScheduled(h, day) ? '' : ' off'}`));
    }
    grid.append(column);
  }
  map.append(grid, el('span', 'fine', 'Last 12 weeks'));
  panel.append(map);
  return panel;
}
function scheduleText(h) {
  if (h.schedule.type === 'times') return `${h.schedule.times}× a week`;
  if (h.schedule.type === 'weekdays') return h.schedule.days.join() === '1,2,3,4,5' ? 'Weekdays' : h.schedule.days.map((d) => DAY_NAMES[d - 1]).join(' ');
  return 'Every day';
}
function goalText(h) {
  if (h.track.type === 'focus') return `Auto: ${h.track.minutes}-min focus session`;
  return h.goalAmount > 0 ? `Goal: ${h.goalAmount}${h.goalUnit ? ` ${h.goalUnit}` : ''}` : 'Goal: check off';
}
function toggleHabit(id, key) {
  const all = loadHabits().map(normalizeHabit);
  const target = all.find((h) => h.id === id);
  if (!target) return;
  if (target.goalAmount > 0) {
    // A day cell for an amount habit fills the goal or clears it.
    target.progress[key] = (target.progress[key] || 0) >= target.goalAmount ? 0 : target.goalAmount;
  } else {
    target.done = target.done.includes(key) ? target.done.filter((d) => d !== key) : [...target.done, key].slice(-400);
  }
  saveHabits(all);
  renderHabits();
}
function stepHabitAmount(id, delta) {
  const all = loadHabits().map(normalizeHabit);
  const target = all.find((h) => h.id === id);
  if (!target) return;
  const key = dayKey(new Date());
  target.progress[key] = Math.max(0, Math.min(99_999, (target.progress[key] || 0) + delta));
  saveHabits(all);
  renderHabits();
}
/** Habits set to "done after a focus session" tick themselves (the Mac's recordFocusSession). */
function recordFocusForHabits(minutes) {
  if (!user || minutes <= 0 || !habitFeatures().autoTracking) return;
  const all = loadHabits().map(normalizeHabit);
  const key = dayKey(new Date());
  let changed = false;
  for (const h of all) {
    if (h.track.type === 'focus' && minutes >= h.track.minutes && !h.done.includes(key)) { h.done = [...h.done, key].slice(-400); changed = true; }
  }
  if (changed) saveHabits(all);
}

let weekOffset = 0;
const DAY_LETTERS = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
function weekOf(offset) {
  const today = new Date();
  const monday = new Date(today);
  monday.setDate(today.getDate() - ((today.getDay() + 6) % 7) + offset * 7);
  return [...Array(7)].map((_, i) => { const d = new Date(monday); d.setDate(monday.getDate() + i); return d; });
}
function weekRate(list, days) {
  const past = days.filter((d) => d <= new Date());
  let due = 0;
  let done = 0;
  for (const h of list) {
    if (h.schedule.type === 'times') { due += h.schedule.times; done += Math.min(h.schedule.times, past.filter((d) => isHabitDone(h, d)).length); continue; }
    for (const d of past) if (isScheduled(h, d)) { due += 1; if (isHabitDone(h, d)) done += 1; }
  }
  return due ? done / due : 0;
}

function renderHabits() {
  const list = loadHabits().map(normalizeHabit);
  const features = habitFeatures();
  // First visit (and nothing tracked yet): choose features first, as on the Mac.
  const setup = !features.hasOnboarded && !list.length;
  $('habit-setup').hidden = !setup;
  $('habit-new').hidden = setup;
  if (setup) {
    renderHabitSetup();
    for (const id of ['habits-empty', 'today-card', 'week-card']) $(id).hidden = true;
    return;
  }
  if (!features.history) { weekOffset = 0; expandedHabit = null; }
  const todayKey = dayKey(new Date());
  // Summary line, as on the Mac.
  if (!list.length) {
    $('habit-summary').textContent = 'Build routines that stick. Everything stays on this PC.';
  } else {
    const now = Math.round(weekRate(list, weekOf(0)) * 100);
    const last = weekRate(list, weekOf(-1));
    if (last <= 0) {
      $('habit-summary').textContent = `This week ${now}% of habits done`;
    } else {
      const change = Math.round((weekRate(list, weekOf(0)) - last) * 100);
      const trend = change === 0 ? 'same as last week' : change > 0 ? `up ${change}% from last week` : `down ${-change}% from last week`;
      $('habit-summary').textContent = `This week ${now}% · ${trend}`;
    }
  }
  $('habits-empty').hidden = list.length > 0;
  $('today-card').hidden = list.length === 0 || !features.today;
  $('week-card').hidden = list.length === 0;
  if (!list.length) return;

  // TODAY: ring and tap-to-check pills, for habits scheduled today.
  const todayDate = new Date();
  const dueToday = list.filter((h) => isScheduled(h, todayDate));
  const doneToday = dueToday.filter((h) => isHabitDone(h, todayDate)).length;
  $('today-date').textContent = new Date().toLocaleDateString(undefined, { weekday: 'long', month: 'long', day: 'numeric' });
  $('today-count').textContent = `${doneToday}/${dueToday.length}`;
  const circumference = 2 * Math.PI * 47;
  $('today-ring').style.strokeDasharray = `${circumference}`;
  $('today-ring').style.strokeDashoffset = `${circumference * (1 - (dueToday.length ? doneToday / dueToday.length : 0))}`;
  $('today-pills').replaceChildren(...dueToday.map((habit) => {
    const done = isHabitDone(habit, todayDate);
    const amount = habit.goalAmount > 0 && !(habit.track.type === 'focus' && features.autoTracking);
    const pill = el(amount ? 'div' : 'button', `check-pill${done ? ' done' : ''}`);
    const dot = el('span', 'check-dot', done ? '✓' : '');
    if (!done) dot.append(habitIcon(habit.symbol, 14));
    const text = el('span', 'check-text');
    const sub = habit.track.type === 'focus' && features.autoTracking ? (done ? 'Done' : `After a ${habit.track.minutes}-min session`)
      : amount ? `${habit.progress[todayKey] || 0}/${habit.goalAmount}${habit.goalUnit ? ` ${habit.goalUnit}` : ''}` : done ? 'Done' : 'Tap when done';
    text.append(el('span', 'check-name', habit.name), el('span', 'check-sub', sub));
    pill.append(dot, text);
    if (amount) {
      const minus = el('button', 'icon-btn amount-btn', '−');
      const plus = el('button', 'icon-btn amount-btn', '+');
      for (const [button, delta, label] of [[minus, -1, 'Less'], [plus, 1, 'More']]) {
        button.type = 'button';
        button.setAttribute('aria-label', `${label} ${habit.name}`);
        button.addEventListener('click', () => stepHabitAmount(habit.id, delta));
      }
      pill.append(minus, plus);
    } else {
      pill.type = 'button';
      pill.setAttribute('aria-pressed', String(done));
      pill.addEventListener('click', () => toggleHabit(habit.id, todayKey));
    }
    return pill;
  }));

  // THIS WEEK: header days, then a row per habit with 24-pt day cells.
  const days = weekOf(weekOffset);
  const format = (d) => d.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
  $('week-title').textContent = weekOffset === 0 ? 'THIS WEEK' : `${format(days[0])} – ${format(days[6])}`.toUpperCase();
  $('week-next').disabled = weekOffset >= 0;
  $('week-prev').hidden = !features.history;
  $('week-next').hidden = !features.history;
  $('week-now').hidden = weekOffset === 0;
  $('week-days').replaceChildren(...days.map((d, i) => {
    const cell = el('span', `week-day${dayKey(d) === todayKey ? ' today' : ''}`);
    cell.append(el('b', '', DAY_LETTERS[i]), el('span', '', String(d.getDate())));
    return cell;
  }));
  $('habit-list').replaceChildren(...list.map((habit) => {
    const row = el('div', 'habit-row');
    const info = el('button', 'habit-info');
    info.type = 'button';
    info.setAttribute('aria-expanded', String(expandedHabit === habit.id));
    info.title = 'Show streak history';
    const streak = habitStreak(habit);
    const unit = habit.schedule.type === 'times' ? 'week' : 'day';
    const name = el('span', 'habit-name');
    name.append(habitIcon(habit.symbol, 14), el('span', '', habit.name));
    info.append(name, el('span', 'habit-meta', `${streak > 0 ? `${streak}-${unit} streak` : 'No streak yet'} · best ${bestStreak(habit)} · ${goalText(habit)} · ${scheduleText(habit)}`));
    info.addEventListener('click', () => { if (!features.history) return; expandedHabit = expandedHabit === habit.id ? null : habit.id; renderHabits(); });
    const edit = el('button', 'icon-btn habit-edit');
    edit.type = 'button';
    edit.title = 'Edit habit and goal';
    edit.setAttribute('aria-label', `Edit ${habit.name}`);
    edit.append(habitIcon('pencil', 13));
    edit.addEventListener('click', () => openHabitEditor(habit));
    const cells = el('div', 'day-cells');
    for (const day of days) {
      const key = dayKey(day);
      const future = key > todayKey;
      const done = isHabitDone(habit, day);
      const off = !isScheduled(habit, day);
      const cell = el('button', `day-cell${done ? ' done' : ''}${key === todayKey && !done ? ' today' : ''}${future ? ' future' : ''}${off ? ' off' : ''}`, done ? '✓' : '');
      cell.type = 'button';
      cell.disabled = future;
      cell.setAttribute('aria-label', `${habit.name}, ${day.toLocaleDateString()}`);
      cell.setAttribute('aria-pressed', String(done));
      cell.addEventListener('click', () => toggleHabit(habit.id, key));
      cells.append(cell);
    }
    row.append(info, edit, cells);
    if (expandedHabit !== habit.id) return row;
    const wrap = el('div', 'habit-wrap');
    wrap.append(row, habitDetailPanel(habit));
    return wrap;
    return row;
  }));
}

$('week-prev').addEventListener('click', () => { weekOffset -= 1; renderHabits(); });
$('week-next').addEventListener('click', () => { if (weekOffset < 0) { weekOffset += 1; renderHabits(); } });
$('week-now').addEventListener('click', () => { weekOffset = 0; renderHabits(); });
$('habit-new').addEventListener('click', () => openHabitEditor(null));

// Habit editor (the Mac app's HabitEditorSheet). Social-media auto-tracking and reminders aren't on Windows yet.
let habitDraft = null;
function radioPills(container, items, current, onPick) {
  container.replaceChildren(...items.map((item) => {
    const pill = el('button', 'pill', item);
    pill.type = 'button';
    pill.setAttribute('role', 'radio');
    pill.setAttribute('aria-checked', String(item === current));
    pill.addEventListener('click', () => onPick(item));
    return pill;
  }));
}
function openHabitEditor(habit) {
  const h = habit ? normalizeHabit(habit) : normalizeHabit({ id: null, name: '' });
  habitDraft = {
    id: h.id, name: h.name, symbol: h.symbol, category: h.category,
    scheduleChoice: h.schedule.type === 'times' ? 'Times a week' : h.schedule.type === 'weekdays' ? (h.schedule.days.join() === '1,2,3,4,5' ? 'Weekdays' : 'Pick days') : 'Every day',
    days: new Set(h.schedule.type === 'weekdays' ? h.schedule.days : [1, 2, 3, 4, 5]),
    times: h.schedule.type === 'times' ? h.schedule.times : 3,
    goalChoice: h.goalAmount > 0 ? 'Reach an amount' : 'Check off', amount: h.goalAmount || 10, unit: h.goalUnit || '',
    trackChoice: h.track.type === 'focus' ? 'Focus session' : 'Manual', focusMinutes: h.track.minutes || 60,
  };
  $('habit-editor-title').textContent = habit ? 'Edit Habit' : 'New Habit';
  $('habit-add').textContent = habit ? 'Save' : 'Add Habit';
  $('habit-delete').hidden = !habit;
  $('habit-name').value = habitDraft.name;
  $('habit-unit').value = habitDraft.unit;
  renderHabitEditor();
  $('habit-editor').hidden = false;
  $('habit-name').focus();
}
function renderHabitEditor() {
  const d = habitDraft;
  $('habit-icons').replaceChildren(...Object.keys(HABIT_ICONS).map((name) => {
    const b = el('button', `he-icon${d.symbol === name ? ' on' : ''}`);
    b.type = 'button';
    b.setAttribute('role', 'radio');
    b.setAttribute('aria-checked', String(d.symbol === name));
    b.setAttribute('aria-label', name);
    b.append(habitIcon(name, 16));
    b.addEventListener('click', () => { d.symbol = name; renderHabitEditor(); });
    return b;
  }));
  radioPills($('habit-categories'), HABIT_CATEGORIES, d.category, (c) => { d.category = c; renderHabitEditor(); });
  radioPills($('habit-schedules'), SCHEDULE_OPTIONS, d.scheduleChoice, (c) => { d.scheduleChoice = c; renderHabitEditor(); });
  $('habit-days').hidden = d.scheduleChoice !== 'Pick days';
  $('habit-days').replaceChildren(...DAY_NAMES.map((name, i) => {
    const on = d.days.has(i + 1);
    const b = el('button', `he-day${on ? ' on' : ''}`, name);
    b.type = 'button';
    b.setAttribute('aria-pressed', String(on));
    b.addEventListener('click', () => { if (on) d.days.delete(i + 1); else d.days.add(i + 1); renderHabitEditor(); });
    return b;
  }));
  $('habit-times-row').hidden = d.scheduleChoice !== 'Times a week';
  $('habit-times-label').textContent = `${d.times} times a week`;
  // An auto-tracked habit is done or not, so it has no amount (as on the Mac).
  $('habit-goal-section').hidden = habitFeatures().autoTracking && d.trackChoice !== 'Manual';
  radioPills($('habit-goals'), ['Check off', 'Reach an amount'], d.goalChoice, (c) => { d.goalChoice = c; renderHabitEditor(); });
  $('habit-amount-row').hidden = d.goalChoice !== 'Reach an amount';
  $('habit-amount-label').textContent = `Goal: ${d.amount}`;
  $('habit-trackings').parentElement.hidden = !habitFeatures().autoTracking;
  radioPills($('habit-trackings'), ['Manual', 'Focus session'], d.trackChoice, (c) => { d.trackChoice = c; renderHabitEditor(); });
  $('habit-focus-row').hidden = d.trackChoice !== 'Focus session';
  $('habit-focus-label').textContent = `Done after a ${d.focusMinutes}-min focus session`;
  $('habit-add').disabled = !$('habit-name').value.trim() || (d.scheduleChoice === 'Pick days' && d.days.size === 0);
}
for (const button of document.querySelectorAll('.he-step')) {
  button.addEventListener('click', () => {
    const [what, by] = button.dataset.step.split(':');
    const d = habitDraft;
    if (what === 'times') d.times = Math.min(6, Math.max(1, d.times + Number(by)));
    if (what === 'amount') d.amount = Math.min(1000, Math.max(1, d.amount + Number(by)));
    if (what === 'focus') d.focusMinutes = Math.min(180, Math.max(15, d.focusMinutes + Number(by)));
    renderHabitEditor();
  });
}
$('habit-name').addEventListener('input', () => renderHabitEditor());
$('habit-unit').addEventListener('input', () => { habitDraft.unit = $('habit-unit').value.slice(0, 20); });
$('habit-cancel').addEventListener('click', () => { $('habit-editor').hidden = true; });
$('habit-delete').addEventListener('click', () => {
  const name = $('habit-name').value.trim() || 'this habit';
  if (!window.confirm(`Delete “${name}”? This removes its streaks and history from this PC.`)) return;
  saveHabits(loadHabits().filter((h) => h.id !== habitDraft.id));
  $('habit-editor').hidden = true;
  renderHabits();
});
$('habit-form').addEventListener('submit', (event) => {
  event.preventDefault();
  const d = habitDraft;
  const name = $('habit-name').value.trim().slice(0, 60);
  if (!name || (d.scheduleChoice === 'Pick days' && d.days.size === 0)) return;
  const list = loadHabits().map(normalizeHabit);
  const existing = list.find((h) => h.id === d.id);
  if (!existing && list.length >= 30) return;
  const fields = {
    name, symbol: d.symbol, category: d.category,
    schedule: d.scheduleChoice === 'Times a week' ? { type: 'times', times: d.times }
      : d.scheduleChoice === 'Weekdays' ? { type: 'weekdays', days: [1, 2, 3, 4, 5] }
        : d.scheduleChoice === 'Pick days' ? { type: 'weekdays', days: [...d.days].sort() } : { type: 'daily' },
    track: d.trackChoice === 'Focus session' ? { type: 'focus', minutes: d.focusMinutes } : { type: 'manual' },
    goalAmount: !$('habit-goal-section').hidden && d.goalChoice === 'Reach an amount' ? d.amount : null,
    goalUnit: !$('habit-goal-section').hidden && d.goalChoice === 'Reach an amount' ? (d.unit || '').trim().slice(0, 20) : '',
  };
  if (existing) Object.assign(existing, fields);
  else list.push(normalizeHabit({ id: crypto.randomUUID(), createdAt: Date.now(), ...fields }));
  saveHabits(list);
  $('habit-editor').hidden = true;
  renderHabits();
});

// ---------- Analytics (from this PC's daily totals) ----------
function renderAnalytics() {
  let all = {};
  try { all = JSON.parse(localStorage.getItem(statsKey()) || '{}'); } catch { /* none yet */ }
  const days = [...Array(7)].map((_, i) => { const d = new Date(); d.setDate(d.getDate() - (6 - i)); return d; });
  const values = days.map((d) => all[dayKey(d)] || { minutes: 0, sessions: 0, blocked: 0 });
  const max = Math.max(30, ...values.map((v) => v.minutes));
  $('week-bars').replaceChildren(...days.map((day, i) => {
    const column = document.createElement('div');
    column.className = 'bar-col';
    const value = document.createElement('span');
    value.className = 'bar-value';
    value.textContent = values[i].minutes ? `${values[i].minutes}` : '';
    const bar = document.createElement('div');
    bar.className = 'bar';
    bar.style.height = `${Math.round((values[i].minutes / max) * 100)}%`;
    const label = document.createElement('span');
    label.className = 'bar-label';
    label.textContent = day.toLocaleDateString(undefined, { weekday: 'short' });
    column.append(value, bar, label);
    return column;
  }));
  $('week-minutes').textContent = values.reduce((a, v) => a + v.minutes, 0);
  $('week-sessions').textContent = values.reduce((a, v) => a + v.sessions, 0);
  $('week-blocked').textContent = values.reduce((a, v) => a + v.blocked, 0);
  let streak = 0;
  const cursor = new Date();
  if (!(all[dayKey(cursor)]?.minutes > 0)) cursor.setDate(cursor.getDate() - 1);
  while (all[dayKey(cursor)]?.minutes > 0) { streak += 1; cursor.setDate(cursor.getDate() - 1); }
  $('week-streak').textContent = streak;
}

// ---------- Week digest (the Mac's WeekDigestPanel; Canvas only, written on request, kept in memory) ----------
function renderWeekDigest() {
  $('digest-disclosure').textContent = `Sends the titles, courses and due times of this week's Canvas assignments to ${aiProvider || 'your AI service'} to plan your week.`;
  $('digest-write').textContent = weekDigest ? 'Write Again' : 'Plan My Week';
  $('digest-body').hidden = !weekDigest;
  if (!weekDigest) return;
  const footer = el('p', 'fine', `Written by ${aiProvider || 'AI'} at ${weekDigest.written.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}. Check anything important against Canvas.`);
  $('digest-body').replaceChildren(...markdownNodes(weekDigest.text), footer);
}
/** The digest's small Markdown (### headings, - bullets, **bold**) as DOM nodes; text is never parsed as HTML. */
function markdownNodes(text) {
  const nodes = [];
  let list = null;
  const inline = (parent, line) => {
    line.split(/(\*\*[^*]+\*\*)/).forEach((part) => {
      if (/^\*\*[^*]+\*\*$/.test(part)) parent.append(el('strong', '', part.slice(2, -2)));
      else if (part) parent.append(document.createTextNode(part));
    });
    return parent;
  };
  for (const raw of text.split('\n')) {
    const line = raw.trim();
    if (!line) { list = null; continue; }
    if (/^#{1,6}\s/.test(line)) { list = null; nodes.push(inline(el('h3'), line.replace(/^#{1,6}\s+/, ''))); continue; }
    if (/^[-*•]\s/.test(line)) {
      if (!list) { list = el('ul'); nodes.push(list); }
      list.append(inline(el('li'), line.replace(/^[-*•]\s+/, '')));
      continue;
    }
    list = null;
    nodes.push(inline(el('p'), line));
  }
  return nodes;
}
$('digest-write').addEventListener('click', async () => {
  const button = $('digest-write');
  const problem = !aiEnabled() ? 'AI features are turned off in Settings.'
    : !aiAdult() ? 'AI features are for people 18 and older.'
      : !aiProvider ? 'Add a Claude, ChatGPT or Gemini API key in Settings to plan your week.' : null;
  const fail = (message, offerSettings) => {
    $('digest-error-text').textContent = message;
    $('digest-settings').hidden = !offerSettings;
    $('digest-error').hidden = false;
  };
  $('digest-error').hidden = true;
  if (problem) { fail(problem, true); return; }
  const start = new Date(); start.setHours(0, 0, 0, 0);
  const end = new Date(start); end.setDate(end.getDate() + 7);
  const lines = pendingAssignments()
    .filter((a) => a.due && a.due >= start && a.due < end)
    .map((a) => `- [Canvas] ${a.due.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' })}, due ${a.due.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })}: ${a.title}${a.course ? ` (${a.course})` : ''}`);
  const today = new Date().toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric', year: 'numeric' });
  button.disabled = true;
  button.classList.add('busy');
  try {
    weekDigest = { text: String(await invoke('ai_week_digest', { account: user.id, today, lines })), written: new Date() };
    renderWeekDigest();
  } catch (error) {
    const message = typeof error === 'string' ? error : "Couldn't reach the AI service.";
    fail(message, /Settings/.test(message));
  } finally {
    button.disabled = false;
    button.classList.remove('busy');
  }
});
$('digest-settings').addEventListener('click', () => showPage('settings'));

// ---------- Notes (per account, on this PC only) ----------
const notesKey = () => `locken.notes.${user.id}`;
let selectedNote = null;
function loadNotes() {
  try { return JSON.parse(localStorage.getItem(notesKey()) || '[]'); } catch { return []; }
}
function saveNotes(list) { localStorage.setItem(notesKey(), JSON.stringify(list)); }

/** "Edited just now / 5 minutes ago / yesterday / Oct 3" (the Mac's relative date). */
function editedText(ms) {
  const seconds = Math.round((Date.now() - ms) / 1000);
  const rtf = new Intl.RelativeTimeFormat(undefined, { numeric: 'auto' });
  if (seconds < 45) return 'Edited just now';
  if (seconds < 3600) return `Edited ${rtf.format(-Math.round(seconds / 60), 'minute')}`;
  if (seconds < 86400) return `Edited ${rtf.format(-Math.round(seconds / 3600), 'hour')}`;
  if (seconds < 7 * 86400) return `Edited ${rtf.format(-Math.round(seconds / 86400), 'day')}`;
  return `Edited ${new Date(ms).toLocaleDateString(undefined, { month: 'short', day: 'numeric' })}`;
}
function renderNotes() {
  const list = loadNotes().sort((a, b) => b.updatedAt - a.updatedAt);
  $('notes-count').textContent = list.length ? String(list.length) : '';
  const current = list.find((n) => n.id === selectedNote);
  if (!current) selectedNote = null;
  $('note-editor').hidden = !current;
  $('notes-empty').hidden = list.length > 0;
  // The open note sits in the editor at the top; the others are listed below it, newest first.
  $('notes-list').replaceChildren(...list.filter((n) => n.id !== selectedNote).map((note) => {
    const button = el('button', 'note-item');
    button.type = 'button';
    button.append(el('span', 'note-item-title', note.title || 'Untitled'));
    if (note.body) button.append(el('span', 'note-item-body', note.body.slice(0, 300)));
    button.append(el('span', 'fine', editedText(note.updatedAt)));
    button.addEventListener('click', () => openNote(note.id));
    return button;
  }));
}

function openNote(id) {
  flushNoteSave();
  selectedNote = id;
  const note = loadNotes().find((n) => n.id === id);
  $('note-title').value = note?.title || '';
  $('note-body').value = note?.body || '';
  $('note-saved').textContent = '';
  renderNotes();
  if (note && !note.title && !note.body) $('note-title').focus(); else $('note-body').focus();
}

let noteSaveTimer = null;
function writeCurrentNote() {
  const list = loadNotes();
  const note = list.find((n) => n.id === selectedNote);
  if (!note) return;
  note.title = $('note-title').value.slice(0, 120);
  note.body = $('note-body').value.slice(0, 20000);
  note.updatedAt = Date.now();
  saveNotes(list);
  $('note-saved').textContent = 'Saved on this PC';
}
/** Saves a pending edit now (before switching notes or closing), so nothing typed is lost. */
function flushNoteSave() {
  if (noteSaveTimer === null) return;
  clearTimeout(noteSaveTimer);
  noteSaveTimer = null;
  writeCurrentNote();
}
function saveCurrentNote() {
  clearTimeout(noteSaveTimer);
  $('note-saved').textContent = 'Saving…';
  noteSaveTimer = setTimeout(() => { noteSaveTimer = null; writeCurrentNote(); }, 400);
}
$('note-title').addEventListener('input', saveCurrentNote);
$('note-body').addEventListener('input', saveCurrentNote);
$('note-new').addEventListener('click', () => {
  flushNoteSave();
  const list = loadNotes();
  if (list.length >= 500) return;
  const note = { id: crypto.randomUUID(), title: '', body: '', updatedAt: Date.now() };
  list.push(note);
  saveNotes(list);
  openNote(note.id);
});
/** Done closes the editor; a note left completely empty is thrown away (as on the Mac). */
$('note-done').addEventListener('click', () => {
  flushNoteSave();
  if (!$('note-title').value.trim() && !$('note-body').value.trim()) saveNotes(loadNotes().filter((n) => n.id !== selectedNote));
  selectedNote = null;
  renderNotes();
});
$('note-delete').addEventListener('click', () => {
  clearTimeout(noteSaveTimer);
  noteSaveTimer = null;
  saveNotes(loadNotes().filter((n) => n.id !== selectedNote));
  selectedNote = null;
  renderNotes();
});

// ---------- Page colours (the Mac app's per-tab palette) ----------
const PAGE_THEME = {
  dashboard: { accent: '#BE123C', light: '#E06683', top: '#17080D' },
  focus: { accent: '#8C33E6', light: '#CCA3F5', top: '#0F0A17' },
  assistant: { accent: '#FB7158', light: '#FCAA9B', top: '#170C0A' },
  habits: { accent: '#F59E0B', light: '#F9C46A', top: '#0D0F17' },
  analytics: { accent: '#38BDF8', light: '#88D7FA', top: '#080F17' },
  notes: { accent: '#8B5CF6', light: '#B99DF9', top: '#120D1A' },
  settings: { accent: '#94A3B8', light: '#C2CBD6', top: '#0D0D12' },
  admin: { accent: '#8C33E6', light: '#CCA3F5', top: '#0F0A17' },
};
let fiberColor = '140, 51, 230';
function applyTheme(page) {
  const theme = PAGE_THEME[page] || PAGE_THEME.focus;
  const root = document.documentElement.style;
  root.setProperty('--accent', theme.accent);
  root.setProperty('--accent-light', theme.light);
  root.setProperty('--bg-top', theme.top);
  const hex = theme.accent.slice(1);
  fiberColor = [0, 2, 4].map((i) => parseInt(hex.slice(i, i + 2), 16)).join(', ');
  const orb = $('orb');
  try { orb?.contentWindow?.updateProps?.({ colors: JSON.stringify([theme.accent, theme.accent, theme.light]) }); } catch { /* not loaded yet */ }
  currentPage = page;
  updateProfileCard();
}
$('orb').addEventListener('load', () => applyTheme('dashboard'));

// ---------- Sidebar profile card (the Mac app's SidebarProfileCard) ----------
// The same React Bits ProfileCard as the Mac: your name, your Windows account name, where your data lives, and
// what's playing from the system media controls (Spotify, a browser, Media Player). Play/pause works from the card.
let currentPage = 'dashboard';
let profileReady = false;
let lastProfileProps = '';
let nowPlaying = null;
let windowsUserName = '';
invoke('user_name').then((name) => { windowsUserName = String(name || ''); updateProfileCard(); }).catch(() => {});
// The Mac's glow colours per page (SquircleTokens.glowGradientColors): the card's faint tint uses the first and last.
const CARD_GLOW = {
  dashboard: ['#BE123C', '#E02673', '#F59E0B'],
  focus: ['#8C33E6', '#E02673', '#3352C7'],
  assistant: ['#FB7158', '#E02673', '#F59E0B'],
  habits: ['#F59E0B', '#D97706', '#BE123C'],
  analytics: ['#F59E0B', '#D97706', '#BE123C'],
  notes: ['#8B5CF6', '#8C33E6', '#E02673'],
  settings: ['#94A3B8', '#3352C7', '#8B5CF6'],
  admin: ['#8C33E6', '#3352C7', '#8B5CF6'],
};
const avatarCache = new Map();
/** The Mac's monogram avatar: your initial on an amber-to-obsidian circle. */
function monogram(letter) {
  if (avatarCache.has(letter)) return avatarCache.get(letter);
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = 512;
  const c = canvas.getContext('2d');
  const fill = c.createLinearGradient(0, 0, 512, 512);
  fill.addColorStop(0, '#D97706');
  fill.addColorStop(1, '#171822');
  c.fillStyle = fill;
  c.beginPath(); c.arc(256, 256, 256, 0, Math.PI * 2); c.fill();
  c.fillStyle = '#fff';
  c.font = '700 220px Montserrat, sans-serif';
  c.textAlign = 'center';
  c.textBaseline = 'middle';
  c.fillText(letter, 256, 268);
  const url = canvas.toDataURL('image/png');
  avatarCache.set(letter, url);
  return url;
}
const GEAR_ICON = 'data:image/svg+xml,' + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#fff" fill-rule="evenodd" d="M10.3 2h3.4l.5 2.6a7.6 7.6 0 0 1 1.9 1.1l2.5-.9 1.7 3-2 1.7a7.7 7.7 0 0 1 0 2.2l2 1.7-1.7 3-2.5-.9a7.6 7.6 0 0 1-1.9 1.1l-.5 2.6h-3.4l-.5-2.6a7.6 7.6 0 0 1-1.9-1.1l-2.5.9-1.7-3 2-1.7a7.7 7.7 0 0 1 0-2.2l-2-1.7 1.7-3 2.5.9a7.6 7.6 0 0 1 1.9-1.1zM12 8.6a3.4 3.4 0 1 0 0 6.8 3.4 3.4 0 0 0 0-6.8z"/></svg>');
function updateProfileCard() {
  const frame = $('profile-card');
  if (!frame || !profileReady || !user) return;
  const name = displayName();
  const glow = CARD_GLOW[currentPage] || CARD_GLOW.focus;
  const accent = (PAGE_THEME[currentPage] || PAGE_THEME.focus).accent;
  const props = {
    name: name || 'Locken',
    handle: windowsUserName || (user.email || '').split('@')[0],
    status: 'Saved on this PC',
    avatarUrl: monogram((name || 'L')[0]),
    settingsIcon: GEAR_ICON,
    innerGradient: `linear-gradient(145deg,${glow[0]}33 0%,${glow[2]}1a 100%)`,
    behindGlowColor: `${accent}40`,
    ...(nowPlaying
      ? { musicState: 'track', musicTitle: nowPlaying.title, musicCover: nowPlaying.cover || '', musicPlaying: nowPlaying.playing ? '1' : '0' }
      : { musicState: 'idle', musicIdleText: 'Nothing playing' }),
  };
  const json = JSON.stringify(props);
  if (json === lastProfileProps) return;
  lastProfileProps = json;
  try { frame.contentWindow.updateProps(props); } catch { lastProfileProps = ''; }
}
// One check at a time: a frozen player can leave Windows' media call waiting, and checks must not pile up behind it.
let checkingNowPlaying = false;
async function refreshNowPlaying() {
  if (checkingNowPlaying || !user || document.visibilityState !== 'visible') return;
  checkingNowPlaying = true;
  try {
    const track = await invoke('now_playing').catch(() => null);
    // Only a data: image from Windows itself is shown, never a remote address.
    nowPlaying = track && typeof track.title === 'string'
      ? { title: track.title.slice(0, 200), playing: Boolean(track.playing), cover: /^data:image\/[a-z+.-]+;base64,/i.test(track.cover || '') ? track.cover : '' }
      : null;
    updateProfileCard();
  } finally {
    checkingNowPlaying = false;
  }
}
setInterval(refreshNowPlaying, 2000);
document.addEventListener('visibilitychange', refreshNowPlaying);
window.addEventListener('message', (event) => {
  const frame = $('profile-card');
  if (event.origin !== window.location.origin || !frame || event.source !== frame.contentWindow) return;
  const message = event.data?.profileCard;
  if (message === 'ready') { profileReady = true; lastProfileProps = ''; updateProfileCard(); refreshNowPlaying(); }
  else if (message === 'openSettings') showPage('settings');
  else if (message === 'playPause') invoke('media_play_pause').catch(() => {}).finally(() => setTimeout(refreshNowPlaying, 300));
});
// The Focus page's dither artwork in the Mac app's paper colour (Locken violet lightened).
document.querySelector('.dither').addEventListener('load', (event) => {
  try { event.target.contentWindow.updateProps?.({ paperColor: '#CCA3F5' }); } catch { /* not ready */ }
});

// ---------- Dashboard: the four glass boxes and their stat cards (same numbers as the Mac app) ----------
function dailyStats() {
  try { return JSON.parse(localStorage.getItem(statsKey()) || '{}'); } catch { return {}; }
}
function weekDays() {
  // Monday first, like the Mac app's chart.
  const today = new Date();
  const monday = new Date(today);
  monday.setDate(today.getDate() - ((today.getDay() + 6) % 7));
  return [...Array(7)].map((_, i) => { const d = new Date(monday); d.setDate(monday.getDate() + i); return d; });
}
function habitsDueToday() {
  const list = loadHabits().map(normalizeHabit);
  const today = new Date();
  const due = list.filter((h) => isScheduled(h, today));
  return { total: due.length, done: due.filter((h) => isHabitDone(h, today)).length, list };
}
function momentumScore() {
  const parts = [];
  const minutes = dailyStats()[dayKey(new Date())]?.minutes || 0;
  if (minutes > 0) parts.push(Math.min(1, minutes / 60));
  const habits = habitsDueToday();
  if (habits.total > 0) parts.push(habits.done / habits.total);
  if (!parts.length) return null;
  return Math.round((parts.reduce((a, b) => a + b, 0) / parts.length) * 100);
}
function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}
function bigNumber(value, caption) {
  const row = el('div', 'metric-big');
  row.append(el('span', 'metric-num', value), el('span', 'metric-cap', caption));
  return row;
}
function progressBar(fraction) {
  const track = el('div', 'metric-progress');
  const fill = el('div');
  fill.style.width = `${Math.round(Math.min(1, Math.max(0, fraction)) * 100)}%`;
  track.append(fill);
  return track;
}

function renderMetric(label) {
  const body = $('metric-body');
  const stats = dailyStats();
  body.replaceChildren();
  if (label === 'Focus') {
    const days = weekDays();
    const minutes = days.map((d) => stats[dayKey(d)]?.minutes || 0);
    const total = minutes.reduce((a, b) => a + b, 0);
    body.append(bigNumber(`${total}`, 'minutes focused this week'));
    const chart = el('div', 'metric-chart');
    chart.append(el('p', 'mini-label', 'FOCUS HOURS THIS WEEK'));
    const bars = el('div', 'metric-bars');
    const todayIndex = (new Date().getDay() + 6) % 7;
    days.forEach((day, i) => {
      const col = el('div', 'metric-col');
      const bar = el('div', 'metric-bar');
      const hours = minutes[i] / 60;
      bar.style.height = `${Math.max(4, Math.min(1, hours / 4) * 100)}%`;
      bar.classList.toggle('today', i === todayIndex);
      bar.classList.toggle('some', hours > 0);
      col.append(bar, el('span', 'metric-day', day.toLocaleDateString(undefined, { weekday: 'short' })));
      bars.append(col);
    });
    chart.append(bars);
    body.append(chart);
  } else if (label === 'Habits') {
    const { list } = habitsDueToday();
    const percentage = Math.round(weekRate(list, weekDays()) * 100);
    const topStreak = list.reduce((max, h) => Math.max(max, habitStreak(h)), 0);
    body.append(bigNumber(`${percentage}%`, 'this week'), progressBar(percentage / 100),
      el('p', 'metric-note', `${list.length} habits tracked • top streak ${topStreak} days`));
  } else if (label === 'Sessions') {
    const today = stats[dayKey(new Date())]?.sessions || 0;
    body.append(bigNumber(`${today}`, 'sessions started today'), progressBar(Math.min(today, 5) / 5),
      el('p', 'metric-note', 'Goal: 5 focus sessions today'));
  } else {
    const score = momentumScore();
    const labelText = score === null ? 'No activity yet' : score >= 80 ? `${score}% Strong` : score >= 50 ? `${score}% Building` : score > 0 ? `${score}% Getting started` : '0% Not started';
    body.append(el('p', 'metric-state', labelText), progressBar((score || 0) / 100),
      el('p', 'metric-note', score === null
        ? 'Start a focus session or check off a habit to see today’s momentum.'
        : 'Today’s focus time (out of an hour) and habits checked off.'));
  }
}

for (const box of document.querySelectorAll('.anno')) {
  box.addEventListener('click', () => {
    $('metric-title').textContent = box.dataset.metric;
    renderMetric(box.dataset.metric);
    $('orbital').classList.add('expanded');
    $('metric-card').hidden = false;
    $('metric-close').focus();
  });
}
$('metric-close').addEventListener('click', () => {
  $('orbital').classList.remove('expanded');
  $('metric-card').hidden = true;
});

// ---------- Settings: blocked apps (per account, on this PC) ----------
const blockKey = () => `locken.blocker.${user.id}`;
function loadBlockRules() {
  try { return { extra: [], allowed: [], ...JSON.parse(localStorage.getItem(blockKey()) || '{}') }; } catch { return { extra: [], allowed: [] }; }
}
function saveBlockRules(rules) { localStorage.setItem(blockKey(), JSON.stringify(rules)); }
let builtInBlocked = [];
async function renderBlockedApps() {
  if (!builtInBlocked.length) builtInBlocked = await invoke('default_blocked_apps').catch(() => []);
  const rules = loadBlockRules();
  const chip = (label, onClick, removable) => {
    const button = el('button', `chip${removable ? ' extra' : ''}`, label);
    button.type = 'button';
    button.title = removable ? 'Stop blocking' : 'Keep open';
    button.addEventListener('click', onClick);
    return button;
  };
  const blocked = builtInBlocked.filter((name) => !rules.allowed.includes(name)).map((name) => chip(name, () => {
    const r = loadBlockRules(); r.allowed = [...new Set([...r.allowed, name])]; saveBlockRules(r); renderBlockedApps();
  }, false));
  const extras = rules.extra.map((exe) => chip(exe.replace(/\.exe$/, ''), () => {
    const r = loadBlockRules(); r.extra = r.extra.filter((e) => e !== exe); saveBlockRules(r); renderBlockedApps();
  }, true));
  $('blocked-chips').replaceChildren(...blocked, ...extras);
  const kept = builtInBlocked.filter((name) => rules.allowed.includes(name));
  $('kept-open').hidden = kept.length === 0;
  $('kept-open').replaceChildren();
  if (kept.length) {
    $('kept-open').append('Kept open: ');
    kept.forEach((name, i) => {
      const undo = el('button', 'link inline-link', name);
      undo.type = 'button';
      undo.title = 'Block again';
      undo.addEventListener('click', () => { const r = loadBlockRules(); r.allowed = r.allowed.filter((a) => a !== name); saveBlockRules(r); renderBlockedApps(); });
      $('kept-open').append(undo, i < kept.length - 1 ? ', ' : '');
    });
  }
}
$('blocked-add').addEventListener('click', async () => {
  const apps = await invoke('running_apps').catch(() => []);
  const rules = loadBlockRules();
  const choices = apps.filter((a) => !rules.extra.includes(a.exe));
  $('app-picker').replaceChildren(...(choices.length ? choices.map((app) => {
    const button = el('button', 'app-choice', app.name);
    button.type = 'button';
    button.addEventListener('click', () => {
      const r = loadBlockRules();
      r.extra = [...new Set([...r.extra, app.exe])].slice(0, 100);
      saveBlockRules(r);
      $('add-app').hidden = true;
      renderBlockedApps();
    });
    return button;
  }) : [el('p', 'fine', 'Open the app you want to block, then try again.')]));
  $('add-app').hidden = false;
});
$('add-app-cancel').addEventListener('click', () => { $('add-app').hidden = true; });

// ---------- Settings: updates, feedback, password, data ----------
$('get-latest').addEventListener('click', () => openUrl('https://locken-app.vercel.app/').catch(() => {}));
$('open-dnd-settings').addEventListener('click', () => openUrl('ms-settings:notifications').catch(() => {}));

let feedbackRating = 0;
function renderStars() {
  $('stars').replaceChildren(...[1, 2, 3, 4, 5].map((n) => {
    const star = el('button', `star${n <= feedbackRating ? ' on' : ''}`, '★');
    star.type = 'button';
    star.setAttribute('role', 'radio');
    star.setAttribute('aria-checked', String(n === feedbackRating));
    star.setAttribute('aria-label', `${n} star${n > 1 ? 's' : ''}`);
    star.addEventListener('click', () => { feedbackRating = n; renderStars(); });
    return star;
  }));
}
$('feedback-open').addEventListener('click', () => {
  feedbackRating = 0; renderStars();
  $('feedback-text').value = ''; $('feedback-error').textContent = '';
  $('feedback-dialog').hidden = false; $('feedback-text').focus();
});
$('feedback-cancel').addEventListener('click', () => { $('feedback-dialog').hidden = true; });
$('feedback-form').addEventListener('submit', (event) => {
  event.preventDefault();
  guarded($('feedback-send'), $('feedback-error'), async () => {
    const text = $('feedback-text').value.trim();
    if (!text) throw new auth.AuthError('Write a few words first.');
    await auth.submitFeedback(feedbackRating, text, '2.0.8');
    $('feedback-dialog').hidden = true;
  });
});

$('password-open').addEventListener('click', () => {
  $('password-code').value = ''; $('password-new').value = ''; $('password-error').textContent = '';
  $('password-hint').textContent = "We'll email you a 6-digit code to confirm it's you.";
  $('password-dialog').hidden = false;
});
$('password-cancel').addEventListener('click', () => { $('password-dialog').hidden = true; });
$('password-send').addEventListener('click', () => {
  guarded($('password-send'), $('password-error'), async () => {
    await auth.sendPasswordChangeCode();
    $('password-hint').textContent = `We sent a 6-digit code to ${user.email}.`;
    $('password-code').focus();
  });
});
$('password-form').addEventListener('submit', (event) => {
  event.preventDefault();
  guarded($('password-save'), $('password-error'), async () => {
    await auth.changePassword(user.email, $('password-new').value, $('password-code').value);
    $('password-new').value = '';
    $('password-dialog').hidden = true;
  });
});
$('sign-out-all').addEventListener('click', async () => {
  if (!window.confirm('Sign out everywhere? Every device signed in to this account, this one included, will need your password and an emailed code to sign in again.')) return;
  await auth.signOutEverywhere().catch(() => {});
  user = null;
  show('auth');
});

// Two-factor authentication (the Mac app's TwoFactorCard).
let tfaEnrollment = null;
function renderTwoFactor() {
  const on = Boolean(user?.totpFactor);
  $('tfa-status').textContent = on ? 'On · a code from your authenticator app is needed to sign in' : 'Require a 6-digit code from Google Authenticator or similar';
  $('tfa-setup').hidden = on || Boolean(tfaEnrollment);
  $('tfa-off').hidden = !on;
  $('tfa-enroll').hidden = !tfaEnrollment;
}
$('tfa-setup').addEventListener('click', () => {
  guarded($('tfa-setup'), $('tfa-error'), async () => {
    tfaEnrollment = await auth.beginTOTPEnrollment();
    // Only Supabase's own SVG QR code is shown, as an image (never as markup in the page).
    $('tfa-qr').src = /^data:image\/svg\+xml[;,]/i.test(tfaEnrollment.qr) ? tfaEnrollment.qr : '';
    $('tfa-secret').textContent = tfaEnrollment.secret;
    $('tfa-code').value = '';
    renderTwoFactor();
    $('tfa-code').focus();
  });
});
$('tfa-enroll').addEventListener('submit', (event) => {
  event.preventDefault();
  guarded($('tfa-confirm'), $('tfa-error'), async () => {
    const code = $('tfa-code').value.trim();
    if (!/^\d{6}$/.test(code)) throw new auth.AuthError('Type the 6-digit code your authenticator app shows.');
    await auth.confirmTOTPEnrollment(tfaEnrollment.factorId, code);
    tfaEnrollment = null;
    user = (await auth.currentUser()) || user;
    renderTwoFactor();
  });
});
$('tfa-cancel').addEventListener('click', () => { tfaEnrollment = null; $('tfa-error').textContent = ''; renderTwoFactor(); });
$('tfa-off').addEventListener('click', () => {
  if (!window.confirm('Turn off two-factor authentication? Signing in will only need your password and an emailed code.')) return;
  guarded($('tfa-off'), $('tfa-error'), async () => {
    await auth.removeTOTP(user.totpFactor);
    user = { ...user, totpFactor: null };
    renderTwoFactor();
  });
});

$('name-input').addEventListener('input', () => {
  $('name-save').disabled = $('name-input').value.trim().slice(0, 40) === displayName();
});
$('name-form').addEventListener('submit', (e) => {
  e.preventDefault();
  const name = $('name-input').value.replace(/[\u0000-\u001f]/g, '').trim().slice(0, 40);
  try {
    if (name) localStorage.setItem(nameKey(user.id), name);
    else localStorage.removeItem(nameKey(user.id)); // empty goes back to the name from your email
  } catch { /* kept until restart */ }
  $('name-input').value = displayName();
  $('name-save').disabled = true;
  const shown = displayName();
  if (shown) writeSignature($('greeting-name'), `${shown}?`, `${user.id}:${shown}`);
  else $('greeting-name').textContent = 'today?';
  updateProfileCard();
});

$('download-data').addEventListener('click', async () => {
  const read = (key) => { try { return JSON.parse(localStorage.getItem(key) || 'null'); } catch { return null; } };
  const server = await auth.serverDataForExport().catch(() => null);
  const data = {
    exportedAt: new Date().toISOString(),
    account: { id: user.id, email: user.email },
    onThisPC: {
      dailyTotals: read(statsKey()), habits: read(habitsKey()), notes: read(notesKey()),
      birth: read(birthKey(user.id)), blockedApps: read(blockKey()), name: localStorage.getItem(nameKey(user.id)),
    },
    onLockensServers: server,
  };
  const link = document.createElement('a');
  link.href = URL.createObjectURL(new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' }));
  link.download = `locken-data-${dayKey(new Date())}.json`;
  link.click();
  setTimeout(() => URL.revokeObjectURL(link.href), 5000);
});

// ---------- Where you'll work (the Mac app's workspace lineup, with Windows apps) ----------
const WORKSPACE = [
  { name: 'Google Chrome', tile: 'Chrome', logo: 'googlechrome' },
  { name: 'Microsoft Edge', tile: 'Edge', logo: 'edge' },
  { name: 'Comet', tile: 'Comet', logo: 'perplexity' },
  { name: 'VS Code', tile: 'VS Code', logo: 'code' },
  { name: 'Cursor', tile: 'Cursor', logo: 'cursor' },
  { name: 'Word', tile: 'Word', logo: 'word' },
  { name: 'Firefox', tile: 'Firefox', logo: 'firefox' },
  { name: 'Brave', tile: 'Brave', logo: 'brave' },
  { name: 'Notion', tile: 'Notion', logo: 'notion' },
  { name: 'Obsidian', tile: 'Obsidian', logo: 'obsidian' },
];
// The tiles shown and their order (names from WORKSPACE). Starts with the six the app always had.
const LINEUP_KEY = 'locken.workspace.lineup';
function loadLineup() {
  try {
    const saved = JSON.parse(localStorage.getItem(LINEUP_KEY) || 'null');
    const valid = Array.isArray(saved) ? saved.filter((name) => WORKSPACE.some((a) => a.name === name)) : [];
    if (valid.length) return valid;
  } catch { /* fall back */ }
  return WORKSPACE.slice(0, 6).map((a) => a.name);
}
let lineup = loadLineup();
const WORKSPACE_KEY = 'locken.workspaceApp';
let workspaceApp = lineup.includes(localStorage.getItem(WORKSPACE_KEY)) ? localStorage.getItem(WORKSPACE_KEY) : lineup[0];
function updateElectricLogo() {
  const app = WORKSPACE.find((a) => a.name === workspaceApp);
  const theme = PAGE_THEME.dashboard;
  try { $('electric').contentWindow?.updateProps?.({ src: `/electric/logos/${app.logo}.svg`, color: theme.light, glowColor: theme.accent }); } catch { /* not loaded yet */ }
}
// Snap the dotted pills and tiles to whole pixels: Doto's dots are sharp on the pixel grid and blur between pixels. Each
// element is re-snapped when it first shows (it is 0 wide while hidden), and everything when the Doto font arrives.
const SNAP = '.pills .pill, .workspace-tile';
const snapObserver = new ResizeObserver(() => requestAnimationFrame(snapPixels));
function snapPixels() {
  const items = [...document.querySelectorAll(SNAP)];
  items.forEach((item) => { item.style.width = ''; });
  items.forEach((item) => {
    const width = parseFloat(getComputedStyle(item).width);
    if (width > 0) item.style.width = `${Math.ceil(width)}px`;
    snapObserver.observe(item);
  });
}
document.fonts?.ready.then(snapPixels);
document.fonts?.addEventListener('loadingdone', snapPixels);
addEventListener('load', snapPixels);

function renderWorkspace() {
  const shown = lineup.map((name) => WORKSPACE.find((a) => a.name === name));
  $('workspace-tiles').replaceChildren(...shown.map((app) => {
    const tile = el('button', `workspace-tile${app.name === workspaceApp ? ' selected' : ''}`, app.tile);
    tile.type = 'button';
    tile.setAttribute('role', 'radio');
    tile.setAttribute('aria-checked', String(app.name === workspaceApp));
    tile.setAttribute('aria-label', app.name);
    tile.addEventListener('click', () => {
      workspaceApp = app.name;
      localStorage.setItem(WORKSPACE_KEY, app.name);
      renderWorkspace();
      updateStartButton();
    });
    return tile;
  }));
  updateElectricLogo();
  snapPixels();
}
$('electric').addEventListener('load', updateElectricLogo);
renderWorkspace();

function saveLineup() {
  try { localStorage.setItem(LINEUP_KEY, JSON.stringify(lineup)); } catch { /* kept this run */ }
  if (!lineup.includes(workspaceApp)) {
    workspaceApp = lineup[0];
    localStorage.setItem(WORKSPACE_KEY, workspaceApp);
  }
  renderWorkspace();
  updateStartButton();
}
function renderLineupEditor() {
  const order = [...lineup, ...WORKSPACE.map((a) => a.name).filter((name) => !lineup.includes(name))];
  $('lineup-list').replaceChildren(...order.map((name) => {
    const app = WORKSPACE.find((a) => a.name === name);
    const on = lineup.includes(name);
    const row = el('li', `lineup-row${on ? '' : ' off'}`);
    const logo = el('img', 'lineup-logo');
    logo.src = `/electric/logos/${app.logo}.svg`;
    logo.alt = '';
    const label = el('label', 'lineup-name');
    const box = el('input');
    box.type = 'checkbox';
    box.checked = on;
    box.disabled = on && lineup.length === 1; // at least one app stays
    box.addEventListener('change', () => {
      lineup = box.checked ? [...lineup, name] : lineup.filter((n) => n !== name);
      saveLineup();
      renderLineupEditor();
    });
    label.append(box, document.createTextNode(` ${name}`));
    row.append(logo, label);
    if (on) {
      const index = lineup.indexOf(name);
      const move = (step, text, hint) => {
        const button = el('button', 'lineup-move', text);
        button.type = 'button';
        button.setAttribute('aria-label', `${hint} ${name}`);
        button.disabled = index + step < 0 || index + step >= lineup.length;
        button.addEventListener('click', () => {
          [lineup[index], lineup[index + step]] = [lineup[index + step], lineup[index]];
          saveLineup();
          renderLineupEditor();
          $('lineup-list').querySelectorAll('.lineup-row')[index + step]?.querySelector(`[aria-label="${hint} ${name}"]`)?.focus();
        });
        return button;
      };
      row.append(move(-1, '↑', 'Move up'), move(1, '↓', 'Move down'));
    }
    return row;
  }));
}
$('lineup-edit').addEventListener('click', () => {
  renderLineupEditor();
  $('lineup-dialog').hidden = false;
  $('lineup-done').focus();
});
$('lineup-done').addEventListener('click', () => { $('lineup-dialog').hidden = true; $('lineup-edit').focus(); });
document.addEventListener('keydown', (event) => { if (event.key === 'Escape' && !$('lineup-dialog').hidden) $('lineup-done').click(); });

// ---------- Session ----------
const goal = $('goal');
const COMMITMENT = 'locken.commitmentMode';
$('commitment-toggle').checked = localStorage.getItem(COMMITMENT) !== 'off';
$('commitment-toggle').addEventListener('change', (event) => {
  localStorage.setItem(COMMITMENT, event.target.checked ? 'on' : 'off');
});

function updateStartButton() {
  const minutes = Number($('length').value);
  $('length-value').textContent = minutes;
  $('start').textContent = `▶ Start ${minutes} min in ${workspaceApp}`;
  const ready = goalSource === 'canvas' ? Boolean(selectedAssignment) : goal.value.trim().length > 0;
  $('start').disabled = !ready || Boolean(session);
  $('setup-hint').textContent = session ? 'A session is already running' : ready ? 'The Shield starts with the timer'
    : goalSource === 'canvas' ? 'Choose a Canvas assignment to start' : "Type what you're working on to start";
}
goal.addEventListener('input', updateStartButton);
$('length').addEventListener('input', updateStartButton);

function format(ms) {
  const total = Math.max(0, Math.round(ms / 1000));
  const m = Math.floor(total / 60);
  const s = total % 60;
  return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
}

/** Every 30 minutes; a single halfway check-in for sessions of 30 minutes or less. */
function firstCheckIn(minutes, startedAt) {
  const gap = minutes <= 30 ? (minutes * 60_000) / 2 : 30 * 60_000;
  return startedAt + gap;
}

// The tray timer's tooltip (the Mac's menu bar timer); sent only when it changes.
let lastTrayText = null;
function setTrayStatus(text) {
  if (text === lastTrayText) return;
  lastTrayText = text;
  invoke('tray_status', { text }).catch(() => {});
}
const RING = 2 * Math.PI * 145;

// ---------- Liquid-glass countdown digits (the Mac's glass timer; both apps draw it from shared/fluidglass-time.js) ----------
const accentNow = () => getComputedStyle(document.documentElement).getPropertyValue('--accent').trim() || '#8C33E6';
let glassTimer = null;
try {
  const glass = createFluidGlassTime($('timer-glass'), { text: $('timer').textContent, accent: accentNow(), fontFamily: 'Montserrat, sans-serif', fallbackText: false });
  if (glass.supported) {
    glassTimer = glass;
    document.body.classList.add('glass-timer');
  }
} catch { /* the plain text timer stays */ }

function renderSession() {
  const now = Date.now();
  const left = session.paused ? session.remaining : session.endsAt - now;
  $('timer').textContent = format(left);
  glassTimer?.update({ text: format(left), accent: accentNow() });
  const done = Math.min(1, Math.max(0, 1 - left / (session.minutes * 60_000)));
  $('ring-fill').style.strokeDasharray = `${RING}`;
  $('ring-fill').style.strokeDashoffset = `${RING * done}`;
  // The Mac countdown's dial: a dot that moves one tick a second, and Focused / Blocked / Ends.
  const elapsed = Math.max(0, Math.round((session.minutes * 60_000 - left) / 1000));
  $('second-dot').style.transform = `rotate(${elapsed * 6}deg)`;
  $('stat-focused').textContent = `${Math.floor(elapsed / 60)}:${String(elapsed % 60).padStart(2, '0')}`;
  $('stat-blocked-now').textContent = session.blocked;
  $('stat-ends').textContent = new Date(session.endsAt).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
  $('nav-live').textContent = format(left);
  document.title = `${format(left)} · Locken`;
  setTrayStatus(`${session.paused ? 'Paused · ' : ''}${format(left)} left · ${session.goal}`);
  if (!$('commit-gate').hidden) $('commit-left').textContent = `${format(left)} left. You set this time for a reason. Take a breath before you decide.`;
  if (session.paused) return;
  if (session.nextCheckIn && now >= session.nextCheckIn) {
    session.nextCheckIn = session.minutes <= 30 ? null : session.nextCheckIn + 30 * 60_000;
    if (session.nextCheckIn && session.nextCheckIn >= session.endsAt) session.nextCheckIn = null;
    invoke('open_checkin').catch(() => {});
  }
  if (left <= 0) finishSession(false);
}

$('setup-form').addEventListener('submit', (event) => {
  event.preventDefault();
  const text = goalSource === 'canvas' ? selectedAssignment?.title || '' : goal.value.trim();
  if (!text || session) return;
  // Like the Mac app: once the papers settle and the timer starts, the app you chose to work in opens.
  const app = workspaceApp;
  startSession(text, Number($('length').value)).then((started) => {
    if (started) invoke('open_workspace_app', { app }).catch(() => {});
  });
});
$('own-goal').addEventListener('input', updateOwnGoal);
$('own-minutes').addEventListener('input', updateOwnGoal);
function updateOwnGoal() {
  const minutes = Number($('own-minutes').value);
  $('own-minutes-value').textContent = `${minutes} min`;
  $('own-start').textContent = `▶ Start ${minutes} min focus`;
  $('own-start').disabled = !$('own-goal').value.trim() || Boolean(session);
}
$('own-goal-form').addEventListener('submit', (event) => {
  event.preventDefault();
  startSession($('own-goal').value.trim(), Number($('own-minutes').value));
});

// The Mac app's SessionIntroView: ten notebook papers fly out and settle (papers.html) between pressing Start and the
// timer page. The page says "flying" when a flight starts and "done" once the stack is home; the timer starts then.
let sessionStarting = false;
function playSessionIntro() {
  return new Promise((resolve) => {
    const pages = document.querySelector('.pages').getBoundingClientRect();
    const frame = document.createElement('iframe');
    frame.className = 'session-intro';
    frame.src = '/papers/papers.html';
    frame.title = '';
    frame.setAttribute('aria-hidden', 'true');
    frame.tabIndex = -1;
    Object.assign(frame.style, { left: `${pages.left}px`, top: `${pages.top}px`, width: `${pages.width}px`, height: `${pages.height}px` });
    let safety = null;
    const finish = () => {
      clearTimeout(safety);
      window.removeEventListener('message', onMessage);
      frame.remove();
      document.querySelector('.pages').classList.remove('intro-playing');
      resolve();
    };
    // If the page never reports back, don't leave the student stuck before their timer.
    const arm = () => { clearTimeout(safety); safety = setTimeout(finish, 6000); };
    const onMessage = (event) => {
      if (event.origin !== window.location.origin || event.source !== frame.contentWindow) return;
      if (event.data?.papers === 'flying') arm();
      else if (event.data?.papers === 'done') finish();
    };
    window.addEventListener('message', onMessage);
    arm();
    document.querySelector('.pages').classList.add('intro-playing'); // as on the Mac, the papers replace the page
    document.body.append(frame);
  });
}

async function startSession(text, minutes) {
  if (!text || session || sessionStarting) return false;
  sessionStarting = true;
  try { await playSessionIntro(); } finally { sessionStarting = false; }
  if (session) return false;
  const startedAt = Date.now();
  session = { goal: text, minutes, planned: minutes, startedAt, endsAt: startedAt + minutes * 60_000, blocked: 0, checkins: [], lastProgress: 0, nextCheckIn: firstCheckIn(minutes, startedAt) };
  session.milestones = [];
  session.milestonesNote = null;
  createMilestones(session, text, minutes);
  saveStats((d) => ({ ...d, sessions: d.sessions + 1 }));
  playFocusSound(); // focus mode just switched on
  await showRunningSession();
  return true;
}

/** Shows the countdown for `session` and starts the Shield (a new session, or one restored after a force quit). */
async function showRunningSession() {
  $('time-adjustment').hidden = true;
  $('session-goal').textContent = session.goal;
  $('ring-goal').textContent = session.goal;
  $('session-blocked').textContent = session.blocked ? `${session.blocked} closed this session.` : 'Nothing closed yet.';
  $('checkins').replaceChildren();
  renderMilestones();
  $('focus-idle').hidden = true;
  $('focus-live').hidden = false;
  updatePauseButton();
  $('nav-live').hidden = false;
  updateStartButton();
  showPage('focus');
  renderSession();
  clearInterval(tick);
  tick = setInterval(renderSession, 1000);
  saveRunningSession();
  const rules = loadBlockRules();
  await invoke('start_blocking', { extra: rules.extra, allowed: rules.allowed }).catch(() => {});
}

// ---------- Surviving a force quit (the Mac app's SavedSession) ----------
// The running session is saved per account on this PC, so a force quit, crash or restart doesn't end it: the
// next launch picks it up with the time it has left. Removed when the session pauses, ends or resets.
const runningKey = () => `locken.session.${user.id}`;
function saveRunningSession() {
  if (!user || !session || session.paused) return;
  const { goal: g, minutes, planned, startedAt, endsAt, blocked, nextCheckIn, lastProgress, milestones } = session;
  try { localStorage.setItem(runningKey(), JSON.stringify({ goal: g, minutes, planned, startedAt, endsAt, blocked, nextCheckIn, lastProgress, milestones })); } catch { /* not saved this time */ }
}
function forgetRunningSession() { if (user) try { localStorage.removeItem(runningKey()); } catch { /* nothing saved */ } }
async function restoreRunningSession() {
  if (session) return;
  let saved = null;
  try { saved = JSON.parse(localStorage.getItem(runningKey()) || 'null'); } catch { /* unreadable: start fresh */ }
  if (!saved || typeof saved.goal !== 'string' || !(saved.endsAt - Date.now() >= 5000)) { forgetRunningSession(); return; }
  session = {
    goal: saved.goal.slice(0, 200), minutes: Number(saved.minutes) || 25, planned: Number(saved.planned) || Number(saved.minutes) || 25,
    startedAt: Number(saved.startedAt) || Date.now(), endsAt: Number(saved.endsAt), blocked: Number(saved.blocked) || 0, checkins: [],
    lastProgress: Number(saved.lastProgress) || 0, nextCheckIn: Number(saved.nextCheckIn) || null,
    milestones: Array.isArray(saved.milestones) ? saved.milestones.filter((m) => typeof m?.text === 'string').map((m) => ({ text: m.text.slice(0, 200), done: Boolean(m.done) })) : [],
  };
  if (session.nextCheckIn && session.nextCheckIn < Date.now()) session.nextCheckIn = Date.now() + 60_000;
  await showRunningSession();
}

// ---------- Commitment mode: a countdown before ending early ----------
let gateTimer = null;
function closeGate() {
  clearInterval(gateTimer);
  $('commit-gate').hidden = true;
}
let gateAction = 'end';
$('end-early').addEventListener('click', () => {
  if (!session) return;
  if ($('commitment-toggle').checked === false) { finishSession(true); return; }
  openCommitGate('end');
});
function openCommitGate(action) {
  gateAction = action;
  const total = action === 'pause' ? 10 : 20;
  let left = total;
  $('commit-title').textContent = { pause: 'Pause this session?', quit: 'Quit Locken mid-session?' }[action] || 'End this session early?';
  const MINI = 2 * Math.PI * 36;
  $('commit-goal').textContent = `“${session.goal}”`;
  $('commit-stop').disabled = true;
  const paint = () => {
    const label = { pause: 'Pause', quit: 'Quit Locken' }[action] || 'End session';
    $('commit-count').textContent = left > 0 ? String(left) : 'OK';
    $('commit-stop').textContent = left > 0 ? `${label} in ${left}s` : label;
    $('commit-stop').disabled = left > 0;
    $('commit-ring').style.strokeDasharray = `${MINI}`;
    $('commit-ring').style.strokeDashoffset = `${MINI * (1 - left / total)}`;
  };
  paint();
  $('commit-gate').hidden = false;
  renderSession();
  $('commit-keep').focus();
  clearInterval(gateTimer);
  gateTimer = setInterval(() => { left = Math.max(0, left - 1); paint(); if (left === 0) clearInterval(gateTimer); }, 1000);
}
$('commit-keep').addEventListener('click', closeGate);
$('commit-stop').addEventListener('click', () => {
  closeGate();
  if (gateAction === 'pause') openPauseReasons();
  else if (gateAction === 'quit') quitLocken();
  else finishSession(true);
});

// ---------- Quitting mid-session (the Mac's applicationShouldTerminate) ----------
// Closing the window quits Locken. While a session runs with Commitment mode on, the 20-second countdown comes
// first; otherwise a running or paused session ends properly (its minutes count) before the window closes. A force
// quit or crash skips this, and the saved session picks up when Locken opens again.
let quitting = false;
async function quitLocken() {
  quitting = true;
  await finishSession(true, { silent: true });
  await getCurrentWindow().destroy();
}
getCurrentWindow().onCloseRequested(async (event) => {
  if (quitting || !session) return;
  if (!session.paused && $('commitment-toggle').checked) {
    event.preventDefault();
    await getCurrentWindow().unminimize().catch(() => {});
    await getCurrentWindow().setFocus().catch(() => {});
    show('main');
    showPage('focus');
    openCommitGate('quit');
    return;
  }
  quitting = true;
  await finishSession(true, { silent: true });
}).catch(() => {});
document.addEventListener('keydown', (event) => { if (event.key === 'Escape' && !$('commit-gate').hidden) closeGate(); });

// ---------- Pause, resume, reset (the Mac app's countdown buttons) ----------
const PAUSE_REASONS = ['Need a break', 'Interrupted', 'Lost focus', 'Finished early', 'Other'];
let pauseReason = null;
function updatePauseButton() {
  $('pause-toggle').textContent = session?.paused ? '▶ Resume' : '❚❚ Pause';
  $('timer').classList.toggle('paused', Boolean(session?.paused));
}
function openPauseReasons() {
  pauseReason = null;
  $('pause-error').textContent = '';
  $('reason-other').value = '';
  $('reason-other-wrap').hidden = true;
  $('reason-pills').replaceChildren(...PAUSE_REASONS.map((reason) => {
    const pill = el('button', 'pill reason', reason);
    pill.type = 'button';
    pill.setAttribute('aria-checked', 'false');
    pill.addEventListener('click', () => {
      if (reason === 'Other') {
        pauseReason = 'Other';
        for (const p of document.querySelectorAll('.reason')) p.setAttribute('aria-checked', String(p === pill));
        $('reason-other-wrap').hidden = false;
        $('reason-other').focus();
        return;
      }
      confirmPause(reason);
    });
    return pill;
  }));
  $('pause-dialog').hidden = false;
}
function confirmPause(reason, note) {
  if (!session) return;
  saveStats((d) => ({ ...d, pauseReasons: { ...(d.pauseReasons || {}), [reason]: ((d.pauseReasons || {})[reason] || 0) + 1 } }));
  $('pause-dialog').hidden = true;
  if (reason === 'Finished early') { finishSession(true); return; }
  session.paused = true;
  session.remaining = Math.max(0, session.endsAt - Date.now());
  forgetRunningSession(); // like the Mac: a paused session isn't picked up after a force quit
  session.note = note || null;
  invoke('stop_blocking').catch(() => {});
  updatePauseButton();
  renderSession();
}
$('reason-other').addEventListener('keydown', (event) => {
  if (event.key !== 'Enter') return;
  const text = $('reason-other').value.trim();
  // Same check as the Mac app: a real reason, not one letter or a keyboard mash.
  if (text.replace(/[^a-z]/gi, '').length < 6 || !/[aeiouy]/i.test(text)) {
    $('pause-error').textContent = "Write a few words about why you're pausing.";
    return;
  }
  confirmPause('Other', text.slice(0, 200));
});
$('pause-keep').addEventListener('click', () => { $('pause-dialog').hidden = true; });
$('pause-toggle').addEventListener('click', async () => {
  if (!session) return;
  if (session.paused) {
    session.paused = false;
    session.endsAt = Date.now() + session.remaining;
    playFocusSound(); // back in focus mode
    saveRunningSession();
    const rules = loadBlockRules();
    await invoke('start_blocking', { extra: rules.extra, allowed: rules.allowed }).catch(() => {});
    updatePauseButton();
    renderSession();
    return;
  }
  if ($('commitment-toggle').checked) openCommitGate('pause'); else openPauseReasons();
});
$('reset-session').addEventListener('click', () => { if (session) finishSession(true, { silent: true }); });

/** Ends the session. Like the Mac app: the timer reaching zero (or a 100% check-in) is "Session complete";
 * ending it yourself, or pausing because you finished, is "Finished early". Both show the celebration. */
async function finishSession(endedEarly, { silent = false } = {}) {
  if (!session) return;
  forgetRunningSession();
  clearInterval(tick);
  closeGate();
  $('pause-dialog').hidden = true;
  await invoke('stop_blocking').catch(() => {});
  const left = session.paused ? session.remaining : Math.max(0, session.endsAt - Date.now());
  const focused = Math.max(0, Math.floor((session.minutes * 60_000 - left) / 60_000));
  saveStats((d) => ({ ...d, minutes: d.minutes + focused }));
  recordFocusForHabits(focused);
  const steps = session.milestones || [];
  const finished = { goal: session.goal, minutes: focused, blocked: session.blocked, endedEarly, stepsDone: steps.filter((m) => m.done).length, stepsTotal: steps.length };
  document.title = 'Locken';
  setTrayStatus('');
  session = null;
  $('nav-live').hidden = true;
  $('focus-live').hidden = true;
  $('focus-idle').hidden = false;
  renderStats();
  updatePauseButton();
  if (silent) { updateStartButton(); updateOwnGoal(); return; }
  playCelebration(finished);
}

// ---------- Intelligent Rephrase (the Mac app's AITaskFormatter, settings card and sparkle button) ----------
// The key and the requests stay in Rust (Credential Manager, per account); the page only ever sees results.
const AI_ENABLED_KEY = 'locken.ai.enabled';
let aiProvider = null;
const aiEnabled = () => { try { return localStorage.getItem(AI_ENABLED_KEY) !== '0'; } catch { return true; } };
/** Claude's, ChatGPT's and Gemini's terms require 18+; Windows always has the birth month and year from sign-up. */
function aiAdult() {
  try {
    const birth = JSON.parse(localStorage.getItem(birthKey(user.id)) || 'null');
    return Boolean(birth) && auth.ageFrom(birth.month, birth.year) >= 18;
  } catch { return false; }
}
const aiReady = () => Boolean(user) && aiEnabled() && aiAdult() && Boolean(aiProvider);
async function refreshAI() {
  if (!user) return;
  aiProvider = await invoke('ai_key_status', { account: user.id }).catch(() => null);
  const on = aiEnabled();
  const adult = aiAdult();
  $('ai-toggle').checked = on;
  $('ai-subtitle').textContent = aiProvider === 'Claude' ? 'Claude · claude-sonnet-5' : aiProvider === 'ChatGPT' ? 'ChatGPT · gpt-4.1-mini' : aiProvider === 'Gemini' ? 'Gemini · newest Flash model your key can use' : 'Rewrites vague session goals into specific ones';
  $('ai-age').hidden = !on || adult;
  $('ai-body').hidden = !on || !adult;
  // Privacy: say exactly what leaves this PC, and to whom.
  $('ai-privacy').textContent = `When you rephrase a goal or start a session, its goal, length and workspace app are sent to ${aiProvider || 'the AI service you add a key for'} to write the rewrite and steps. Email addresses, links and phone numbers are removed first. Nothing else is shared.`;
  $('ai-key-saved').hidden = !aiProvider;
  $('ai-key-form').hidden = Boolean(aiProvider);
  $('ai-key-label').textContent = aiProvider ? `${aiProvider} API key saved in Windows Credential Manager` : '';
  $('rephrase').hidden = !on || !adult;
  updateRephraseButton();
  refreshAssistantSettings();
}
function updateRephraseButton() { $('rephrase').disabled = !goal.value.trim() || $('rephrase').classList.contains('busy'); }
$('ai-toggle').addEventListener('change', () => {
  try { localStorage.setItem(AI_ENABLED_KEY, $('ai-toggle').checked ? '1' : '0'); } catch { /* applies this run */ }
  refreshAI();
});
$('ai-key').addEventListener('input', () => { $('ai-key-save').disabled = !$('ai-key').value.trim(); $('ai-key-error').textContent = ''; });
$('ai-key-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const key = $('ai-key').value;
  if (!key.trim()) return;
  try {
    await invoke('ai_save_key', { account: user.id, key });
    $('ai-key').value = '';
    $('ai-key-save').disabled = true;
    refreshAI();
  } catch (error) {
    $('ai-key-error').textContent = typeof error === 'string' ? error : "Couldn't save the key.";
  }
});
$('ai-key-remove').addEventListener('click', async () => { await invoke('ai_remove_key', { account: user.id }).catch(() => {}); refreshAI(); });
goal.addEventListener('input', () => { updateRephraseButton(); $('rephrase-error').hidden = true; });
$('rephrase').addEventListener('click', async () => {
  const input = goal.value.trim();
  const button = $('rephrase');
  if (!input || button.classList.contains('busy')) return;
  $('rephrase-error').hidden = true;
  const problem = !aiEnabled() ? 'Intelligent Rephrase is turned off in Settings.'
    : !aiAdult() ? 'AI features are for people 18 and older.'
      : !aiProvider ? 'Add a Claude, ChatGPT or Gemini API key in Settings to use Intelligent Rephrase.' : null;
  if (problem) { showRephraseError(problem, true); return; }
  button.classList.add('busy');
  updateRephraseButton();
  try {
    const rewritten = await invoke('ai_rephrase', { account: user.id, goal: input, minutes: Number($('length').value), app: workspaceApp });
    goal.value = String(rewritten).slice(0, 200);
    goal.dispatchEvent(new Event('input', { bubbles: true }));
    goal.focus(); // hand the field back so the rewrite can be tweaked before starting
  } catch (error) {
    const message = typeof error === 'string' ? error : "Couldn't reach the AI service.";
    showRephraseError(message, /Settings/.test(message));
  } finally {
    button.classList.remove('busy');
    updateRephraseButton();
  }
});
function showRephraseError(message, offerSettings) {
  $('rephrase-error-text').textContent = message;
  $('rephrase-settings').hidden = !offerSettings;
  $('rephrase-error').hidden = false;
}
$('rephrase-settings').addEventListener('click', () => showPage('settings'));

// ---------- Canvas (the Mac app's CanvasAPIManager, setup picker and CanvasAssignmentsCard) ----------
// Rust keeps the token or feed link and does every Canvas request; the page gets assignments only.
const canvas = { linked: null, all: [], loading: false, error: '', synced: false, lastCheckedOff: null };
let canvasCardSelected = null;
let canvasCardMinutes = 25;
const checkedKey = () => `locken.canvas.checked.${user.id}`;
function loadChecked() { try { return new Set(JSON.parse(localStorage.getItem(checkedKey()) || '[]')); } catch { return new Set(); } }
function saveChecked(set) { try { localStorage.setItem(checkedKey(), JSON.stringify([...set].sort().slice(-500))); } catch { /* kept this run */ } }
const pendingAssignments = () => { const checked = loadChecked(); return canvas.all.filter((a) => !checked.has(a.id)); };

/** UTC offset (ms) of a time zone at an instant, for reading calendar-feed times given in that zone. */
function zoneOffset(ms, timeZone) {
  const parts = Object.fromEntries(new Intl.DateTimeFormat('en-US', { timeZone, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit' })
    .formatToParts(new Date(ms)).map((p) => [p.type, p.value]));
  return Date.UTC(+parts.year, +parts.month - 1, +parts.day, +parts.hour, +parts.minute, +parts.second) - ms;
}
function icsDate(value, params) {
  const all = /^(\d{4})(\d{2})(\d{2})$/.exec(value);
  // All-day due date: due at the end of that local day.
  if (all) return new Date(+all[1], +all[2] - 1, +all[3], 23, 59);
  const m = /^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z?)$/.exec(value);
  if (!m) return null;
  const fields = [+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]];
  if (m[7]) return new Date(Date.UTC(...fields));
  const tzid = /TZID="?([^";]+)"?/i.exec(params)?.[1];
  try {
    if (tzid) {
      const guess = Date.UTC(...fields);
      const first = guess - zoneOffset(guess, tzid);
      return new Date(guess - zoneOffset(first, tzid));
    }
  } catch { /* unknown time zone: read it as local time */ }
  return new Date(...fields);
}
const unescapeIcs = (t) => t.replace(/\\[nN]/g, ' ').replace(/\\,/g, ',').replace(/\;/g, ';').replace(/\\\\/g, '\\');
/** A Canvas calendar feed (RFC 5545), assignment events only. */
function parseFeed(ics) {
  const lines = ics.replace(/\r\n/g, '\n').replace(/\n[ \t]/g, '').split('\n');
  const out = [];
  let event = null;
  for (const line of lines) {
    if (line === 'BEGIN:VEVENT') { event = {}; continue; }
    if (line === 'END:VEVENT') {
      const uid = event?.UID?.value || '';
      if (uid.includes('assignment') && event.SUMMARY) {
        const summary = unescapeIcs(event.SUMMARY.value);
        // Canvas appends the course as " [COURSE CODE]".
        const course = / \[([^\]]*)\]$/.exec(summary);
        const date = event.DTSTART || event.DTEND;
        out.push({ id: uid.slice(0, 200), title: (course ? summary.slice(0, course.index) : summary).slice(0, 300), course: (course?.[1] || '').slice(0, 200), due: date ? icsDate(date.value, date.params) : null });
      }
      event = null;
      continue;
    }
    const colon = line.indexOf(':');
    if (!event || colon < 0) continue;
    const [name, ...rest] = line.slice(0, colon).split(';');
    event[name.toUpperCase()] = { params: rest.join(';'), value: line.slice(colon + 1) };
  }
  return out;
}
/** Due within the last day or later, soonest first; undated ones last. */
function upcoming(list) {
  const cutoff = Date.now() - 24 * 3600_000;
  return list.filter((a) => !a.due || a.due.getTime() >= cutoff)
    .sort((a, b) => (a.due ? a.due.getTime() : Infinity) - (b.due ? b.due.getTime() : Infinity));
}
function applyLoaded(loaded) {
  const list = loaded?.kind === 'feed' ? parseFeed(String(loaded.text || ''))
    : (loaded?.items || []).map((a) => ({ id: String(a.id), title: String(a.title), course: String(a.course || ''), due: a.due ? new Date(a.due) : null }));
  canvas.all = upcoming(list.filter((a) => a.title && !(a.due && Number.isNaN(a.due.getTime()))));
  canvas.synced = true;
}
const canvasError = (error) => (typeof error === 'string' ? error : "Couldn't reach Canvas. Try again.");
function dueText(a) {
  if (!a.due) return 'No due date';
  const when = a.due.toLocaleString([], { weekday: 'short', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
  return `${a.due.getTime() < Date.now() ? 'Was due' : 'Due'} ${when}`;
}
const detailLine = (a) => [a.course, dueText(a)].filter(Boolean).join(' • ');

async function refreshCanvasStatus() {
  if (!user) return;
  canvas.linked = await invoke('canvas_status', { account: user.id }).catch(() => null);
  canvas.all = []; canvas.synced = false; canvas.error = ''; canvas.lastCheckedOff = null;
  renderCanvas();
  if (canvas.linked) refreshCanvas();
}
async function refreshCanvas() {
  if (!user || !canvas.linked || canvas.loading) return;
  canvas.loading = true; canvas.error = '';
  renderCanvas();
  try { applyLoaded(await invoke('canvas_refresh', { account: user.id })); } catch (error) { canvas.error = canvasError(error); }
  canvas.loading = false;
  renderCanvas();
}
async function unlinkCanvas() {
  await invoke('canvas_unlink', { account: user.id }).catch(() => {});
  canvas.linked = null; canvas.all = []; canvas.error = ''; canvas.lastCheckedOff = null; canvas.synced = false;
  selectedAssignment = null; canvasCardSelected = null;
  renderCanvas();
}

function renderCanvas() {
  // New: link row or picker.
  $('canvas-link-row').hidden = Boolean(canvas.linked);
  $('canvas-picker').hidden = !canvas.linked;
  if (selectedAssignment && !pendingAssignments().some((a) => a.id === selectedAssignment.id)) selectedAssignment = null;
  $('canvas-choose-title').textContent = selectedAssignment ? selectedAssignment.title
    : canvas.loading && !canvas.all.length ? 'Loading your assignments…' : 'Choose a Canvas assignment';
  $('canvas-choose-sub').textContent = selectedAssignment ? detailLine(selectedAssignment) : '';
  $('canvas-choose-sub').hidden = !selectedAssignment;
  $('canvas-choose').classList.toggle('chosen', Boolean(selectedAssignment));
  if (!$('canvas-pop').hidden) renderCanvasList();
  renderCanvasCard();
  updateStartButton();
}
function renderCanvasList() {
  const query = $('canvas-search').value.trim().toLowerCase();
  const list = pendingAssignments().filter((a) => !query || a.title.toLowerCase().includes(query) || a.course.toLowerCase().includes(query));
  $('canvas-pop-error').textContent = canvas.error;
  $('canvas-pop-error').hidden = !canvas.error;
  if (!list.length) {
    const empty = canvas.loading ? 'Loading your assignments…'
      : !pendingAssignments().length ? 'No upcoming assignments. Switch to My Own Goal to type one instead.' : `No assignments match “${$('canvas-search').value.trim()}”.`;
    $('canvas-list').replaceChildren(el('li', 'canvas-empty', empty));
    return;
  }
  $('canvas-list').replaceChildren(...list.map((a) => {
    const row = el('li', `canvas-option${selectedAssignment?.id === a.id ? ' selected' : ''}`);
    row.setAttribute('role', 'option');
    row.setAttribute('aria-selected', String(selectedAssignment?.id === a.id));
    row.tabIndex = 0;
    row.append(el('span', 'canvas-option-title', a.title), el('span', 'fine', detailLine(a)));
    const choose = () => { selectedAssignment = a; closeCanvasPop(); renderCanvas(); };
    row.addEventListener('click', choose);
    row.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); choose(); } });
    return row;
  }));
}
function closeCanvasPop() { $('canvas-pop').hidden = true; $('canvas-choose').setAttribute('aria-expanded', 'false'); }
$('canvas-choose').addEventListener('click', () => {
  const opening = $('canvas-pop').hidden;
  $('canvas-pop').hidden = !opening;
  $('canvas-choose').setAttribute('aria-expanded', String(opening));
  if (opening) { $('canvas-search').value = ''; renderCanvasList(); $('canvas-search').focus(); }
});
$('canvas-search').addEventListener('input', renderCanvasList);
$('canvas-search').addEventListener('keydown', (e) => {
  if (e.key === 'Enter') { e.preventDefault(); $('canvas-list').querySelector('.canvas-option')?.click(); } // Return picks the top match
  if (e.key === 'Escape') { closeCanvasPop(); $('canvas-choose').focus(); }
});
document.addEventListener('click', (e) => { if (!$('canvas-pop').hidden && !$('canvas-picker').contains(e.target)) closeCanvasPop(); });
for (const button of document.querySelectorAll('.canvas-refresh')) button.addEventListener('click', refreshCanvas);
for (const button of document.querySelectorAll('.canvas-unlink')) button.addEventListener('click', unlinkCanvas);

for (const pill of document.querySelectorAll('.goal-source .pill')) {
  pill.addEventListener('click', () => {
    goalSource = pill.dataset.source;
    for (const p of document.querySelectorAll('.goal-source .pill')) p.setAttribute('aria-checked', String(p === pill));
    $('goal-canvas').hidden = goalSource !== 'canvas';
    document.querySelector('.goal-field').hidden = goalSource === 'canvas';
    $('rephrase-error').hidden = true;
    if (goalSource === 'manual') goal.focus();
    updateStartButton();
  });
}

function renderCanvasCard() {
  $('canvas-card-actions').hidden = !canvas.linked;
  const body = $('canvas-card-body');
  if (!canvas.linked) {
    const open = el('button', 'primary pill-btn small-pill canvas-open-link', 'Link Canvas');
    open.type = 'button';
    open.addEventListener('click', openCanvasDialog);
    body.replaceChildren(el('p', 'fine', 'Link Canvas to see your upcoming assignments here. Pick one, set a time limit, and start focusing.'), open);
    return;
  }
  const nodes = [];
  if (canvas.error) nodes.push(el('p', 'canvas-error', canvas.error));
  const list = pendingAssignments();
  if (!list.length) nodes.push(el('p', 'fine', canvas.loading || !canvas.synced ? 'Loading assignments…' : 'No upcoming assignments.'));
  for (const a of list) {
    const selected = canvasCardSelected === a.id;
    const row = el('div', `canvas-row${selected ? ' selected' : ''}`);
    const pick = el('button', 'canvas-row-pick');
    pick.type = 'button';
    pick.setAttribute('aria-pressed', String(selected));
    pick.append(el('span', 'step-dot'), Object.assign(el('span', 'canvas-row-text'), {}));
    pick.lastChild.append(el('span', 'canvas-option-title', a.title), el('span', 'fine', detailLine(a)));
    pick.addEventListener('click', () => { canvasCardSelected = selected ? null : a.id; renderCanvasCard(); });
    row.append(pick);
    if (selected) {
      const extra = el('div', 'canvas-row-extra');
      const label = el('div', 'limit-row');
      const value = el('b', '', `${canvasCardMinutes} min`);
      label.append(el('p', 'mini-label', 'TIME LIMIT'), value);
      const slider = Object.assign(document.createElement('input'), { type: 'range', min: 5, max: 180, step: 5, value: canvasCardMinutes });
      slider.setAttribute('aria-label', 'Time limit in minutes');
      const start = el('button', 'primary pill-btn', `▶ Start ${canvasCardMinutes} min focus`);
      start.type = 'button';
      slider.addEventListener('input', () => { canvasCardMinutes = Number(slider.value); value.textContent = `${canvasCardMinutes} min`; start.textContent = `▶ Start ${canvasCardMinutes} min focus`; });
      // For work handed in on paper or in person, which Canvas never sees as submitted.
      const done = el('button', 'link', 'Mark as done');
      done.type = 'button';
      done.title = 'Hides it here. Use this for work you hand in on paper or in person.';
      done.addEventListener('click', () => { const set = loadChecked(); set.add(a.id); saveChecked(set); canvas.lastCheckedOff = a; canvasCardSelected = null; renderCanvas(); });
      start.addEventListener('click', () => { canvasCardSelected = null; startSession(a.title, canvasCardMinutes); });
      const foot = el('div', 'canvas-row-foot');
      foot.append(done, start);
      extra.append(label, slider, foot);
      row.append(extra);
    }
    nodes.push(row);
  }
  const checkedCount = canvas.all.filter((a) => loadChecked().has(a.id)).length;
  if (canvas.lastCheckedOff) {
    const undo = el('button', 'link', 'Undo');
    undo.type = 'button';
    undo.addEventListener('click', () => { const set = loadChecked(); set.delete(canvas.lastCheckedOff.id); saveChecked(set); canvas.lastCheckedOff = null; renderCanvas(); });
    const foot = el('div', 'canvas-foot');
    foot.append(el('span', 'fine', `Marked “${canvas.lastCheckedOff.title}” as done.`), undo);
    nodes.push(foot);
  } else if (checkedCount > 0) {
    const restore = el('button', 'link', 'Show them again');
    restore.type = 'button';
    restore.addEventListener('click', () => { saveChecked(new Set()); renderCanvas(); });
    const foot = el('div', 'canvas-foot');
    foot.append(el('span', 'fine', `${checkedCount} checked off by hand`), restore);
    nodes.push(foot);
  }
  body.replaceChildren(...nodes);
}

// Link dialog (the Mac's LinkCanvasSheet).
let canvasMethod = 'token';
function openCanvasDialog() {
  $('canvas-link-error').textContent = '';
  $('canvas-dialog').hidden = false;
  (canvasMethod === 'token' ? $('canvas-address') : $('canvas-feed')).focus();
  updateCanvasSubmit();
}
for (const b of document.querySelectorAll('.canvas-open-link')) b.addEventListener('click', openCanvasDialog);
function updateCanvasSubmit() {
  $('canvas-link-submit').disabled = canvasMethod === 'token' ? !$('canvas-address').value.trim() || !$('canvas-token').value.trim() : !$('canvas-feed').value.trim();
}
for (const id of ['canvas-address', 'canvas-token', 'canvas-feed']) $(id).addEventListener('input', updateCanvasSubmit);
for (const pill of document.querySelectorAll('.canvas-method')) {
  pill.addEventListener('click', () => {
    canvasMethod = pill.dataset.method;
    for (const p of document.querySelectorAll('.canvas-method')) p.setAttribute('aria-checked', String(p === pill));
    $('canvas-token-fields').hidden = canvasMethod !== 'token';
    $('canvas-feed-fields').hidden = canvasMethod !== 'feed';
    $('canvas-link-error').textContent = '';
    updateCanvasSubmit();
  });
}
$('canvas-link-cancel').addEventListener('click', () => { $('canvas-dialog').hidden = true; });
$('canvas-form').addEventListener('submit', (event) => {
  event.preventDefault();
  guarded($('canvas-link-submit'), $('canvas-link-error'), async () => {
    let loaded;
    try {
      loaded = canvasMethod === 'token'
        ? await invoke('canvas_link_token', { account: user.id, address: $('canvas-address').value, token: $('canvas-token').value })
        : await invoke('canvas_link_feed', { account: user.id, url: $('canvas-feed').value });
    } catch (error) { throw new auth.AuthError(canvasError(error)); }
    $('canvas-token').value = '';
    $('canvas-feed').value = '';
    $('canvas-dialog').hidden = true;
    canvas.linked = await invoke('canvas_status', { account: user.id }).catch(() => ({ method: canvasMethod, host: '' }));
    canvas.error = '';
    applyLoaded(loaded);
    renderCanvas();
  });
});

// ---------- Steps for this session (the Mac app's FocusMilestonesCard) ----------
// Without an AI key the Mac plans steps by time; this is the same plan. Steps live with the session only.
function plannedMilestones(goalText, minutes) {
  const subject = goalText.length > 40 ? `${goalText.slice(0, 38).trim()}…` : goalText;
  const edge = Math.max(2, Math.floor(minutes / 10));
  const steps = [`Plan (first ${edge} min): decide what done looks like`];
  if (minutes >= 50) steps.push(`Work on ${subject}`, `Halfway (${Math.floor(minutes / 2)} min): check progress, adjust the plan`, `Keep going on ${subject}`);
  else steps.push(`Work on ${subject}`);
  steps.push(`Wrap up (last ${edge} min): check your work, note next steps`);
  return steps;
}
/** Steps for a new session: written by the AI when a key is set (and the student is 18+), otherwise planned by
 * time. Steps the student adds while this runs are kept. */
async function createMilestones(target, goalText, minutes) {
  if (!aiReady()) {
    target.milestones = plannedMilestones(goalText, minutes).map((step) => ({ text: step, done: false }));
    renderMilestones();
    return;
  }
  target.creatingMilestones = true;
  renderMilestones();
  let steps;
  try {
    steps = await invoke('ai_milestones', { account: user.id, goal: goalText, minutes, app: workspaceApp });
    target.milestonesNote = `Written by ${aiProvider} for your goal.`;
  } catch (error) {
    steps = plannedMilestones(goalText, minutes);
    target.milestonesNote = `Planned by time. ${typeof error === 'string' ? error : "Couldn't reach the AI service."}`;
  }
  target.creatingMilestones = false;
  if (session !== target) return; // the session ended meanwhile
  target.milestones = steps.map((step) => ({ text: String(step).slice(0, 200), done: false })).concat(target.milestones);
  renderMilestones();
}
function renderMilestones() {
  const steps = session?.milestones || [];
  const done = steps.filter((m) => m.done).length;
  $('steps-summary').textContent = session?.creatingMilestones ? 'Creating steps for this session…'
    : steps.length ? `${done} of ${steps.length} done` : 'Steps for your session appear here when it starts. Add your own below.';
  $('steps-note').textContent = session?.creatingMilestones ? '' : session?.milestonesNote || '';
  $('steps-note').hidden = !$('steps-note').textContent;
  saveRunningSession(); // ticked or added steps survive a force quit too
  $('steps').replaceChildren(...steps.map((step, index) => {
    const row = el('li', `step${step.done ? ' done' : ''}`);
    const toggle = el('button', 'step-toggle');
    toggle.type = 'button';
    toggle.title = step.done ? 'Mark as not done' : 'Mark as done';
    toggle.setAttribute('aria-pressed', String(step.done));
    toggle.append(el('span', 'step-dot'), el('span', 'step-text', step.text));
    toggle.addEventListener('click', () => { step.done = !step.done; renderMilestones(); });
    const remove = el('button', 'step-remove', '×');
    remove.type = 'button';
    remove.title = 'Remove milestone';
    remove.setAttribute('aria-label', `Remove ${step.text}`);
    remove.addEventListener('click', () => { session.milestones.splice(index, 1); renderMilestones(); });
    row.append(toggle, remove);
    return row;
  }));
}
$('step-new').addEventListener('input', () => { $('step-add-btn').disabled = !$('step-new').value.trim() || !session; });
$('step-add').addEventListener('submit', (event) => {
  event.preventDefault();
  const text = $('step-new').value.trim().slice(0, 200);
  if (!text || !session) return;
  session.milestones.push({ text, done: false });
  $('step-new').value = '';
  $('step-add-btn').disabled = true;
  renderMilestones();
});

// ---------- Finish celebration (the Mac app's SessionCelebrationView) ----------
let celebrationTimers = [];
function playCelebration({ goal: finishedGoal, minutes, blocked, endedEarly, stepsDone = 0, stepsTotal = 0 }) {
  const card = $('done-card');
  celebrationTimers.forEach(clearTimeout);
  celebrationTimers = [];
  const title = endedEarly ? 'Finished early' : 'Session complete';
  const stats = [`${minutes} min focused`];
  if (stepsTotal > 0) stats.push(`${stepsDone} of ${stepsTotal} steps done`);
  if (blocked > 0) stats.push(`${blocked} distraction${blocked === 1 ? '' : 's'} blocked`);
  // TextGenerateEffect: each word fades in from a blur, 0.2 s apart.
  $('done-title').replaceChildren(...title.split(' ').map((word, i, words) => {
    const span = el('span', 'cel-word', i < words.length - 1 ? `${word} ` : word);
    span.style.animationDelay = `${i * 200}ms`;
    return span;
  }));
  $('done-title').setAttribute('aria-label', title);
  $('done-goal').textContent = finishedGoal;
  $('done-stats').replaceChildren(...stats.map((text, i) => {
    const chip = el('span', 'cel-stat', text);
    chip.style.transitionDelay = `${i * 60}ms`;
    return chip;
  }));
  card.className = 'celebrate';
  card.hidden = false;
  $('done-ok').focus();
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
    card.classList.add('unlocked', 'details');
    return;
  }
  // Same beats as the Mac: unlock at 250 ms, a small settle on the body, then the numbers and buttons.
  const at = (ms, fn) => celebrationTimers.push(setTimeout(fn, ms));
  at(250, () => card.classList.add('unlocked'));
  at(550, () => card.classList.add('pulse'));
  at(710, () => { card.classList.remove('pulse'); card.classList.add('details'); });
}
function dismissCelebration(toDashboard) {
  celebrationTimers.forEach(clearTimeout);
  $('done-card').hidden = true;
  goal.value = '';
  selectedAssignment = null;
  renderCanvas();
  updateStartButton();
  $('own-goal').value = '';
  updateOwnGoal();
  if (toDashboard) showPage('dashboard');
}
$('done-ok').addEventListener('click', () => dismissCelebration(false));
$('done-again').addEventListener('click', () => dismissCelebration(true));
window.addEventListener('keydown', (event) => { if (event.key === 'Escape' && !$('done-card').hidden) dismissCelebration(false); });

listen('app-blocked', (event) => {
  if (!session) return;
  session.blocked += 1;
  saveRunningSession();
  saveStats((d) => ({ ...d, blocked: d.blocked + 1 }));
  const name = String(event.payload?.name || 'An app').slice(0, 60);
  $('session-blocked').textContent = `Closed ${name}. ${session.blocked} closed this session.`;
});

// ---------- Check-ins and Adaptive time (the Mac app's CheckInWindowManager and applyCheckIn) ----------
const ADAPTIVE_KEY = 'locken.adaptiveTime';
const adaptiveOn = () => { try { return localStorage.getItem(ADAPTIVE_KEY) === '1'; } catch { return false; } };
document.querySelectorAll('.adaptive-toggle').forEach((toggle) => {
  toggle.checked = adaptiveOn();
  toggle.addEventListener('change', () => {
    try { localStorage.setItem(ADAPTIVE_KEY, toggle.checked ? '1' : '0'); } catch { /* the switch still works this run */ }
    document.querySelectorAll('.adaptive-toggle').forEach((other) => { other.checked = toggle.checked; });
  });
});

/** Same formula as the Mac app: the rest of the goal at the pace so far, 5 min at least, twice the plan (3 h) at most. */
function adaptedRemaining(elapsed, planned, progress) {
  if (elapsed <= 0) return null;
  if (progress >= 100) return 0;
  if (progress <= 0) return null;
  const needed = (elapsed * (100 - progress)) / progress;
  const longestTotal = Math.min(planned * 2, 180 * 60);
  const upper = Math.max(longestTotal - elapsed, 5 * 60);
  return Math.round(Math.min(Math.max(needed, 5 * 60), upper) / 60) * 60;
}

function sessionSeconds() {
  const left = session.paused ? session.remaining : Math.max(0, session.endsAt - Date.now());
  const leftSeconds = Math.round(left / 1000);
  return { leftSeconds, elapsed: Math.max(0, Math.round(session.minutes * 60) - leftSeconds) };
}

// The check-in window asks for the goal and time left when it opens.
listen('checkin-ready', () => {
  if (!session) return;
  const { leftSeconds, elapsed } = sessionSeconds();
  emitTo('checkin', 'checkin-state', {
    goal: session.goal, secondsLeft: leftSeconds, lastProgress: session.lastProgress || 0,
    adaptive: adaptiveOn(), elapsed, planned: session.planned * 60,
  }).catch(() => {});
});

listen('checkin-answer', (event) => {
  if (!session) return;
  const progress = Math.round(Number(event.payload?.progress));
  if (!Number.isFinite(progress) || progress < 0 || progress > 100) return;
  session.lastProgress = progress;
  session.checkins.push(progress);
  const li = document.createElement('li');
  li.textContent = `${format(Date.now() - session.startedAt)} in: ${progress}% of the way`;
  $('checkins').append(li);
  if (!adaptiveOn()) return;
  const { leftSeconds, elapsed } = sessionSeconds();
  const remaining = adaptedRemaining(elapsed, session.planned * 60, progress);
  if (remaining === null) return;
  const adjustment = $('time-adjustment');
  if (remaining === 0) {
    adjustment.textContent = "You said you're done, so the session ended.";
    adjustment.hidden = false;
    finishSession(false);
    return;
  }
  if (remaining === leftSeconds) return;
  session.minutes = (elapsed + remaining) / 60;
  if (session.paused) session.remaining = remaining * 1000;
  else session.endsAt = Date.now() + remaining * 1000;
  if (!session.nextCheckIn && remaining > 30 * 60) session.nextCheckIn = Date.now() + 30 * 60_000;
  saveRunningSession();
  adjustment.textContent = `Adjusted at your ${progress}% check-in: ${remaining / 60} min left (was ${Math.floor(leftSeconds / 60)}).`;
  adjustment.hidden = false;
  renderSession();
});

// ---------- Background fibers (the Mac app's GhostFibersBackgroundView) ----------
(function fibers() {
  const canvas = $('fibers');
  const context = canvas.getContext('2d');
  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const layers = 5;
  let last = 0;
  function draw(now) {
    const ratio = window.devicePixelRatio || 1;
    const width = canvas.clientWidth;
    const height = canvas.clientHeight;
    if (canvas.width !== Math.round(width * ratio) || canvas.height !== Math.round(height * ratio)) {
      canvas.width = Math.round(width * ratio);
      canvas.height = Math.round(height * ratio);
    }
    context.setTransform(ratio, 0, 0, ratio, 0, 0);
    context.clearRect(0, 0, width, height);
    const time = now / 1000;
    for (let i = 0; i < layers; i++) {
      const fade = 0.5 + 0.5 * i / (layers - 1);
      const phase = i * 1.7;
      const amplitude = height * 0.05;
      const baseY = height * (0.15 + 0.65 * i / (layers - 1));
      context.beginPath();
      for (let x = 0; x <= width; x += 10) {
        const progress = x / Math.max(width, 1);
        const y = baseY + Math.sin(progress * 6 + time * 0.3 + phase) * amplitude
          + Math.sin(progress * 3 - time * 0.15 + phase) * amplitude * 0.4;
        if (x === 0) context.moveTo(x, y); else context.lineTo(x, y);
      }
      // A soft violet glow, then the thin line on top.
      context.shadowColor = `rgba(${fiberColor}, ${0.4 * fade})`;
      context.shadowBlur = 8;
      context.strokeStyle = `rgba(${fiberColor}, ${0.16 * fade})`;
      context.lineWidth = 3;
      context.stroke();
      context.shadowBlur = 0;
      context.strokeStyle = `rgba(255, 255, 255, ${0.4 * fade})`;
      context.lineWidth = 1.2;
      context.stroke();
    }
  }
  function loop(now) {
    // The fibers drift slowly: 20 frames a second, and none while the window is hidden.
    if (!document.hidden && now - last > 50) { last = now; draw(now); }
    requestAnimationFrame(loop);
  }
  if (reduce) draw(0); else requestAnimationFrame(loop);
  window.addEventListener('resize', () => draw(performance.now()));
})();

// ---------- Assistant: the main window's own functions it may read and (after the student confirms) call ----------
initAssistant({
  userId: () => user?.id || '',
  aiAdult: () => aiAdult(),
  aiEnabled: () => aiEnabled(),
  aiProvider: () => aiProvider,
  todayStats: () => loadStats(),
  weekMinutes: () => {
    let all = {};
    try { all = JSON.parse(localStorage.getItem(statsKey()) || '{}'); } catch { /* none yet */ }
    return [...Array(7)].reduce((sum, _, i) => sum + (all[addDays(new Date(), -i).toLocaleDateString('en-CA')]?.minutes || 0), 0);
  },
  session: () => session,
  habitsToday: () => {
    const now = new Date();
    return loadHabits().map(normalizeHabit).filter((h) => isScheduled(h, now)).map((h) => ({ id: h.id, name: h.name, done: isHabitDone(h, now), streak: habitStreak(h) }));
  },
  assignments: () => upcoming(pendingAssignments()).map((a) => ({ id: a.id, title: a.title, course: a.course, due: a.due ? dueText(a).replace(/^(Was due|Due) /, '') : '' })),
  canvasLinked: () => Boolean(canvas.linked),
  startSession: async (text, minutes) => { showPage('focus'); await startSession(text, minutes); },
  completeStep: (step) => { step.done = true; renderMilestones(); },
  checkOffAssignment: (id) => { const set = loadChecked(); set.add(id); saveChecked(set); renderCanvas(); },
  completeHabit: (id) => toggleHabit(id, dayKey(new Date())),
  addNote: (title, body) => {
    const list = loadNotes();
    if (list.length >= 500) throw new Error('full');
    list.push({ id: crypto.randomUUID(), title, body, updatedAt: Date.now() });
    saveNotes(list);
  },
  showPage: (page) => showPage(page),
  pauseSession: () => { showPage('focus'); $('pause-toggle').click(); },
  resumeSession: () => { showPage('focus'); $('pause-toggle').click(); },
});
// The Mac's BorderGlow on Locken's buttons: a glow in the current tab's colour that follows the pointer near the edge.
mountButtonGlow();

// ---------- Start ----------
(async () => {
  // The padlock reveal plays over whatever opens first, every time Locken opens (as on the Mac).
  const style = document.createElement('style');
  style.textContent = launchRevealCss + receiptCss;
  document.head.append(style);
  const reveal = playLaunchReveal();
  updateGoogleButton();
  try {
    const verified = await auth.currentUser();
    if (verified?.needsMFA) { openMFA(verified); await reveal; return; }
    if (verified) { await enterApp(verified); await reveal; return; }
  } catch { /* fall through to sign-in */ }
  show('auth');
  // Locken opened by Google's sign-in link while it wasn't running.
  getCurrent().then(handleSignInLink).catch(() => {});
})();
