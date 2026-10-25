import { createRoot } from 'react-dom/client';
import Strands from './Strands';

// The Assistant's hero: React Bits Strands as light strands on the app's own background (no glass orb), in the Assistant
// tab's coral (#FB7158) with a pink second sheet and a white-hot core. The 7 colours are in the component's order: warm
// sheet tip, edge, body, core, then the cooler sheet's light, mid and deep. { colors } (a JSON array) can replace them.
// The component's pointer lean and click pulse are off: Locken's design rules allow no cursor tilt or click ripples. With
// Reduce Motion on, the component holds still.
const COLORS = ['#d6213f', '#f0503a', '#ff8a5c', '#fff3ec', '#ff6f9c', '#b0306a', '#4a1236'];
const root = createRoot(document.getElementById('root'));
const query = new URLSearchParams(location.search);
// While tuning in a browser, the URL can override the numbers (?amplitude=1&spread=1&intensity=0.8 ...).
const tune = {};
for (const [key, value] of query) if (key !== 'colors' && !Number.isNaN(parseFloat(value))) tune[key] = parseFloat(value);

// The app sets the state through props: { speaking: '1' } while Locken talks (the component's own speech-like motion),
// { level: '0.4' } for anything with a loudness (the microphone while it listens, a steady lift while it thinks), and
// nothing while idle, which leaves the strands calm at the base energy.
function render(props = {}) {
  const level = parseFloat(props.level);
  let colors;
  try { colors = JSON.parse(props.colors || query.get('colors') || 'null'); } catch { colors = null; }
  root.render(
    <div className="strands-stage">
      <Strands
        glass={false}
        colors={Array.isArray(colors) && colors.length ? colors : COLORS}
        speed={1.6}
        amplitude={1}
        waviness={1.4}
        energy={0.3}
        level={Number.isFinite(level) ? level : undefined}
        listening={props.speaking === '1'}
        spread={1}
        intensity={0.9}
        scale={1}
        interactive={false}
        clickPulse={false}
        {...tune}
      />
    </div>
  );
}

window.updateProps = render;
render(window.__initialProps);
