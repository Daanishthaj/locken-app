// The $0.00 receipt welcome, ported from the Mac app's ReceiptIntroView (same steps and timings). Plays after every
// sign-in: the view pans down to a printer, which prints Locken's receipt a line at a time; the receipt tears off,
// the printer slides up out of frame, and the receipt falls the whole window, tipping flat while its edges curl up
// and it drifts side to side, as the app fades in behind it. A click or any key skips it. Reduce Motion shows the
// printed receipt briefly instead.

const W = 250;                 // paper width and height, as on the Mac
const H = 330;
const INK = '#381e5c';
const VIOLET = '#8c33e6';
const MAGENTA = '#e02673';
const FEED = [0.09, 0.19, 0.30, 0.42, 0.55, 0.68, 0.80, 0.90, 0.97, 1];
const LINES = [['Focus sessions', '$0.00'], ['Canvas sync', '$0.00'], ['The Shield', '$0.00'], ['Check-ins', '$0.00'], ['Updates', '$0.00']];

/** Draws the receipt (same layout as the Mac's) onto a canvas, for the printer slot and the falling copy. */
function drawReceipt(scale) {
  const canvas = document.createElement('canvas');
  canvas.width = W * scale;
  canvas.height = H * scale;
  const c = canvas.getContext('2d');
  c.scale(scale, scale);
  // Torn bottom edge: zig-zag teeth.
  c.beginPath();
  c.moveTo(0, 0); c.lineTo(W, 0); c.lineTo(W, H - 5);
  const teeth = 24; const step = W / (teeth * 2);
  for (let i = 1; i <= teeth * 2; i++) c.lineTo(W - i * step, i % 2 ? H : H - 5);
  c.closePath();
  const paper = c.createLinearGradient(0, 0, 0, H);
  paper.addColorStop(0, '#f5f0ff'); paper.addColorStop(1, '#e6def7');
  c.fillStyle = paper;
  c.fill();
  c.save();
  c.clip();
  const doto = (weight, size) => `${weight} ${size}px Doto, monospace`;
  const sans = (weight, size) => `${weight} ${size}px Montserrat, sans-serif`;
  let y = 22 + 18;
  const title = c.createLinearGradient(W / 2 - 40, 0, W / 2 + 40, 0);
  title.addColorStop(0, VIOLET); title.addColorStop(1, MAGENTA);
  c.fillStyle = title; c.font = doto(900, 20); c.textAlign = 'center';
  c.fillText('LOCKEN', W / 2, y);
  y += 20; c.fillStyle = INK; c.globalAlpha = 0.7; c.font = sans(400, 11);
  c.fillText('Focus app for students', W / 2, y);
  c.globalAlpha = 1;
  const rule = (at) => { c.save(); c.globalAlpha = 0.4; c.strokeStyle = INK; c.setLineDash([3, 3]); c.beginPath(); c.moveTo(20, at); c.lineTo(W - 20, at); c.stroke(); c.restore(); };
  y += 14; rule(y);
  c.font = sans(400, 12); c.fillStyle = INK;
  for (const [label, price] of LINES) {
    y += 22;
    c.textAlign = 'left'; c.fillText(label, 20, y);
    c.textAlign = 'right'; c.fillText(price, W - 20, y);
  }
  y += 14; rule(y);
  y += 24; c.font = sans(700, 14); c.fillStyle = VIOLET;
  c.textAlign = 'left'; c.fillText('TOTAL', 20, y);
  c.textAlign = 'right'; c.fillText('$0.00', W - 20, y);
  y += 26; c.fillStyle = INK; c.font = sans(700, 11); c.textAlign = 'center';
  c.fillText('NOTHING TO PAY · NO CARD NEEDED', W / 2, y);
  y += 20; c.globalAlpha = 0.7; c.font = sans(400, 11);
  c.fillText('Thanks for focusing.', W / 2, y);
  c.restore();
  return canvas;
}

/** Distance fallen (0…1) at time t: falling with air drag, starting from rest (same curve as the Mac). */
const drop = (t) => Math.log(Math.cosh(t / 0.32)) / Math.log(Math.cosh(1 / 0.32));

