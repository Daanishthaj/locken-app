// The Admin page (owner only): a compact Windows version of the Mac app's admin console. Overview, accounts (with
// ban and unban), feedback and recent events, all from the `admin-overview` Edge Function, which checks on the server
// that the caller is an admin. Everything is drawn with textContent, never as HTML, since emails and feedback are
// written by other people.
import * as auth from './auth.js';

const $ = (id) => document.getElementById(id);
const SECTIONS = ['Overview', 'Accounts', 'Feedback', 'Events'];
let section = 'Overview';
let data = null;
let loading = false;
let selectedId = null;
let confirming = false;
let working = false;
let query = '';
let banError = '';

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

const when = (iso) => {
  if (!iso) return 'never';
  const date = new Date(iso);
  return Number.isNaN(date.getTime()) ? 'never' : date.toLocaleString(undefined, { month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit' });
};

function kpi(label, value, note) {
  const box = el('div', 'card admin-kpi');
  box.append(el('p', 'mini-label', label), el('p', 'admin-kpi-value', String(value ?? '—')));
  if (note) box.append(el('p', 'fine', note));
  return box;
}

function tag(text, kind) { return el('span', `admin-tag ${kind || ''}`.trim(), text); }

function adminIds() { return new Set(data?.analytics?.security?.admins || []); }

function renderOverview(body) {
  const t = data.totals || {};
  const grid = el('div', 'admin-kpis');
  grid.append(
    kpi('ACCOUNTS', t.accounts, `${t.newLast7Days ?? 0} new in the last 7 days`),
    kpi('ACTIVE, 7 DAYS', t.activeLast7Days, `${t.activeLast30Days ?? 0} in the last 30 days`),
    kpi('NEVER SIGNED IN', t.neverSignedIn),
    kpi('BANNED', t.banned ?? 0),
    kpi('FEEDBACK', t.feedback, t.averageRating ? `Average ${t.averageRating} of 5` : 'No ratings yet'),
    kpi('GOOGLE SIGN-IN', t.google),
  );
  const health = el('div', 'card admin-panel');
  health.append(el('p', 'setting-title', 'System health'));
  const live = data.liveVersion;
  const server = data.updateServer || {};
  const db = data.database || {};
  const rows = [
    ['Live Mac version', live ? `${live.version} (build ${live.build})${live.maintenanceMode ? ', maintenance mode on' : ''}` : 'Unknown'],
    ['Update server', server.reachable ? `Up, ${server.ms} ms` : `Down${server.status ? ` (HTTP ${server.status})` : ''}`],
    ['Database', db.ok ? `Up, ${db.ms} ms` : 'Not answering'],
    ['Updated', when(data.generatedAt)],
  ];
  for (const [label, value] of rows) {
    const row = el('div', 'admin-row');
    row.append(el('span', 'fine', label), el('span', '', value));
    health.append(row);
  }
  body.append(grid, health);
}

function userRow(u, admins) {
  const row = el('button', `admin-user${u.id === selectedId ? ' selected' : ''}`);
  row.type = 'button';
  const name = el('span', 'admin-email', u.email || 'no email');
  const tags = el('span', 'admin-tags');
  if (admins.has(u.id)) tags.append(tag('admin', 'admin'));
  if (u.banned) tags.append(tag('banned', 'banned'));
  if (!u.confirmed) tags.append(tag('unconfirmed'));
  if (u.provider === 'google') tags.append(tag('Google'));
  row.append(name, tags, el('span', 'fine', `Last sign-in ${when(u.lastSignInAt)}`));
  row.addEventListener('click', () => { selectedId = u.id === selectedId ? null : u.id; confirming = false; banError = ''; render(); });
  return row;
}

function userDetail(u, admins) {
  const panel = el('div', 'card admin-panel admin-detail');
  panel.append(el('p', 'setting-title', u.email || 'no email'));
  const rows = [
    ['Status', u.banned ? 'Banned' : u.confirmed ? 'Active' : 'Hasn’t confirmed their email'],
    ['Signs in with', u.provider === 'google' ? 'Google' : 'Email and password'],
    ['Created', when(u.createdAt)],
    ['Last sign-in', when(u.lastSignInAt)],
  ];
  for (const [label, value] of rows) {
    const row = el('div', 'admin-row');
    row.append(el('span', 'fine', label), el('span', '', value));
    panel.append(row);
  }
  if (admins.has(u.id)) {
    panel.append(el('p', 'fine', 'Admin accounts can’t be banned.'));
    return panel;
  }
  if (confirming) {
    const box = el('div', 'admin-confirm');
    box.append(el('p', '', u.banned
      ? `Unban ${u.email}? They can sign in again, and their data is untouched.`
      : `Ban ${u.email}? They're signed out on every device and can't sign in. Their data stays, so you can unban them later.`));
    const actions = el('div', 'admin-confirm-row');
    const cancel = el('button', 'link', 'Cancel');
    cancel.type = 'button';
    cancel.addEventListener('click', () => { confirming = false; render(); });
    const go = el('button', `quiet-action${u.banned ? '' : ' danger'}`, working ? 'Working…' : u.banned ? 'Unban account' : 'Ban account');
    go.type = 'button';
    go.disabled = working;
    go.addEventListener('click', () => setBan(u));
    actions.append(cancel, go);
    box.append(actions);
    panel.append(box);
  } else {
    const button = el('button', `quiet-action${u.banned ? '' : ' danger'}`, u.banned ? 'Unban account' : 'Ban account');
    button.type = 'button';
    button.addEventListener('click', () => { confirming = true; banError = ''; render(); });
    panel.append(button);
  }
  if (banError) panel.append(el('p', 'error', banError));
  return panel;
}

async function setBan(u) {
  working = true;
  banError = '';
  render();
  try {
    await auth.adminSetBan(u.id, !u.banned);
    confirming = false;
    await load();
  } catch (error) {
    banError = error.message || "Couldn't change that account. Try again.";
  } finally {
    working = false;
    render();
  }
}

function renderAccounts(body) {
  const admins = adminIds();
  const search = el('input', 'field-bg admin-search');
  search.placeholder = 'Search by email';
  search.setAttribute('aria-label', 'Search accounts by email');
  search.maxLength = 80;
  search.value = query;
  search.addEventListener('input', () => { query = search.value; drawList(); });
  const layout = el('div', 'admin-accounts');
  const list = el('div', 'card admin-list');
  const side = el('div', 'admin-side');
  function drawList() {
    const q = query.trim().toLowerCase();
    const users = (data.users || []).filter((u) => !q || (u.email || '').toLowerCase().includes(q));
    list.replaceChildren(...(users.length ? users.map((u) => userRow(u, admins)) : [el('p', 'fine', 'No accounts match.')]));
  }
  drawList();
  const selected = (data.users || []).find((u) => u.id === selectedId);
  side.append(selected ? userDetail(selected, admins) : el('p', 'fine', 'Pick an account to see its details.'));
  layout.append(list, side);
  body.append(search, layout);
}

function renderFeedback(body) {
  const items = data.feedback || [];
  if (!items.length) { body.append(el('p', 'fine', 'No feedback yet.')); return; }
  const list = el('div', 'admin-feedback');
  for (const f of items) {
    const card = el('div', 'card admin-panel');
    const head = el('div', 'admin-row');
    head.append(el('span', 'admin-email', f.email), el('span', 'fine', `${f.rating ? '★'.repeat(f.rating) + ' · ' : ''}${f.appVersion ? `v${f.appVersion} · ` : ''}${when(f.createdAt)}`));
    card.append(head, el('p', 'admin-message', f.message || ''));
    list.append(card);
  }
  body.append(list);
}

function renderEvents(body) {
  const emailFor = new Map((data.users || []).map((u) => [u.id, u.email]));
  const events = (data.analytics?.events || []).slice(0, 80);
  const audit = data.audit || [];
  const card = el('div', 'card admin-panel');
  card.append(el('p', 'setting-title', 'Recent sign-ups, sign-ins and data changes'));
  const rows = events.length
    ? events.map((e) => [String(e.kind || '').replace(/_/g, ' '), emailFor.get(e.userId) || '', e.at])
    : audit.map((a) => [`${a.action} ${a.table}`, a.account || '', a.occurredAt]);
  if (!rows.length) card.append(el('p', 'fine', 'Nothing yet.'));
  for (const [what, who, at] of rows) {
    const row = el('div', 'admin-row');
    row.append(el('span', '', who ? `${what} · ${who}` : what), el('span', 'fine', when(at)));
    card.append(row);
  }
  body.append(card);
}

function render() {
  const tabs = $('admin-tabs');
  tabs.replaceChildren(...SECTIONS.map((name) => {
    const pill = el('button', 'pill', name);
    pill.type = 'button';
    pill.setAttribute('role', 'radio');
    pill.setAttribute('aria-checked', String(name === section));
    pill.addEventListener('click', () => { section = name; render(); });
    return pill;
  }));
  const body = $('admin-body');
  body.replaceChildren();
  if (!data) { body.append(el('p', 'fine', loading ? 'Loading…' : '')); return; }
  ({ Overview: renderOverview, Accounts: renderAccounts, Feedback: renderFeedback, Events: renderEvents })[section](body);
}

async function load() {
  loading = true;
  $('admin-error').textContent = '';
  if (!data) render();
  try {
    data = await auth.adminOverview();
  } catch (error) {
    $('admin-error').textContent = error.message || "Couldn't load the overview. Try again.";
  } finally {
    loading = false;
  }
  render();
}

/** Called when the Admin page opens. */
export function showAdmin() {
  render();
  if (!loading) load();
}

/** Forget everything when the account signs out. */
export function resetAdmin() {
  data = null;
  selectedId = null;
  confirming = false;
  query = '';
  section = 'Overview';
}

$('admin-refresh').addEventListener('click', () => { if (!loading) load(); });
