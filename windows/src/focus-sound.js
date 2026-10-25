// The sound when focus mode switches on, like AirPods' noise cancellation turning on (the Mac's `FocusSound`): a soft swell of air
// rising from 350 Hz to 3.5 kHz into two rising chime notes (E5, then A5) with a short echo tail. Made with Web Audio, so there is
// no audio file. About 1.4 s and quiet; it follows the PC's volume and mute.
let context = null;
let noise = null;

const audioContext = () => {
  if (!context) {
    const Context = window.AudioContext || window.webkitAudioContext;
    if (!Context) return null;
    context = new Context();
  }
  return context;
};

/** Builds the sound into `ctx` starting at `start` seconds, at `level` (0.35 peaks near 0.3), ending in a short fade. */
export function buildFocusSound(ctx, start, destination, level = 0.35) {
  const master = ctx.createGain();
  master.gain.setValueAtTime(level, start);
  master.gain.setValueAtTime(level, start + 1.2);
  master.gain.linearRampToValueAtTime(0, start + 1.4);
  master.connect(destination);

  // A short tail: three quiet echoes of everything.
  const bus = ctx.createGain();
  bus.connect(master);
  for (const [delay, level] of [[0.11, 0.30], [0.19, 0.18], [0.29, 0.10]]) {
    const echo = ctx.createDelay(1);
    echo.delayTime.value = delay;
    const gain = ctx.createGain();
    gain.gain.value = level;
    bus.connect(echo).connect(gain).connect(master);
  }

  // The air: noise through a band-pass filter that rises while it swells and fades.
  if (!noise || noise.sampleRate !== ctx.sampleRate) {
    noise = ctx.createBuffer(1, Math.ceil(ctx.sampleRate), ctx.sampleRate);
    const data = noise.getChannelData(0);
    for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;
  }
  const air = ctx.createBufferSource();
  air.buffer = noise;
  air.loop = true;
  const filter = ctx.createBiquadFilter();
  filter.type = 'bandpass';
  filter.Q.value = 1.4;
  filter.frequency.setValueAtTime(350, start);
  filter.frequency.exponentialRampToValueAtTime(3500, start + 0.6);
  const swell = ctx.createGain();
  swell.gain.setValueAtTime(0.0001, start);
  swell.gain.linearRampToValueAtTime(0.9, start + 0.45);
  swell.gain.linearRampToValueAtTime(0.9, start + 0.55);
  swell.gain.linearRampToValueAtTime(0, start + 0.9);
  air.connect(filter).connect(swell).connect(bus);
  air.start(start);
  air.stop(start + 0.95);

  // The two notes: a sine with a soft second and third harmonic, a quick attack and a long, smooth decay.
  for (const [at, frequency, level] of [[0.18, 659.26, 0.34], [0.34, 880, 0.30]]) {
    const note = ctx.createGain();
    note.gain.setValueAtTime(0, start + at);
    note.gain.linearRampToValueAtTime(level, start + at + 0.008);
    note.gain.setTargetAtTime(0, start + at + 0.008, 0.3);
    note.connect(bus);
    for (const [multiple, share] of [[1, 1], [2, 0.22], [3, 0.07]]) {
      const oscillator = ctx.createOscillator();
      oscillator.frequency.value = frequency * multiple;
      const gain = ctx.createGain();
      gain.gain.value = share;
      oscillator.connect(gain).connect(note);
      oscillator.start(start + at);
      oscillator.stop(start + at + 1.2);
    }
  }
}

/** Called from a click once, so the browser allows sound later. */
export function unlockFocusSound() {
  const ctx = audioContext();
  if (ctx && ctx.state === 'suspended') ctx.resume().catch(() => {});
}

export function playFocusSound() {
  try {
    const ctx = audioContext();
    if (!ctx) return;
    if (ctx.state === 'suspended') ctx.resume().catch(() => {});
    buildFocusSound(ctx, ctx.currentTime + 0.02, ctx.destination);
  } catch { /* no sound this time */ }
}