export function playReceiptIntro() {
  return new Promise((resolve) => {
    const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    const root = document.createElement('div');
    root.className = 'receipt-intro';
    root.innerHTML = `
      <div class="ri-backdrop"></div>
      <div class="ri-scene">
        <div class="ri-printer">
          <div class="ri-status"><span class="ri-dot"></span><span class="ri-status-text">Printing your receipt</span></div>
          <div class="ri-slot"></div>
        </div>
        <div class="ri-paper"><canvas class="ri-receipt"></canvas></div>
      </div>
      <canvas class="ri-fall"></canvas>`;
    document.body.append(root);
    const ratio = Math.max(2, window.devicePixelRatio || 1);
    const receiptImage = drawReceipt(ratio);
    const slot = root.querySelector('.ri-receipt');
    slot.width = receiptImage.width; slot.height = receiptImage.height;
    slot.style.width = `${W}px`; slot.style.height = `${H}px`;
    slot.getContext('2d').drawImage(receiptImage, 0, 0);
    const paper = root.querySelector('.ri-paper');

    let done = false;
    const timers = [];
    let frame = null;
    const at = (ms, fn) => timers.push(setTimeout(fn, ms));
    const finish = () => {
      if (done) return;
      done = true;
      timers.forEach(clearTimeout);
      cancelAnimationFrame(frame);
      root.classList.add('ri-leaving');
      setTimeout(() => { root.remove(); resolve(); }, 300);
    };
    root.addEventListener('click', finish);
    window.addEventListener('keydown', finish, { once: true });

    const setFeed = (f) => { paper.style.setProperty('--feed', String(f)); };
    if (reduce) {
      root.classList.add('ri-panned');
      setFeed(1);
      root.querySelector('.ri-status-text').textContent = "All set. It's on us.";
      at(1600, () => root.classList.add('ri-fade'));
      at(2100, finish);
      return;
    }

    // Pan down from the sign-in screen to the printer.
    setFeed(0);
    requestAnimationFrame(() => root.classList.add('ri-panned'));
    let t = 1250;
    // Stepped feed: each step advances the paper, then pauses a beat, like a line being printed.
    FEED.forEach((step) => { at(t, () => setFeed(step)); t += 175; });
    at(t, () => {
      root.querySelector('.ri-status-text').textContent = "All set. It's on us.";
      root.classList.add('ri-printed');
    });
    t += 800;
    at(t, () => {
      // Tear off: the printer slides up and out, the receipt falls the whole way down.
      const rect = paper.getBoundingClientRect();
      root.classList.add('ri-falling');
      const fall = root.querySelector('.ri-fall');
      const width = window.innerWidth;
      const height = window.innerHeight;
      fall.width = width * ratio; fall.height = height * ratio;
      const c = fall.getContext('2d');
      const start = performance.now();
      const startX = rect.left;
      const startY = rect.top;
      const endY = height + 40;
      const tick = (now) => {
        const p = Math.min(1, (now - start) / 2800);
        const tilt = Math.min(1, p / 0.6);
        const curl = Math.max(0, Math.min(1, (p - 0.25) / 0.6));
        const easeIn = Math.min(1, p / 0.25);
        const sway = Math.sin(p * Math.PI * 2.2) * easeIn;
        const y = startY + drop(p) * (endY - startY);
        const x = startX + sway * 46;
        const angle = (sway * 9 * (1 - p * 0.5) + p * easeIn * 6) * Math.PI / 180;
        c.setTransform(ratio, 0, 0, ratio, 0, 0);
        c.clearRect(0, 0, width, height);
        c.save();
        c.translate(x + W / 2, y + H / 2);
        c.rotate(angle);
        c.shadowColor = `rgba(0,0,0,${0.3 * easeIn * (1 - tilt * 0.5)})`;
        c.shadowBlur = 14 + 10 * tilt;
        c.shadowOffsetY = 10 + 16 * tilt;
        const strips = 40;
        const flatten = 1 - 0.62 * tilt * tilt;
        const stripW = W / strips;
        for (let i = 0; i < strips; i++) {
          const u = ((i + 0.5) / strips) * 2 - 1;
          const lift = curl * u * u * 34;
          const squeeze = 1 - curl * u * u * 0.12;
          const drawnH = H * flatten * squeeze;
          const top = -H / 2 + (H - drawnH) * tilt * 0.5 - lift;
          c.drawImage(receiptImage, (i * stripW) * ratio, 0, stripW * ratio, H * ratio, -W / 2 + i * stripW, top, stripW + 0.6, drawnH);
          const shade = 0.1 * curl * (1 - u * u) - 0.08 * curl * u * u;
          if (shade !== 0) {
            c.shadowColor = 'transparent';
            c.fillStyle = shade > 0 ? `rgba(0,0,0,${shade})` : `rgba(255,255,255,${-shade})`;
            c.fillRect(-W / 2 + i * stripW, top, stripW + 0.6, drawnH);
          }
        }
        c.restore();
        if (p < 1) frame = requestAnimationFrame(tick);
      };
      frame = requestAnimationFrame(tick);
      at(700, () => root.classList.add('ri-fade'));
    });
    t += 2850;
    at(t, finish);
  });
}

