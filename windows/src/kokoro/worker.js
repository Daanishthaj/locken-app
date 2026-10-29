// Runs the Kokoro model off the main thread, so the window stays smooth while a reply is turned into speech. It reads the
// model from the Cache API (saved and checked by index.js); onnxruntime's WebAssembly file is bundled with the app.
import * as ort from 'onnxruntime-web/wasm';

ort.env.wasm.numThreads = 1; // no SharedArrayBuffer in the app's web view
let session = null;

async function open(cacheName, modelUrl) {
  if (session) return session;
  const cache = await caches.open(cacheName);
  const response = await cache.match(modelUrl);
  if (!response) throw new Error('missing');
  session = await ort.InferenceSession.create(new Uint8Array(await response.arrayBuffer()), { executionProviders: ['wasm'] });
  return session;
}

// One request at a time, in the order they came: a session can't run two at once.
let queue = Promise.resolve();
self.onmessage = ({ data }) => { queue = queue.then(() => generate(data)); };

async function generate(data) {
  const { id, cacheName, modelUrl, ids, style, speed } = data;
  try {
    const s = await open(cacheName, modelUrl);
    const padded = BigInt64Array.from([0, ...ids, 0].map(BigInt));
    const output = await s.run({
      input_ids: new ort.Tensor('int64', padded, [1, padded.length]),
      style: new ort.Tensor('float32', style, [1, style.length]),
      speed: new ort.Tensor('float32', Float32Array.of(speed), [1]),
    });
    const audio = output[s.outputNames[0]].data;
    self.postMessage({ id, audio }, [audio.buffer]);
  } catch (error) {
    self.postMessage({ id, error: String(error?.message || error) });
  }
}
