// The Mac app's BorderGlow (React Bits) on Locken's buttons: as the pointer nears a button's edge, a cone of light in the
// current tab's colour lights the border around the pointer's angle and a soft halo fades in. Light only, no movement
// (Locken's hover rule), so it needs no Reduce Motion path. Same numbers as the Mac: edge sensitivity 30, cone 25°.
const SELECTOR = '.primary, .btn, .quiet-action';
const EDGE_SENSITIVITY = 30;
let current = null;

function clear() {
  if (current) current.style.setProperty('--glow', '0');
  current = null;
}

export function mountButtonGlow() {
  document.addEventListener('pointermove', (event) => {
    const button = event.target instanceof Element ? event.target.closest(SELECTOR) : null;
    if (button !== current) clear();
    if (!button || button.disabled) return;
    current = button;
    const rect = button.getBoundingClientRect();
    const dx = event.clientX - (rect.left + rect.width / 2);
    const dy = event.clientY - (rect.top + rect.height / 2);
    // 0 at the centre, 100 at the edge (the original's edge proximity).
    const proximity = Math.min(1, Math.max(Math.abs(dx) / (rect.width / 2 || 1), Math.abs(dy) / (rect.height / 2 || 1))) * 100;
    const strength = Math.min(1, Math.max(0, (proximity - EDGE_SENSITIVITY) / (100 - EDGE_SENSITIVITY)));
    button.style.setProperty('--glow-angle', `${(Math.atan2(dy, dx) * 180) / Math.PI + 90}deg`);
    button.style.setProperty('--glow', strength.toFixed(3));
  }, { passive: true });
  document.addEventListener('pointerleave', clear);
  window.addEventListener('blur', clear);
}
