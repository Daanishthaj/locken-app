// The glow window has no logic of its own: it fades in once painted, and fades out when the check-in tells it the answer
// is in (the window itself is closed along with the check-in).
import { listen } from '@tauri-apps/api/event';

requestAnimationFrame(() => requestAnimationFrame(() => document.body.classList.add('on')));
listen('aurora-out', () => document.body.classList.add('out')).catch(() => {});
