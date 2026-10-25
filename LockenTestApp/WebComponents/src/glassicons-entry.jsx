import { createRoot } from 'react-dom/client';
import { HugeiconsIcon } from '@hugeicons/react';
import {
  AddCircleIcon, AiVoiceIcon, Calendar03Icon, ChartHistogramIcon, FireIcon, FlashIcon, Note01Icon, SecurityLockIcon, Settings01Icon,
} from '@hugeicons/core-free-icons';
import GlassIcons from './GlassIcons';

// The collapsed sidebar: one React Bits GlassIcons button per page, in a single column. The native app owns what is
// shown and picked: it supplies { items (JSON array of { id, label, icon }), value (the open page), size, gap } via
// window.__initialProps / window.updateProps(props) (closing: '1' plays the tiles' intro backwards), and hears a press as "select:<id>". The colours come from the page itself (by id). The page reports its size as
// "size:<w>x<h>" so the native frame can hug it. The settings are the ones chosen for Locken (plate tilt, press on hover,
// labels on hover, dark theme).
const ICONS = {
  new: AddCircleIcon, focus: FlashIcon, assistant: AiVoiceIcon, calendar: Calendar03Icon, habits: FireIcon,
  analytics: ChartHistogramIcon, notes: Note01Icon, settings: Settings01Icon, admin: SecurityLockIcon,
};
// One muted, dark palette for the whole rail (the same saturation and lightness on every button, so it sits quietly on the
// dark app and the white symbols stay easy to read), told apart by hue alone: the hues are spread round the wheel, a little over 30 degrees apart, and keep to each page's
// own accent where that leaves them distinct. Notes leans magenta (its plum is too close to Focus's violet) and Admin is
// indigo. Settings is the one neutral: a cool slate.
const HUES = { new: 345, assistant: 14, habits: 42, calendar: 158, analytics: 200, admin: 238, focus: 268, notes: 308 };
const tone = id => (id === 'settings'
  ? 'linear-gradient(135deg, hsl(215, 14%, 40%), hsl(215, 16%, 22%))'
  : HUES[id] === undefined ? null : `linear-gradient(135deg, hsl(${HUES[id]}, 50%, 40%), hsl(${HUES[id]}, 58%, 22%))`);
const root = createRoot(document.getElementById('root'));
const post = message => window.webkit?.messageHandlers?.locken?.postMessage(message);

function render(props = {}) {
  let list = [];
  try { list = JSON.parse(props.items || '[]'); } catch { /* none yet */ }
  const items = list.map(item => ({
    id: item.id,
    label: item.label,
    color: tone(item.id) ?? item.color,
    // The open page's button: ringed, with its colour plate straight behind the glass.
    className: item.id === props.value ? 'is-selected' : '',
    aligned: item.id === props.value,
    icon: <HugeiconsIcon icon={ICONS[item.icon] || ICONS.new} />,
    onClick: () => post(`select:${item.id}`),
  }));
  root.render(
    <div className={`rail${props.closing === '1' ? ' is-closing' : ''}`}>
      <GlassIcons
        items={items}
        size={Number(props.size) || 40}
        gap={Number(props.gap) || 30}
        columns={1}
        roundness={0.6}
        refraction={0.8}
        bevel={0.6}
        dispersion={0}
        frost={0.2}
        shine={0.5}
        tint="#08080c"
        tintOpacity={0.4}
        iconColor="#ffffff"
        plate="tilt"
        tilt={30}
        spread={0.5}
        hover="press"
        parallax={1}
        labels="hover"
        intro={true}
        closing={props.closing === '1'}
        theme="dark"
      />
    </div>
  );
}

window.updateProps = render;
render(window.__initialProps);

const report = () => {
  const rail = document.querySelector('.rail');
  if (rail) post(`size:${Math.ceil(rail.offsetWidth)}x${Math.ceil(rail.offsetHeight)}`);
};
new ResizeObserver(report).observe(document.getElementById('root'));
const attach = () => {
  const rail = document.querySelector('.rail');
  if (!rail) return requestAnimationFrame(attach);
  new ResizeObserver(report).observe(rail);
  report();
};
requestAnimationFrame(attach);
