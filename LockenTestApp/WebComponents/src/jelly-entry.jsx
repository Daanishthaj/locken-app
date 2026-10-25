import { createRoot } from 'react-dom/client';
import JellyRadio from './JellyRadio';

const root = createRoot(document.getElementById('root'));
const post = message => window.webkit?.messageHandlers?.locken?.postMessage(message);

// The native app owns the selection: it supplies { items (JSON array), value, label } via window.__initialProps /
// window.updateProps(props), and hears picks as "change:<value>".
function render(props = {}) {
  root.render(
    <JellyRadio
      items={JSON.parse(props.items || '[]')}
      value={props.value}
      onChange={value => post(`change:${value}`)}
      ariaLabel={props.label || 'Options'}
      chipColor="#27272a"
      // The app passes a very light tint of the current tab's accent (e.g. lavender on violet tabs).
      activeColor={props.activeColor || '#f5f5f5'}
      textColor="#f5f5f5"
      activeTextColor="#18181b"
      size="md"
      gap={8}
      radius={18}
      // Every pill rests at its true size (no lasting swell or shrink), so its text sits on whole pixels and stays
      // sharp; the jelly wobble still plays when the choice changes.
      swell={0}
      barge={0}
      shrink={0}
      jelly={1}
      bounce={0.25}
      stagger={22}
      stiffness={580}
    />
  );
}

window.updateProps = render;
render(window.__initialProps);

// Snap every pill to a whole number of pixels (so each pill and its dotted label sit on the pixel grid, where Doto's
// dots stay sharp), then report the group's size so the native frame can hug it. The width reported is the natural,
// single-row width: the native side never makes the frame wider than that, and when the space is narrower the pills
// wrap onto more rows and the height reported grows to match.
// The labels' own size changes when the Doto font arrives (or the text changes), and that changes the pill widths too.
const labelObserver = new ResizeObserver(() => requestAnimationFrame(snapAndReport));

function snapAndReport() {
  const group = document.querySelector('.jelly-radio');
  if (!group) return;
  group.querySelectorAll('.jelly-radio__label').forEach(label => labelObserver.observe(label));
  const chips = [...group.querySelectorAll('.jelly-radio__chip')];
  chips.forEach(chip => { chip.style.width = ''; });
  const widths = chips.map(chip => Math.ceil(parseFloat(getComputedStyle(chip).width)));
  chips.forEach((chip, i) => { chip.style.width = `${widths[i]}px`; });
  const style = getComputedStyle(group);
  const natural = widths.reduce((sum, w) => sum + w, 0)
    + (parseFloat(style.columnGap) || 0) * Math.max(chips.length - 1, 0)
    + (parseFloat(style.paddingLeft) || 0) * 2;
  post(`size:${Math.ceil(natural)}x${Math.ceil(group.getBoundingClientRect().height)}`);
}

const sizeObserver = new ResizeObserver(snapAndReport);
requestAnimationFrame(function attach() {
  const group = document.querySelector('.jelly-radio');
  if (!group) return requestAnimationFrame(attach);
  sizeObserver.observe(group);
  // New labels (another list of choices) and the Doto font arriving both change the pills' natural widths.
  new MutationObserver(() => requestAnimationFrame(snapAndReport))
    .observe(document.getElementById('root'), { childList: true, subtree: true, characterData: true });
  document.fonts?.ready.then(snapAndReport);
  document.fonts?.addEventListener('loadingdone', snapAndReport);
  snapAndReport();
});
