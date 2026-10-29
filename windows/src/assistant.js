// The Assistant page (the Mac app's AssistantView and VoiceAssistant). On Windows the student types; replies can be read
// aloud with a Windows voice, or with one of Locken's ElevenLabs voices and the student's own key. Questions go to the
// student's own AI key through Rust (`ai_assistant`), with only the facts Locken already shows them: today's focus
// numbers, the running session and its steps, today's habits and upcoming Canvas assignments. Any action the AI
// suggests waits for the student to confirm it. Conversations are kept on this PC, per account (text only).
import { invoke } from '@tauri-apps/api/core';
import { kokoroReady, downloadKokoro, removeKokoro, kokoroSpeech, KOKORO_MB, KOKORO_SAMPLE_RATE } from './kokoro/index.js';

const $ = (id) => document.getElementById(id);
const CLONE_IDS = ['6i4Eb1eUSagmAhMPqhYS', 'rFtEb2MlDt7EXDbMtvop', 'jQsSjEc5AqgeKVNnZAUe', 'igSE0ESt9o1f4gv4QCL2'];
const WINDOWS_VOICE = 'windows';
/** Kokoro, the Mac's own voice ("Locken"), run on this PC after a one-time download. */
const KOKORO_VOICE = 'kokoro';
const MAX_CHATS = 200;
/** The pages the Assistant can open, by the name the model uses (same names as the Mac). */
const OPENABLE = { home: ['dashboard', 'Home'], focus: ['focus', 'Focus'], assistant: ['assistant', 'Assistant'], habits: ['habits', 'Habit Tracker'], analytics: ['analytics', 'Analytics'], notes: ['notes', 'Notes'], settings: ['settings', 'Settings'] };

let api = null; // set by initAssistant (the main window's own functions)
let chat = null; // { id, started, title, messages: [{ role: 'student' | 'assistant', text }] }
let thinking = false;
let proposal = null; // { label, run }
let voices = []; // [{ id, name }] Locken's voices this key can use
let hasVoiceKey = false;
let audio = null;
let speakingToken = 0;
let search = '';
let kokoro = 'missing'; // 'missing' | 'downloading' | 'ready'
let kokoroProgress = 0;
let kokoroError = '';
let audioContext = null;
let kokoroSource = null;

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

// ---------- Saved conversations ----------
const historyKey = () => `locken.assistant.history.${api.userId()}`;
function loadChats() { try { const list = JSON.parse(localStorage.getItem(historyKey()) || '[]'); return Array.isArray(list) ? list : []; } catch { return []; } }
function saveChats(list) { try { localStorage.setItem(historyKey(), JSON.stringify(list.slice(0, MAX_CHATS))); } catch { /* kept this run */ } }
function storeChat() {
  if (!chat || !chat.messages.length) return;
  const list = loadChats().filter((c) => c.id !== chat.id);
  list.unshift(chat);
  saveChats(list);
}

function dayLabel(ms) {
  const day = new Date(ms); day.setHours(0, 0, 0, 0);
  const today = new Date(); today.setHours(0, 0, 0, 0);
  const diff = Math.round((today - day) / 86_400_000);
  if (diff === 0) return 'Today';
  if (diff === 1) return 'Yesterday';
  return day.toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' });
}

