// The check-in window (same question as the Mac app): how far into the goal the student is, as a percentage.
// It asks the main window for the session's goal and time left, and sends the answer back; nothing else.
import { emitTo, listen } from '@tauri-apps/api/event';
import { getCurrentWindow } from '@tauri-apps/api/window';

const slider = document.getElementById('checkin-progress');
const value = document.getElementById('checkin-value');
const preview = document.getElementById('checkin-preview');
let state = null;

/** Same formula as the Mac app (TestAppStateManager.adaptedRemaining). */
function adaptedRemaining(elapsed, planned, progress) {
  if (elapsed <= 0) return null;
  if (progress >= 100) return 0;
  if (progress <= 0) return null;
  const needed = (elapsed * (100 - progress)) / progress;
  const longestTotal = Math.min(planned * 2, 180 * 60);
  const upper = Math.max(longestTotal - elapsed, 5 * 60);
  return Math.round(Math.min(Math.max(needed, 5 * 60), upper) / 60) * 60;
}

function render() {
  const progress = Number(slider.value);
  value.textContent = `${progress}%`;
  if (!state?.adaptive) { preview.hidden = true; return; }
  const remaining = adaptedRemaining(state.elapsed, state.planned, progress);
  preview.hidden = false;
  preview.textContent = remaining === null ? 'Adaptive time: move the slider to adjust the time left.'
    : remaining === 0 ? 'Adaptive time: checking in at 100% ends the session.'
      : `Adaptive time: ${remaining / 60} min left after this check-in.`;
}

listen('checkin-state', (event) => {
  state = event.payload || {};
  document.getElementById('checkin-goal').textContent = state.goal ? `Goal: ${String(state.goal).slice(0, 200)}` : '';
  const left = Math.max(0, Number(state.secondsLeft) || 0);
  document.getElementById('checkin-left').textContent = `${Math.floor(left / 60)}:${String(left % 60).padStart(2, '0')} left`;
  slider.value = String(Math.min(100, Math.max(0, Number(state.lastProgress) || 0)));
  render();
});
slider.addEventListener('input', render);
slider.focus();
emitTo('main', 'checkin-ready', {});

document.getElementById('checkin-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  await emitTo('main', 'checkin-answer', { progress: Number(slider.value) });
  // Let the glow behind the check-in fade out first (it closes with this window either way).
  await emitTo('checkin-aurora', 'aurora-out', {}).catch(() => {});
  await new Promise((resolve) => setTimeout(resolve, 350));
  await getCurrentWindow().close();
});