export const receiptCss = `
.receipt-intro { position: fixed; inset: 0; z-index: 90; overflow: hidden; transition: opacity 0.3s ease; }
.receipt-intro.ri-leaving { opacity: 0; }
.ri-backdrop { position: absolute; inset: 0; background: linear-gradient(180deg, #0f0a17, #08080b); transition: opacity 1.8s cubic-bezier(0.42, 0, 0.58, 1); }
.receipt-intro.ri-fade .ri-backdrop, .receipt-intro.ri-fade .ri-scene { opacity: 0; }
.ri-scene { position: absolute; inset: 0; display: flex; flex-direction: column; align-items: center; justify-content: center; padding-bottom: ${Math.round(H * 0.35)}px;
  background: radial-gradient(${Math.round(H * 1.3)}px circle at 50% 50%, rgba(140, 51, 230, 0.22), transparent 70%);
  transform: translateY(100vh); transition: transform 1s cubic-bezier(0.77, 0, 0.175, 1), opacity 1.8s ease; }
.receipt-intro.ri-panned .ri-scene { transform: none; }
.ri-printer { position: relative; z-index: 2; width: ${W + 70}px; display: flex; flex-direction: column; gap: 10px; border-radius: 24px;
  background: linear-gradient(180deg, #261c3b, #140f1f); border: 1px solid rgba(140, 51, 230, 0.4);
  box-shadow: 0 14px 30px rgba(140, 51, 230, 0.35); transition: transform 0.9s cubic-bezier(0.77, 0, 0.175, 1); }
.receipt-intro.ri-falling .ri-printer { transform: translateY(-100vh); }
.ri-status { display: flex; align-items: center; gap: 8px; padding: 14px 16px 0; font: 500 12px Montserrat, sans-serif; color: rgba(255, 255, 255, 0.75); }
.ri-dot { width: 10px; height: 10px; border-radius: 50%; border: 2px solid rgba(255, 255, 255, 0.7); border-top-color: transparent; animation: ri-spin 0.8s linear infinite; }
.receipt-intro.ri-printed .ri-dot { animation: none; border-color: #8b5cf6; background: #8b5cf6; }
@keyframes ri-spin { to { transform: rotate(360deg); } }
.ri-slot { align-self: center; width: ${W + 22}px; height: 8px; margin-bottom: 12px; border-radius: 4px; background: #000; border: 1px solid rgba(140, 51, 230, 0.35); box-shadow: 0 0 6px rgba(140, 51, 230, 0.5); }
.ri-paper { position: relative; z-index: 1; width: ${W}px; height: ${H}px; margin-top: -4px; overflow: hidden; }
.ri-receipt { display: block; transform: translateY(calc((1 - var(--feed, 0)) * -${H}px)); transition: transform 0.13s linear; }
.receipt-intro.ri-falling .ri-paper { opacity: 0; }
.ri-fall { position: absolute; inset: 0; width: 100%; height: 100%; pointer-events: none; }
@media (prefers-reduced-motion: reduce) { .receipt-intro * { transition-duration: 0.2s !important; } }
`;
