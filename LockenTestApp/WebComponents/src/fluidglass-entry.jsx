// Liquid-glass clock digits for Locken's focus timer (Mac). The drawing code is shared with the Windows app and lives in
// shared/fluidglass-time.js; this page only hosts it in the native web view and passes props through.
//
// Props from the app: { text: "24:59", accent: "#8B5CF6" }, updated each second through window.updateProps.
import { createFluidGlassTime } from '../../../shared/fluidglass-time.js';

const query = new URLSearchParams(location.search);
const root = document.getElementById('root');
if (query.get('bg')) document.body.style.background = query.get('bg');

// The URL can override the glass's tuning values while the look is being tuned in a browser (feed, kill, inject, ...).
const tune = {};
for (const [key, value] of query) if (!Number.isNaN(parseFloat(value)) && !['text', 'accent', 'bg', 'v'].includes(key)) tune[key] = parseFloat(value);

const props = { text: '25:00', accent: '#8B5CF6', ...(window.__initialProps || {}) };
if (query.get('text')) props.text = query.get('text');
if (query.get('accent')) props.accent = query.get('accent');

const glass = createFluidGlassTime(root, { ...props, tune });
window.updateProps = (next = {}) => glass.update(next);
