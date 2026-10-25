import { createRoot } from 'react-dom/client';
import PlasmaRing from './originkit/ui/plasma-ring';

const root = createRoot(document.getElementById('root'));
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
let lastProps = {};

// OriginKit PlasmaRing on a transparent background; the app passes the tab's colors via { colors } (JSON array).
function render(props = {}) {
  lastProps = props;
  let colors;
  try { colors = JSON.parse(props.colors || 'null'); } catch { colors = null; }
  root.render(
    <PlasmaRing
      background="transparent"
      colors={colors || ['#8B5CF6', '#C4B5FD', '#E9D5FF']}
      // No corner glows or black box: the ring floats on the app's own background.
      style={{ minWidth: 0, minHeight: 0, background: 'transparent' }}
      // Thinner lattice and a dimmer center, so additive blending doesn't blow out to white.
      density={60}
      centerOpacity={25}
      // Camera closer than the default 36, so the ring fills most of the dashboard stage.
      scale={70}
      // Reduce Motion: the ring holds still instead of rippling.
      speed={reducedMotion.matches ? 0 : 100}
    />
  );
}

window.updateProps = render;
render(window.__initialProps);
reducedMotion.addEventListener('change', () => render(lastProps));
