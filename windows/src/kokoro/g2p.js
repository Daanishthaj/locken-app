// English text to Kokoro phonemes, from word lists only: the Mac app's misaki lexicons (us_gold, us_silver; Apache-2.0)
// with misaki's -s, -ed and -ing rules, numbers as words, and letter-by-letter spelling for unknown names and acronyms.
// No eSpeak (GPL), so a rare word the lists don't have is spelled out or skipped instead of guessed.

let golds = null;
let silvers = null;
let vocab = null;

const US_TAUS = new Set('AIOWYiuæɑəɛɪɹʊʌ');
const SYMBOLS = { '%': 'percent', '&': 'and', '+': 'plus', '@': 'at' };
/** Words the lists don't have but Locken says often. */
const CUSTOM = { locken: 'lˈɑkən' };
const PUNCT = new Set([';', ':', ',', '.', '!', '?', '—', '…']);
const ONES = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve',
  'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen'];
const TENS = ['', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety'];

/** Adds the capitalized form of lowercase words and the lowercase form of capitalized ones (misaki's grow_dictionary). */
function grow(dict) {
  const extra = {};
  for (const [k, v] of Object.entries(dict)) {
    if (k.length < 2) continue;
    const cap = k[0].toUpperCase() + k.slice(1).toLowerCase();
    if (k === k.toLowerCase()) { if (k !== cap) extra[cap] = v; }
    else if (k === cap) extra[k.toLowerCase()] = v;
  }
  return Object.assign(extra, dict);
}

export async function loadLexicon(base = '/kokoro/') {
  if (golds) return;
  const [g, s, v] = await Promise.all(['us_gold.json', 'us_silver.json', 'vocab_index.json'].map((f) => fetch(base + f).then((r) => {
    if (!r.ok) throw new Error('lexicon');
    return r.json();
  })));
  golds = grow(g);
  silvers = grow(s);
  vocab = v.vocab;
}

const pick = (value) => (value && typeof value === 'object' ? value.DEFAULT ?? null : value ?? null);

function lookup(word) {
  let w = word;
  if (w === w.toUpperCase() && golds[w] === undefined) w = w.toLowerCase();
  const ps = pick(golds[w]) ?? pick(silvers[w]);
  return typeof ps === 'string' ? ps : null;
}

const isKnown = (w) => golds[w] !== undefined || silvers[w] !== undefined || (w.length === 1 && /[A-Za-z]/.test(w));

function pluralizeS(stem) {
  if (!stem) return null;
  const last = stem.at(-1);
  if ('ptkfθ'.includes(last)) return `${stem}s`;
  if ('szʃʒʧʤ'.includes(last)) return `${stem}ᵻz`;
  return `${stem}z`;
}
function pastEd(stem) {
  if (!stem) return null;
  if ('pkfθʃsʧ'.includes(stem.at(-1))) return `${stem}t`;
  if (stem.endsWith('d')) return `${stem}ᵻd`;
  if (!stem.endsWith('t')) return `${stem}d`;
  if (stem.length >= 2 && US_TAUS.has(stem.at(-2))) return `${stem.slice(0, -1)}ɾᵻd`;
  return `${stem}ᵻd`;
}
function progIng(stem) {
  if (!stem) return null;
  if (stem.length > 1 && stem.endsWith('t') && US_TAUS.has(stem.at(-2))) return `${stem.slice(0, -1)}ɾɪŋ`;
  return `${stem}ɪŋ`;
}

function stemmed(word) {
  const w = word.toLowerCase();
  if (w.length >= 3 && w.endsWith('s')) {
    let stem = null;
    if (!w.endsWith('ss') && isKnown(w.slice(0, -1))) stem = w.slice(0, -1);
    else if ((w.endsWith("'s") || (w.length > 4 && w.endsWith('es') && !w.endsWith('ies'))) && isKnown(w.slice(0, -2))) stem = w.slice(0, -2);
    else if (w.length > 4 && w.endsWith('ies') && isKnown(`${w.slice(0, -3)}y`)) stem = `${w.slice(0, -3)}y`;
    if (stem) return pluralizeS(lookup(stem));
  }
  if (w.length >= 4 && w.endsWith('d')) {
    let stem = null;
    if (!w.endsWith('dd') && isKnown(w.slice(0, -1))) stem = w.slice(0, -1);
    else if (w.length > 4 && w.endsWith('ed') && !w.endsWith('eed') && isKnown(w.slice(0, -2))) stem = w.slice(0, -2);
    if (stem) return pastEd(lookup(stem));
  }
  if (w.length >= 5 && w.endsWith('ing')) {
    let stem = null;
    if (w.length > 5 && isKnown(w.slice(0, -3))) stem = w.slice(0, -3);
    else if (isKnown(`${w.slice(0, -3)}e`)) stem = `${w.slice(0, -3)}e`;
    else if (w.length > 5 && /([bcdgklmnprstvxz])\1ing$|cking$/.test(w) && isKnown(w.slice(0, -4))) stem = w.slice(0, -4);
    if (stem) return progIng(lookup(stem));
  }
  return null;
}

/** Spells a word letter by letter (misaki's get_NNP), with the main stress on the last letter. */
function spell(word) {
  const pieces = [...word].filter((c) => /[A-Za-z]/.test(c)).map((c) => pick(golds[c.toUpperCase()]));
  if (!pieces.length || pieces.some((p) => typeof p !== 'string')) return null;
  const joined = pieces.join('').replace(/ˈ/g, 'ˌ');
  const i = joined.lastIndexOf('ˌ');
  return i < 0 ? joined : `${joined.slice(0, i)}ˈ${joined.slice(i + 1)}`;
}

function wordPhonemes(word) {
  return CUSTOM[word.toLowerCase()] ?? lookup(word) ?? stemmed(word) ?? spell(word);
}

/** Whole numbers as English words (up to the billions); other digits are read one by one. */
export function numberWords(text) {
  const n = Number(text);
  if (!Number.isSafeInteger(n) || n < 0 || n >= 1e12) return [...text].map((d) => ONES[Number(d)] ?? '').join(' ');
  if (n < 20) return ONES[n];
  if (n < 100) return TENS[Math.floor(n / 10)] + (n % 10 ? ` ${ONES[n % 10]}` : '');
  if (n < 1000) return `${ONES[Math.floor(n / 100)]} hundred${n % 100 ? ` ${numberWords(String(n % 100))}` : ''}`;
  for (const [size, name] of [[1e9, 'billion'], [1e6, 'million'], [1e3, 'thousand']]) {
    if (n >= size) return `${numberWords(String(Math.floor(n / size)))} ${name}${n % size ? ` ${numberWords(String(n % size))}` : ''}`;
  }
  return String(n);
}

/** Phonemes for one sentence or paragraph, keeping only characters Kokoro's vocabulary has. */
export function phonemize(text) {
  const clean = String(text).replace(/[’‘]/g, "'").replace(/[“”]/g, '"').replace(/\s+/g, ' ');
  const tokens = clean.match(/[A-Za-z]+(?:'[A-Za-z]+)*|\d+(?:[.,]\d+)?|[^\sA-Za-z\d]/g) || [];
  const out = [];
  for (const token of tokens) {
    let ps = null;
    if (/^\d/.test(token)) {
      const [whole, frac] = token.replace(/,(?=\d{3}\b)/g, '').split(/[.,]/);
      const words = numberWords(whole) + (frac ? ` point ${[...frac].map((d) => ONES[Number(d)]).join(' ')}` : '');
      ps = words.split(' ').map(wordPhonemes).filter(Boolean).join(' ');
    } else if (/^[A-Za-z]/.test(token)) {
      ps = wordPhonemes(token);
    } else if (SYMBOLS[token]) {
      ps = wordPhonemes(SYMBOLS[token]);
    } else if (PUNCT.has(token)) {
      if (out.length) out[out.length - 1] += token;
      continue;
    }
    if (ps) out.push(ps);
  }
  return [...out.join(' ')].filter((c) => vocab[c] !== undefined).join('');
}

/** Kokoro token IDs for phonemes, at most 510 (the model's limit). */
export function tokenize(phonemes) {
  return [...phonemes].map((c) => vocab[c]).filter((id) => id !== undefined).slice(0, 510);
}
