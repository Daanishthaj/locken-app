// React Bits' GradualBlur, for the page scroller: a band along the bottom where what scrolls under it blurs more and
// more toward the edge, with a dark tint on top. It fades away on its own when there's nothing more to scroll to
// (the original's `autoHide`). The Mac app has the same band (DesignSystem/GradualBlur.swift).
//
// The layer math is the original's: each layer's blur radius is the difference of two squares, so the layers add up to
// the exponential curve, and each layer is masked to its own slice of the band.

const CURVES = {
  linear: (t) => t,
  bezier: (t) => t * t * (3 - 2 * t),
  'ease-in': (t) => t * t,
  'ease-out': (t) => 1 - (1 - t) * (1 - t),
  'ease-in-out': (t) => (t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2),
};
const clamp01 = (value) => Math.min(Math.max(value, 0), 1);

export function mountGradualBlur(scroller, { height = 96, strength = 2, layers = 8, curve = 'linear', exponential = true, tint = 'rgba(18, 15, 23, 0.6)', zIndex = 5 } = {}) {
  const root = document.createElement('div');
  root.className = 'gradual-blur';
  root.setAttribute('aria-hidden', 'true');
  Object.assign(root.style, { position: 'fixed', zIndex: String(zIndex), height: `${height}px`, pointerEvents: 'none' });

  const count = Math.min(Math.max(Math.round(layers) || 1, 1), 16);
  const shape = CURVES[curve] || CURVES.linear;
  const maxBlur = Math.max(strength, 0) * 12;
  const level = (u) => maxBlur * (exponential ? (Math.pow(2, 4 * shape(clamp01(u))) - 1) / 15 : shape(clamp01(u)));
  const frosted = !matchMedia('(prefers-reduced-transparency: reduce)').matches; // then only the dark fade shows

  if (frosted) {
    for (let i = 0; i < count; i++) {
      const from = level(i / count);
      const to = level((i + 1) / count);
      const radius = Math.sqrt(Math.max(to * to - from * from, 0));
      const filter = `blur(calc(${radius.toFixed(3)}px * var(--gradual-blur-reveal, 1)))`;
      const mask = `linear-gradient(to bottom, transparent ${((i / count) * 100).toFixed(2)}%, #000 ${(((i + 1) / count) * 100).toFixed(2)}%)`;
      const layer = document.createElement('div');
      Object.assign(layer.style, { position: 'absolute', inset: '0', backdropFilter: filter, webkitBackdropFilter: filter, maskImage: mask, webkitMaskImage: mask });
      root.append(layer);
    }
  }
  const stops = Array.from({ length: 9 }, (_, k) => {
    const t = shape(k / 8);
    return `rgba(0, 0, 0, ${(t * t * t * (t * (t * 6 - 15) + 10)).toFixed(3)}) ${((k / 8) * 100).toFixed(1)}%`;
  }).join(', ');
  const wash = document.createElement('div');
  Object.assign(wash.style, {
    position: 'absolute', inset: '0', background: tint, opacity: 'var(--gradual-blur-reveal, 1)',
    maskImage: `linear-gradient(to bottom, ${stops})`, webkitMaskImage: `linear-gradient(to bottom, ${stops})`,
  });
  root.append(wash);

  // Fixed to the window, over the scroller's own box (it isn't inside the scroller, so it doesn't scroll with it).
  const place = () => {
    const box = scroller.getBoundingClientRect();
    root.style.left = `${box.left}px`;
    root.style.width = `${scroller.clientWidth}px`;
    root.style.bottom = `${Math.max(0, innerHeight - box.bottom)}px`;
  };
  const update = () => {
    place();
    const room = scroller.scrollHeight - scroller.clientHeight - scroller.scrollTop;
    root.style.setProperty('--gradual-blur-reveal', clamp01(room / Math.max(height, 1)).toFixed(3));
  };

  scroller.parentElement.append(root);
  scroller.addEventListener('scroll', update, { passive: true });
  addEventListener('resize', update);
  // Content height changes when a page's content changes (the pages are the scroller's children) and when another page is
  // shown (their `hidden` flags), so only those are watched, not every text change inside a page.
  const observer = new ResizeObserver(update);
  observer.observe(scroller);
  for (const page of scroller.children) observer.observe(page);
  new MutationObserver(update).observe(scroller, { attributes: true, attributeFilter: ['hidden'], subtree: true });
  update();
  return root;
}