function renderChats() {
  const q = search.trim().toLowerCase();
  const list = loadChats().filter((c) => !q || c.title.toLowerCase().includes(q) || c.messages.some((m) => m.text.toLowerCase().includes(q)));
  const nodes = [];
  let lastDay = '';
  for (const c of list) {
    const label = dayLabel(c.started);
    if (label !== lastDay) { nodes.push(el('p', 'mini-label assistant-day', label.toUpperCase())); lastDay = label; }
    const row = el('div', `assistant-chat${chat?.id === c.id ? ' selected' : ''}`);
    const open = el('button', 'assistant-chat-open');
    open.type = 'button';
    open.append(el('span', 'assistant-chat-title', c.title), el('span', 'fine', new Date(c.started).toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' })));
    open.addEventListener('click', () => { stopSpeaking(); chat = structuredClone(c); proposal = null; render(); });
    const remove = el('button', 'step-remove', '×');
    remove.type = 'button';
    remove.title = 'Delete this conversation';
    remove.setAttribute('aria-label', `Delete ${c.title}`);
    remove.addEventListener('click', () => {
      saveChats(loadChats().filter((x) => x.id !== c.id));
      if (chat?.id === c.id) newChat();
      render();
    });
    row.append(open, remove);
    nodes.push(row);
  }
  $('assistant-chats').replaceChildren(...nodes);
  $('assistant-chats-empty').hidden = nodes.length > 0;
  $('assistant-chats-empty').textContent = q ? 'No conversations match.' : 'Your conversations show up here, kept on this PC.';
  $('assistant-clear').hidden = !loadChats().length;
}

function newChat() {
  stopSpeaking();
  chat = null;
  proposal = null;
  $('assistant-error').textContent = '';
}

// ---------- The conversation ----------
function renderLog() {
  const log = $('assistant-log');
  const messages = chat?.messages || [];
  if (!messages.length && !thinking) {
    log.replaceChildren(el('p', 'fine assistant-hint', 'Try “What should I work on first?”, “Start a 25-minute session on my essay” or “How did I do today?”'));
  } else {
    log.replaceChildren(...messages.map((m) => el('p', `assistant-msg ${m.role}`, m.text)));
    if (thinking) log.append(el('p', 'assistant-msg assistant thinking', 'Thinking…'));
  }
  log.scrollTop = log.scrollHeight;
  $('assistant-proposal').hidden = !proposal;
  if (proposal) $('assistant-proposal-text').textContent = proposal.label;
}

function availability() {
  if (!api.aiAdult()) return 'The Assistant uses AI, which is for people 18 and older.';
  if (!api.aiEnabled()) return 'Turn on AI features in Settings to use the Assistant.';
  if (!api.aiProvider()) return 'Add a Claude, ChatGPT or Gemini API key in Settings to use the Assistant.';
  return '';
}

function render() {
  const off = availability();
  $('assistant-off').hidden = !off;
  $('assistant-off-text').textContent = off;
  $('assistant-input').disabled = Boolean(off) || thinking;
  $('assistant-send').disabled = Boolean(off) || thinking || !$('assistant-input').value.trim();
  renderLog();
  renderChats();
  renderVoiceLabel();
  setStrands();
}

function setStrands() {
  const props = audio || kokoroSource || speechSynthesis.speaking ? { speaking: '1' } : thinking ? { level: '0.4' } : {};
  try { $('strands').contentWindow?.updateProps?.(props); } catch { /* not loaded yet */ }
}

/** The facts the AI may use, numbered so it can point at a step, habit or assignment. */
function facts() {
  const lines = [];
  const stats = api.todayStats();
  lines.push(`Today: ${stats.minutes} focus minutes in ${stats.sessions} sessions; ${stats.blocked} distractions blocked.`);
  lines.push(`Last 7 days: ${api.weekMinutes()} focus minutes.`);
  const s = api.session();
  if (s) {
    const left = Math.max(0, Math.round((s.paused ? s.remaining : s.endsAt - Date.now()) / 60_000));
    lines.push(`Focus session ${s.paused ? 'paused' : 'running'}: "${s.goal}", ${s.minutes} minutes planned, about ${left} left.`);
    (s.milestones || []).forEach((m, i) => lines.push(`Step ${i + 1}: ${m.text}${m.done ? ' (done)' : ''}`));
  } else {
    lines.push('No focus session is running.');
  }
  const habits = api.habitsToday();
  if (habits.length) habits.forEach((h, i) => lines.push(`Habit ${i + 1}: ${h.name}${h.done ? ' (done today)' : ''}${h.streak ? `, ${h.streak}-day streak` : ''}`));
  else lines.push('No habits are due today.');
  const assignments = api.assignments().slice(0, 12);
  if (assignments.length) assignments.forEach((a, i) => lines.push(`Canvas assignment ${i + 1}: ${a.title}${a.course ? ` (${a.course})` : ''}${a.due ? `, due ${a.due}` : ''}`));
  else lines.push(api.canvasLinked() ? 'No upcoming Canvas assignments.' : 'Canvas isn’t linked.');
  return lines.join('\n');
}

/** The JSON object in the reply ({"say": ..., "action": ...}); plain text if the model didn't send JSON. */
function parseReply(raw) {
  const start = raw.indexOf('{');
  const end = raw.lastIndexOf('}');
  if (start >= 0 && end > start) {
    try {
      const json = JSON.parse(raw.slice(start, end + 1));
      if (typeof json.say === 'string') return { say: json.say.trim(), action: json.action && typeof json.action === 'object' ? json.action : null };
    } catch { /* fall through */ }
  }
  return { say: raw.trim(), action: null };
}

const clampMinutes = (m) => Math.min(180, Math.max(5, Math.round(Number(m) || 25)));
const numbered = (list, n) => (Number.isInteger(n) && n >= 1 && n <= list.length ? list[n - 1] : null);

/** Turns a suggested action into something the student can confirm, or null if it doesn't fit what's on screen. */
function toProposal(action) {
  const s = api.session();
  switch (action?.type) {
    case 'start_session': {
      const goal = String(action.goal || '').trim().slice(0, 200);
      if (!goal || s) return null;
      const minutes = clampMinutes(action.minutes);
      return { label: `Start a ${minutes}-minute focus session: ${goal}`, run: () => api.startSession(goal, minutes) };
    }
    case 'complete_step': {
      const step = numbered(s?.milestones || [], action.number);
      if (!step || step.done) return null;
      return { label: `Tick off the step “${step.text}”`, run: () => api.completeStep(step) };
    }
    case 'check_off_assignment': {
      const a = numbered(api.assignments().slice(0, 12), action.number);
      if (!a) return null;
      return { label: `Mark “${a.title}” done in Locken (nothing is sent to Canvas)`, run: () => api.checkOffAssignment(a.id) };
    }
    case 'complete_habit': {
      const h = numbered(api.habitsToday(), action.number);
      if (!h || h.done) return null;
      return { label: `Tick off today's habit “${h.name}”`, run: () => api.completeHabit(h.id) };
    }
    case 'add_note': {
      const title = String(action.title || '').trim().slice(0, 120);
      const body = String(action.body || '').trim().slice(0, 20000);
      if (!title && !body) return null;
      return { label: `Save a note${title ? `: ${title}` : ''}`, run: () => api.addNote(title, body) };
    }
    case 'open_page': {
      const page = OPENABLE[String(action.page || '').toLowerCase()];
      if (!page) return null;
      return { label: `Open ${page[1]}`, run: () => api.showPage(page[0]) };
    }
    case 'pause_session':
      if (!s || s.paused) return null;
      return { label: 'Pause your focus session', run: () => api.pauseSession() };
    case 'resume_session':
      if (!s || !s.paused) return null;
      return { label: 'Resume your focus session', run: () => api.resumeSession() };
    default:
      return null;
  }
}

async function send(text) {
  if (thinking || availability()) return;
  stopSpeaking();
  if (!chat) chat = { id: crypto.randomUUID(), started: Date.now(), title: text.slice(0, 60), messages: [] };
  const history = chat.messages.map((m) => ({ role: m.role, text: m.text }));
  chat.messages.push({ role: 'student', text });
  storeChat();
  proposal = null;
  thinking = true;
  $('assistant-error').textContent = '';
  $('assistant-input').value = '';
  render();
  try {
    const now = new Date().toLocaleString(undefined, { weekday: 'long', month: 'long', day: 'numeric', hour: 'numeric', minute: '2-digit' });
    const raw = await invoke('ai_assistant', { account: api.userId(), now, facts: facts(), history, message: text });
    const reply = parseReply(String(raw));
    const say = reply.say || 'Sorry, I didn’t catch that. Try again?';
    chat.messages.push({ role: 'assistant', text: say });
    storeChat();
    proposal = toProposal(reply.action);
    thinking = false;
    render();
    speak(say);
  } catch (error) {
    thinking = false;
    $('assistant-error').textContent = typeof error === 'string' ? error : 'Couldn’t reach the AI service. Try again.';
    render();
  }
  $('assistant-input').focus();
}

// ---------- Reading replies aloud ----------
const speakKey = () => `locken.assistant.speak.${api.userId()}`;
const voiceKey = () => `locken.assistant.voice.${api.userId()}`;
function speakOn() { try { return localStorage.getItem(speakKey()) !== '0'; } catch { return true; } }
function chosenVoice() {
  let id = WINDOWS_VOICE;
  try { id = localStorage.getItem(voiceKey()) || WINDOWS_VOICE; } catch { /* default */ }
  if (id === KOKORO_VOICE) return kokoro === 'ready' ? KOKORO_VOICE : WINDOWS_VOICE;
  return id !== WINDOWS_VOICE && hasVoiceKey && CLONE_IDS.includes(id) ? id : WINDOWS_VOICE;
}

function renderVoiceLabel() {
  $('assistant-speak').checked = speakOn();
  const id = chosenVoice();
  const name = id === WINDOWS_VOICE ? 'a Windows voice' : id === KOKORO_VOICE ? 'Locken\u2019s voice, on this PC' : (voices.find((v) => v.id === id)?.name || 'your ElevenLabs voice');
  $('assistant-voice-label').textContent = speakOn() ? `With ${name}. Change it in Settings.` : 'Off: replies are only shown.';
  $('assistant-stop').hidden = !(audio || kokoroSource || speechSynthesis.speaking);
}

function stopSpeaking() {
  speakingToken += 1;
  if (audio) { audio.pause(); audio = null; }
  if (kokoroSource) { try { kokoroSource.stop(); } catch { /* already ended */ } kokoroSource = null; }
  speechSynthesis.cancel();
  if (api) { renderVoiceLabel(); setStrands(); }
}

function speakLocally(text, token) {
  if (token !== speakingToken) return;
  const utterance = new SpeechSynthesisUtterance(text);
  utterance.rate = 1.05;
  utterance.onend = utterance.onerror = () => { renderVoiceLabel(); setStrands(); };
  speechSynthesis.speak(utterance);
  renderVoiceLabel();
  setStrands();
}

async function speak(text) {
  if (!speakOn() || !text) return;
  const token = ++speakingToken;
  const id = chosenVoice();
  if (id === WINDOWS_VOICE) { speakLocally(text, token); return; }
  if (id === KOKORO_VOICE) { speakKokoro(text, token); return; }
  try {
    const mp3 = await invoke('voice_speech', { account: api.userId(), voiceId: id, text });
    if (token !== speakingToken) return;
    audio = new Audio(`data:audio/mpeg;base64,${mp3}`);
    audio.onended = audio.onerror = () => { audio = null; renderVoiceLabel(); setStrands(); };
    await audio.play();
    renderVoiceLabel();
    setStrands();
  } catch {
    // ElevenLabs unreachable or out of characters: read it with the Windows voice instead.
    audio = null;
    speakLocally(text, token);
  }
}

/** Plays Kokoro's sentences one after another as they're ready; falls back to the Windows voice if it fails. */
async function speakKokoro(text, token) {
  try {
    audioContext ??= new AudioContext();
    if (audioContext.state === 'suspended') await audioContext.resume();
    for await (const samples of kokoroSpeech(text)) {
      if (token !== speakingToken) return;
      const buffer = audioContext.createBuffer(1, samples.length, KOKORO_SAMPLE_RATE);
      buffer.copyToChannel(samples, 0);
      await new Promise((resolve) => {
        const source = audioContext.createBufferSource();
        source.buffer = buffer;
        source.connect(audioContext.destination);
        source.onended = resolve;
        kokoroSource = source;
        source.start();
        renderVoiceLabel();
        setStrands();
      });
      kokoroSource = null;
    }
  } catch {
    kokoroSource = null;
    if (token === speakingToken) speakLocally(text, token);
    return;
  }
  renderVoiceLabel();
  setStrands();
}

// ---------- Settings: Assistant voice ----------
function renderVoiceCard() {
  $('voice-card').hidden = !api.aiAdult();
  const current = chosenVoice();
  const options = [{ id: WINDOWS_VOICE, name: 'Windows voice' }, { id: KOKORO_VOICE, name: kokoro === 'ready' ? 'Locken (on this PC)' : kokoro === 'downloading' ? `Locken: downloading ${Math.round(kokoroProgress * 100)}%` : `Locken: download ${KOKORO_MB} MB` }, ...(hasVoiceKey ? voices : [])];
  $('voice-tiles').replaceChildren(...options.map((v) => {
    const tile = el('button', 'voice-tile', v.name || 'Locken voice');
    tile.type = 'button';
    tile.setAttribute('role', 'radio');
    tile.setAttribute('aria-checked', String(v.id === current));
    if (v.id === KOKORO_VOICE && kokoro === 'downloading') tile.disabled = true;
    tile.addEventListener('click', async () => {
      if (v.id === KOKORO_VOICE && kokoro !== 'ready') { await getKokoro(); if (kokoro !== 'ready') return; }
      try { localStorage.setItem(voiceKey(), v.id); } catch { /* this run only */ }
      renderVoiceCard();
      renderVoiceLabel();
      speak(v.id === WINDOWS_VOICE ? 'This is the Windows voice.' : v.id === KOKORO_VOICE ? "Hi, I'm Locken. Let's get to work." : `Hi, I'm ${v.name || 'Locken'}. Let's get to work.`);
    });
    return tile;
  }));
  $('voice-key-saved').hidden = !hasVoiceKey;
  $('voice-key-form').hidden = hasVoiceKey;
  $('kokoro-remove').hidden = kokoro !== 'ready';
  $('kokoro-error').textContent = kokoroError;
}

/** Downloads Kokoro once, when the student picks it. */
async function getKokoro() {
  if (kokoro !== 'missing') return;
  kokoro = 'downloading';
  kokoroProgress = 0;
  kokoroError = '';
  renderVoiceCard();
  let shown = 0;
  try {
    await downloadKokoro((fraction) => {
      kokoroProgress = fraction;
      if (fraction - shown >= 0.01) { shown = fraction; renderVoiceCard(); }
    });
    kokoro = 'ready';
  } catch (error) {
    kokoro = 'missing';
    kokoroError = error.message || "Couldn't download the voice. Try again.";
  }
  renderVoiceCard();
  renderVoiceLabel();
}

async function refreshVoices() {
  if (!api.userId()) return;
  if (kokoro !== 'downloading') kokoro = (await kokoroReady()) ? 'ready' : 'missing';
  hasVoiceKey = await invoke('voice_key_status', { account: api.userId() }).catch(() => false);
  voices = hasVoiceKey ? await invoke('voice_list', { account: api.userId() }).catch(() => []) : [];
  renderVoiceCard();
  renderVoiceLabel();
}

/** Called once with the main window's own functions. */
export function initAssistant(functions) {
  api = functions;
  $('assistant-form').addEventListener('submit', (event) => {
    event.preventDefault();
    const text = $('assistant-input').value.trim().slice(0, 1000);
    if (text) send(text);
  });
  $('assistant-input').addEventListener('input', () => { $('assistant-send').disabled = thinking || Boolean(availability()) || !$('assistant-input').value.trim(); });
  $('assistant-new').addEventListener('click', () => { newChat(); render(); $('assistant-input').focus(); });
  $('assistant-search').addEventListener('input', () => { search = $('assistant-search').value; renderChats(); });
  $('assistant-clear').addEventListener('click', () => {
    if ($('assistant-clear').dataset.sure !== '1') { $('assistant-clear').dataset.sure = '1'; $('assistant-clear').textContent = 'Delete every conversation?'; return; }
    delete $('assistant-clear').dataset.sure;
    $('assistant-clear').textContent = 'Delete all';
    saveChats([]);
    newChat();
    render();
  });
  $('assistant-settings').addEventListener('click', () => api.showPage('settings'));
  $('assistant-confirm').addEventListener('click', async () => {
    const chosen = proposal;
    proposal = null;
    renderLog();
    if (!chosen) return;
    try { await chosen.run(); } catch { $('assistant-error').textContent = 'Couldn’t do that. Try it in the app.'; }
  });
  $('assistant-dismiss').addEventListener('click', () => { proposal = null; renderLog(); });
  $('assistant-speak').addEventListener('change', () => {
    try { localStorage.setItem(speakKey(), $('assistant-speak').checked ? '1' : '0'); } catch { /* this run only */ }
    if (!$('assistant-speak').checked) stopSpeaking();
    renderVoiceLabel();
  });
  $('assistant-stop').addEventListener('click', stopSpeaking);
  $('voice-key').addEventListener('input', () => { $('voice-key-save').disabled = !$('voice-key').value.trim(); $('voice-key-error').textContent = ''; });
  $('voice-key-form').addEventListener('submit', async (event) => {
    event.preventDefault();
    const key = $('voice-key').value.trim();
    if (!key) return;
    $('voice-key-save').disabled = true;
    $('voice-key-error').textContent = '';
    try {
      voices = await invoke('voice_save_key', { account: api.userId(), key });
      hasVoiceKey = true;
      $('voice-key').value = '';
      try { if (voices[0] && chosenVoice() === WINDOWS_VOICE) localStorage.setItem(voiceKey(), voices[0].id); } catch { /* this run only */ }
    } catch (error) {
      $('voice-key-error').textContent = typeof error === 'string' ? error : 'Couldn’t save the key. Try again.';
    }
    $('voice-key-save').disabled = !$('voice-key').value.trim();
    renderVoiceCard();
    renderVoiceLabel();
  });
  $('voice-key-remove').addEventListener('click', async () => {
    await invoke('voice_remove_key', { account: api.userId() }).catch(() => {});
    hasVoiceKey = false;
    voices = [];
    stopSpeaking();
    renderVoiceCard();
    renderVoiceLabel();
  });
  $('strands').addEventListener('load', setStrands);
  $('kokoro-remove').addEventListener('click', async () => {
    stopSpeaking();
    await removeKokoro();
    kokoro = 'missing';
    renderVoiceCard();
    renderVoiceLabel();
  });
}

/** The Assistant page opened. */
export function showAssistant() { render(); $('assistant-input').focus(); }
/** Settings opened, or the account or its AI key changed. */
export function refreshAssistantSettings() { refreshVoices(); if (!$('page-assistant').hidden) render(); }
/** The account signed out or was deleted: stop talking and forget what's on screen (saved chats stay with the account). */
export function resetAssistant() { stopSpeaking(); chat = null; proposal = null; thinking = false; voices = []; hasVoiceKey = false; search = ''; }
/** Delete Account: remove this account's ElevenLabs key and saved conversations from this PC. */
export async function eraseAssistantData(userId) {
  await invoke('voice_remove_key', { account: userId }).catch(() => {});
  for (const key of [`locken.assistant.history.${userId}`, `locken.assistant.speak.${userId}`, `locken.assistant.voice.${userId}`]) {
    try { localStorage.removeItem(key); } catch { /* nothing saved */ }
  }
}
