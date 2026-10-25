import { createRoot } from 'react-dom/client';
import CodeSlots from './CodeSlots';

const root = createRoot(document.getElementById('root'));
const post = message => window.webkit?.messageHandlers?.locken?.postMessage(message);

// The app verifies the code with the server and sends back { status: idle | success | error }.
// Typing reports "change", a full code reports "complete:<code>", and the size is reported so the frame can hug it.
function render(props = {}) {
  root.render(
    <CodeSlots
      key={props.resetKey || '0'}
      length={6}
      status={props.status || 'idle'}
      onChange={() => post('change')}
      onComplete={code => post(`complete:${code}`)}
      accentColor={props.accentColor || '#f5f5f5'}
      inkColor="#f5f5f5"
      slotColor="#27272a"
      digitColor="#18181b"
      dangerColor="#ff3b30"
      slotSize={44}
      gap={8}
      radius={12}
      bounce={0.2}
      settle={0.3}
      rise={8}
      cascade={20}
    />
  );
}

window.updateProps = render;
render(window.__initialProps);
