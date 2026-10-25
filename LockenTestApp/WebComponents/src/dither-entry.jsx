import { createRoot } from 'react-dom/client';
import DitherVeil from './DitherVeil';
// Bundled into the page (Unsplash photo, downloaded once) so showing it never contacts another server.
import heroImage from './assets/dither-hero.jpg';

const root = createRoot(document.getElementById('root'));

// The native app can tint the light dots per tab via { paperColor } (window.__initialProps / window.updateProps).
function render(props = {}) {
  root.render(
    <div style={{ width: '100%', height: '100%', position: 'relative' }}>
      <DitherVeil
        src={heroImage}
        pattern="floyd"
        pixelSize={2}
        inkColor="#120f17"
        paperColor={props.paperColor || '#f4f1ea'}
        revealRadius={200}
        softness={0.6}
        linger={1}
      />
    </div>
  );
}

window.updateProps = render;
render(window.__initialProps);

// The native view sits behind a scroll view, so real mouse events never reach it; the app forwards the pointer here.
window.__lockenPointer = (x, y, inside) => {
  const target = document.querySelector('.dither-veil');
  if (!target) return;
  target.dispatchEvent(
    new PointerEvent(inside ? 'pointermove' : 'pointerleave', { clientX: x, clientY: y, pointerType: 'mouse' })
  );
};
