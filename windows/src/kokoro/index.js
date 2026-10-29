// Kokoro, the Mac app's on-device voice, on Windows: the same Kokoro-82M model (ONNX, Apache-2.0) and the same af_heart
// voice, run on this PC. Nothing is sent anywhere to speak. The model (92 MB) is downloaded only when the student asks,
// from a fixed Hugging Face revision, and kept only if its SHA-256 matches; then it lives in this app's cache.
import { loadLexicon, phonemize, tokenize } from './g2p.js';

const REVISION = '1939ad2a8e416c0acfeecc08a694d14ef25f2231';
const MODEL_URL = `https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX/resolve/${REVISION}/onnx/model_quantized.onnx`;
const MODEL_SHA256 = 'fbae9257e1e05ffc727e951ef9b9c98418e6d79f1c9b6b13bd59f5c9028a1478';
const MODEL_BYTES = 92361116;
const CACHE = 'locken-kokoro-v1';
const STYLE = 256;
export const KOKORO_MB = Math.round(MODEL_BYTES / 1_000_000);

let worker = null;
let voice = null; // af_heart: 510 style vectors of 256
let nextId = 0;
const waiting = new Map();

export async function kokoroReady() {
  try { return Boolean(await (await caches.open(CACHE)).match(MODEL_URL)); } catch { return false; }
}

const hex = (buffer) => [...new Uint8Array(buffer)].map((b) => b.toString(16).padStart(2, '0')).join('');

/** Downloads and checks the model; onProgress gets 0 to 1. Throws a message to show. */
export async function downloadKokoro(onProgress) {
  let response;
  try { response = await fetch(MODEL_URL); } catch { throw new Error("Couldn't download the voice. Check your internet connection."); }
  if (!response.ok || !response.body) throw new Error("Couldn't download the voice. Try again later.");
  const data = new Uint8Array(MODEL_BYTES);
  const reader = response.body.getReader();
  let received = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    if (received + value.length > MODEL_BYTES) throw new Error("The voice download wasn't the expected file.");
    data.set(value, received);
    received += value.length;
    onProgress?.(received / MODEL_BYTES);
  }
  if (received !== MODEL_BYTES || hex(await crypto.subtle.digest('SHA-256', data)) !== MODEL_SHA256) {
    throw new Error("The voice download wasn't the expected file, so it wasn't kept.");
  }
  const cache = await caches.open(CACHE);
  await cache.put(MODEL_URL, new Response(data, { headers: { 'Content-Type': 'application/octet-stream' } }));
}

export async function removeKokoro() {
  worker?.terminate();
  worker = null;
  try { await caches.delete(CACHE); } catch { /* nothing saved */ }
}

function startWorker() {
  if (worker) return worker;
  worker = new Worker(new URL('./worker.js', import.meta.url), { type: 'module' });
  worker.onmessage = ({ data }) => {
    const job = waiting.get(data.id);
    if (!job) return;
    waiting.delete(data.id);
    if (data.error) job.reject(new Error(data.error)); else job.resolve(data.audio);
  };
  return worker;
}

/** Splits a reply into sentences short enough for the model (510 tokens). */
function sentences(text) {
  return (String(text).match(/[^.!?…]+[.!?…]*/g) || []).map((s) => s.trim()).filter(Boolean);
}

/** The reply as 24 kHz audio, one Float32Array per sentence, generated in order. */
export async function* kokoroSpeech(text, speed = 1) {
  await loadLexicon();
  if (!voice) {
    const response = await fetch('/kokoro/af_heart.bin');
    if (!response.ok) throw new Error('voice');
    voice = new Float32Array(await response.arrayBuffer());
  }
  startWorker();
  // Every sentence is queued at once (the worker runs them in order), so the next one is ready while one plays.
  const jobs = [];
  for (const sentence of sentences(text)) {
    const ids = tokenize(phonemize(sentence));
    if (!ids.length) continue;
    const row = Math.min(ids.length, 509);
    const style = voice.slice(row * STYLE, (row + 1) * STYLE);
    const id = nextId++;
    jobs.push(new Promise((resolve, reject) => {
      waiting.set(id, { resolve, reject });
      worker.postMessage({ id, cacheName: CACHE, modelUrl: MODEL_URL, ids, style, speed }, [style.buffer]);
    }));
  }
  for (const job of jobs) job.catch(() => {}); // a failure is reported once, by the sentence that awaits it
  for (const job of jobs) yield await job;
}

export const KOKORO_SAMPLE_RATE = 24000;
