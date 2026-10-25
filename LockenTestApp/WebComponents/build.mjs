// Bundles each React Bits component into a self-contained page under ../Resources/Web,
// which the native app loads into a transparent WKWebView. Run with: npm run build
import { build } from 'esbuild';
import { cp, mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const outdir = new URL('../Resources/Web/', import.meta.url);
await mkdir(new URL('fonts/', outdir), { recursive: true });
await cp(new URL('./public/', import.meta.url), outdir, { recursive: true });
// The web view can't see fonts the app registers, so pages that show text load them themselves:
// Doto (round dots, weight 900) for the picker labels and code digits, Montserrat for the profile card, which is
// drawn at about half size where Doto's dots would blur.
await cp(new URL('../Resources/Fonts/Doto.ttf', import.meta.url), new URL('fonts/Doto.ttf', outdir));
for (const weight of ['Regular', 'Medium', 'SemiBold', 'Bold']) {
  await cp(new URL(`../Resources/Fonts/Montserrat-${weight}.ttf`, import.meta.url), new URL(`fonts/Montserrat-${weight}.ttf`, outdir));
}

const fonts = [['Regular', 400], ['Medium', 500], ['SemiBold', 600], ['Bold', 700]]
  .map(([name, weight]) => `@font-face { font-family: 'Montserrat'; src: url('fonts/Montserrat-${name}.ttf'); font-weight: ${weight}; }`)
  .concat(`@font-face { font-family: 'Doto'; src: url('fonts/Doto.ttf'); font-weight: 100 900; }`)
  .join('\n') + `\nbody { font-family: 'Montserrat', sans-serif; }`;
const dotoDigits = `font-family: 'Doto', sans-serif; font-weight: 900; font-variation-settings: 'ROND' 100;`;

// Extra page CSS/JS only fits the component into its native frame; the component sources are otherwise unmodified.
const pages = {
  electric: { css: '', js: '' },
  dither: { css: '', js: '' },
  // Home's 3D orb (three.js). Its starfield fades out toward the frame's edges, so no square shows around it.
  orb: {
    css: `#root { position: relative; -webkit-mask-image: radial-gradient(circle closest-side at 50% 50%, #000 62%, transparent 100%);
  mask-image: radial-gradient(circle closest-side at 50% 50%, #000 62%, transparent 100%); }`,
    js: '',
  },
  // Liquid-glass clock digits for the focus timer: a WebGL canvas, in the app's Montserrat for the digit shapes.
  fluidglass: { css: fonts, js: '' },
  // The Assistant's hero: React Bits Strands (WebGL2 light strands) on a transparent page.
  strands: {
    // The strands live in a 2:1 box, centred: in a wider one the ribbons are cropped by the top and bottom edges. The
    // box's edges fade out, so no rectangle shows.
    css: `#root { display: flex; align-items: center; justify-content: center; }
.strands-stage { height: 100%; max-width: 100%; aspect-ratio: 2 / 1;
  -webkit-mask-image: radial-gradient(ellipse closest-side at 50% 50%, #000 58%, transparent 100%);
  mask-image: radial-gradient(ellipse closest-side at 50% 50%, #000 58%, transparent 100%); }`,
    js: '',
  },
  // The collapsed sidebar: React Bits GlassIcons in one column, with room on both sides for the tilted colour plates and
  // the hover labels (they sit below each button and are wider than it). The open page gets a thin ring.
  glassicons: {
    css: `${fonts}
#root { display: flex; align-items: flex-start; justify-content: center; }
.rail { padding: 18px 26px 42px; box-sizing: border-box; }
.glass-icon-label { font-family: 'Montserrat', sans-serif; font-size: 12px; font-weight: 600; }
.glass-icon.is-selected::after { content: ''; position: absolute; inset: -5px; border-radius: 16px; border: 2px solid rgba(255, 255, 255, 0.85); pointer-events: none; transition: opacity 0.2s; }
.rail.is-closing .glass-icon.is-selected::after { opacity: 0; }`,
    js: '',
  },
  codeslots: {
    css: `${fonts}
.code-slots__digit { ${dotoDigits} }
#root { display: flex; align-items: center; justify-content: center; }`,
    js: '',
  },
  jelly: {
    // Laid out at its natural width (the native frame then hugs the reported size), in the app's typeface.
    css: `${fonts}
/* Picker labels keep Locken's dotted Doto, at full weight and 15px (a size its dots land on whole pixels), so the
   dots are solid and readable rather than thin and faint. */
body { ${dotoDigits} }
.jelly-radio__label { font-weight: 900 !important; font-size: 15px !important; letter-spacing: 0.02em; }
/* Compact pills: shorter and tighter than the component's defaults. */
.jelly-radio { --jr-h: 30px !important; --jr-px: 12px !important; --jr-gap: 6px !important; }
.jelly-radio__label { -webkit-font-smoothing: antialiased; }
#root { display: flex; align-items: flex-start; justify-content: flex-start; }
/* A row wider than its space wraps onto a second line instead of being cut off. */
.jelly-radio { flex: 0 1 auto; flex-wrap: wrap; max-width: 100%; }
.jelly-radio__chip { flex: none; }
/* Each pill is snapped to a whole number of pixels by jelly-entry.jsx, and its label starts at the padding, so the dots of
   the Doto text land on the pixel grid (at fractional positions they blur). The 16px line makes the vertical offset whole. */
.jelly-radio__skin { box-sizing: border-box; width: 100%; justify-content: flex-start; }
.jelly-radio__label { white-space: nowrap; line-height: 16px; }`,
    js: '',
  },
  profile: {
    // The narrow web view would trigger ProfileCard's smallest breakpoints (tiny, overlapping title/subtitle).
    // Instead, lay the card out at its 450px (≤768px breakpoint) design size and scale it uniformly to fit.
    css: `${fonts}
#root { display: flex; align-items: center; justify-content: center; }
.pc-card-wrapper { transform: scale(var(--pc-scale, 1)); transform-origin: center; flex: none; }
.pc-card { height: 450px !important; max-height: none !important; aspect-ratio: 0.94 !important; }
.pc-details { top: 2em !important; }
.pc-details h3 { font-size: 2.5em !important; background-image: linear-gradient(to bottom, #fff, #b4b4bf) !important; }
.pc-details p { font-size: 14px !important; top: -12px !important; }
/* The card renders at ~47% scale in the sidebar, so the bottom banner uses about double the usual sizes. */
.pc-user-info { --ui-inset: 16px !important; padding: 16px 18px !important; }
.pc-mini-avatar { width: 56px !important; height: 56px !important; }
.pc-user-details { gap: 14px !important; }
.pc-user-text { gap: 8px !important; }
.pc-handle { font-size: 26px !important; }
.pc-status { font-size: 19px !important; }
/* No background in the component CSS, so WebKit's light default button fill showed through; keep it a quiet glass chip. */
.pc-contact-btn { width: 80px; height: 80px; padding: 0 !important; place-items: center; border-radius: 20px !important; background: rgba(255, 255, 255, 0.08) !important; }
.pc-contact-btn .pc-settings-icon { width: 42px; height: 42px; border-radius: 0 !important; }
/* Now-playing row in place of the name. \`.pc-card *\` makes every descendant a click-through grid cell, so each part resets that. */
.pc-details { padding: 0 22px; box-sizing: border-box; }
.pc-music {
  display: flex !important; align-items: center; gap: 18px; grid-area: auto !important;
  padding: 14px 16px; border-radius: 24px !important; pointer-events: auto !important;
  background: rgba(255, 255, 255, 0.08); border: 1px solid rgba(255, 255, 255, 0.1);
  -webkit-backdrop-filter: blur(20px); backdrop-filter: blur(20px); text-align: left;
}
.pc-music--action { cursor: pointer; }
.pc-music-cover {
  display: grid !important; place-items: center; flex: none; width: 76px; height: 76px;
  border-radius: 14px !important; overflow: hidden; background: rgba(255, 255, 255, 0.1); color: rgba(255, 255, 255, 0.7);
}
.pc-music-cover img { display: block !important; width: 100%; height: 100%; object-fit: cover; border-radius: 0 !important; }
.pc-music-cover svg { width: 36px; height: 36px; }
.pc-music-title {
  display: block !important; flex: 1; min-width: 0; font-size: 26px; font-weight: 600; color: #fff;
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis; border-radius: 0 !important;
}
.pc-music-btn {
  display: grid !important; place-items: center; flex: none; width: 64px; height: 64px; padding: 0;
  border-radius: 50% !important; border: 1px solid rgba(255, 255, 255, 0.12); background: rgba(255, 255, 255, 0.12);
  color: #fff; cursor: pointer; pointer-events: auto !important;
}
.pc-music-btn svg { width: 30px; height: 30px; border-radius: 0 !important; }
/* A regular photo (not a transparent cut-out portrait) fades into the card instead of sitting as a hard-edged block. */
.pc-avatar-content .avatar {
  -webkit-mask-image: radial-gradient(ellipse 60% 55% at 50% 55%, #000 50%, transparent 100%);
  mask-image: radial-gradient(ellipse 60% 55% at 50% 55%, #000 50%, transparent 100%);
}`,
    js: `(function () {
  const cardHeight = 450, cardWidth = 450 * 0.94, margin = 8;
  function fit() {
    const scale = Math.min((innerWidth - margin) / cardWidth, (innerHeight - margin) / cardHeight);
    document.documentElement.style.setProperty('--pc-scale', scale.toFixed(4));
  }
  addEventListener('resize', fit);
  fit();
})();`,
  },
};

for (const [page, extra] of Object.entries(pages)) {
  await build({
    entryPoints: [`src/${page}-entry.jsx`],
    bundle: true,
    minify: true,
    format: 'iife',
    target: 'safari17',
    jsx: 'automatic',
    loader: { '.jsx': 'jsx', '.tsx': 'tsx', '.jpg': 'dataurl' },
    define: { 'process.env.NODE_ENV': '"production"' },
    outfile: fileURLToPath(new URL(`${page}.js`, outdir)),
  });

  const html = `<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="stylesheet" href="${page}.css">
<style>html, body, #root { margin: 0; width: 100%; height: 100%; background: transparent; overflow: hidden; }
${extra.css}</style>
</head>
<body>
<div id="root"></div>
<script src="${page}.js"></script>
${extra.js ? `<script>${extra.js}</script>` : ''}
<script>addEventListener('load', () => requestAnimationFrame(() => requestAnimationFrame(() => window.webkit?.messageHandlers?.locken?.postMessage('ready'))));</script>
</body>
</html>
`;
  await writeFile(new URL(`${page}.html`, outdir), html);
  console.log(`built ${page}.html`);
}
