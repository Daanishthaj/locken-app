import { createRoot } from 'react-dom/client';
import ElectricLogo from './ElectricLogo';

const root = createRoot(document.getElementById('root'));

// The native app supplies { src } (the selected workspace app's icon) via window.__initialProps and window.updateProps(props).
function render(props = {}) {
  root.render(
    <div style={{ width: '100%', height: '100%', position: 'relative' }}>
      {/* Tuned for a 44pt inline icon: smaller mark, fewer/thinner strands, and a dimmer glow that fades out before the edges. */}
      <ElectricLogo
        src={props.src}
        // The page's own palette (the app passes the current tab's accent); rose for the Dashboard by default.
        color={props.color || '#ffd1d6'}
        glowColor={props.glowColor || '#e11d48'}
        scale={0.55}
        intensity={0.6}
        glow={0.35}
        thickness={1.0}
        strands={2}
        bend={0.6}
        crackle={1.0}
        arcs={0}
        speed={2.5}
        cursorRadius={30}
        interactive
      />
    </div>
  );
}

window.updateProps = render;
render(window.__initialProps);
