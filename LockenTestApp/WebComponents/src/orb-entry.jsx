import { createRoot } from 'react-dom/client';
import Globe from './components/ui/3d-orb';

const root = createRoot(document.getElementById('root'));
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
let lastProps = {};

// The 3D orb on a transparent background; the app passes the tab's colors via { colors } (JSON array).
function render(props = {}) {
  lastProps = props;
  let colors;
  try { colors = JSON.parse(props.colors || 'null'); } catch { colors = null; }
  root.render(<Globe colors={colors || undefined} still={reducedMotion.matches} />);
}

window.updateProps = render;
render(window.__initialProps);
reducedMotion.addEventListener('change', () => render(lastProps));
