import { createRoot } from 'react-dom/client';
import ProfileCard from './ProfileCard';

const root = createRoot(document.getElementById('root'));
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
let lastProps = {};
const send = message => window.webkit?.messageHandlers?.locken?.postMessage(message);

const PlayIcon = () => (
  <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8 5.5v13l11-6.5z" fill="currentColor" /></svg>
);
const PauseIcon = () => (
  <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 5h3.5v14H7zM13.5 5H17v14h-3.5z" fill="currentColor" /></svg>
);
const NoteIcon = () => (
  <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9 17.5a2.5 2.5 0 1 1-2-2.45V5l11-2v10.5a2.5 2.5 0 1 1-2-2.45V6.4L9 7.7z" fill="currentColor" /></svg>
);

// Now playing from Spotify / Music, in place of the card's name: cover, song title, play/pause.
// musicState is "track", "consent" (needs Automation permission), "denied" or "idle".
function MusicHeader({ state, title, cover, playing, idleText }) {
  const action = state === 'consent' ? 'connectMusic' : state === 'denied' ? 'openAutomation' : null;
  const label =
    state === 'track' ? title : state === 'consent' ? "Show what's playing" : state === 'denied' ? 'Allow music in Settings' : idleText;
  return (
    <div
      className={`pc-music${action ? ' pc-music--action' : ''}`}
      onClick={action ? () => send(action) : undefined}
      role={action ? 'button' : undefined}
    >
      <div className="pc-music-cover">{state === 'track' && cover ? <img src={cover} alt="" /> : <NoteIcon />}</div>
      <div className="pc-music-title" title={label}>{label}</div>
      {state === 'track' && (
        <button
          type="button"
          className="pc-music-btn"
          onClick={() => send('playPause')}
          aria-label={playing ? 'Pause' : 'Play'}
        >
          {playing ? <PauseIcon /> : <PlayIcon />}
        </button>
      )}
    </div>
  );
}

// The native app supplies the user's details via window.__initialProps and window.updateProps(props).
// The contact button shows a settings gear and asks the app to open the Settings tab.
function render(props = {}) {
  lastProps = props;
  root.render(
    <ProfileCard
      name={props.name}
      title=""
      handle={props.handle}
      status={props.status}
      contactText={<img className="pc-settings-icon" src={props.settingsIcon} alt="" />}
      avatarUrl={props.avatarUrl}
      showUserInfo={true}
      // Reduce Motion: no 3D tilt or moving shine.
      enableTilt={!reducedMotion.matches}
      enableMobileTilt={false}
      onContactClick={() => window.webkit?.messageHandlers?.locken?.postMessage('openSettings')}
      iconUrl="iconpattern.png"
      behindGlowEnabled
      // The app passes a tint per tab; the original purple→blue gradient is the fallback.
      innerGradient={props.innerGradient || 'linear-gradient(145deg,#60496e8c 0%,#71C4FF44 100%)'}
      behindGlowColor={props.behindGlowColor}
      header={
        <MusicHeader
          state={props.musicState || 'idle'}
          title={props.musicTitle}
          cover={props.musicCover}
          playing={props.musicPlaying === '1'}
          idleText={props.musicIdleText || 'Nothing playing'}
        />
      }
    />
  );
}

window.updateProps = render;
render(window.__initialProps);
reducedMotion.addEventListener('change', () => render(lastProps));
