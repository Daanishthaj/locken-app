import { createRoot } from 'react-dom/client';
import { SiApplemusic, SiArc, SiBrave, SiClaude, SiGooglegemini, SiGoogle, SiSoundcloud, SiYoutube, SiYoutubemusic } from 'react-icons/si';
import LogoLoop from '../components/LogoLoop';
import '../components/LogoLoop.css';

// "Works with": every service Locken can connect to, as two slow rows of React Bits LogoLoop. Only real connections are
// listed (Google Classroom joins when its sign-in is switched on). The icons for Canvas, the Apple apps, Safari, Chrome and
// Spotify are the same ones the static row used; the rest are Simple Icons through react-icons, and a few services without
// a mark in that set show only their name. Without JavaScript the static row inside #connectors stays.
const brand = (Icon, color) => <Icon style={{ color }} />;

const schoolAndBrowsers = [
  { node: <span className="canvas-icon" aria-hidden="true" />, title: 'Canvas' },
  { node: <span className="cal-icon" aria-hidden="true"><b>OCT</b><i>17</i></span>, title: 'Calendar' },
  { node: <span className="rem-icon" aria-hidden="true"><i /><i /><i /></span>, title: 'Reminders' },
  { node: <span className="notes-icon" aria-hidden="true" />, title: 'Notes' },
  { src: '/logos/safari.svg', alt: '', title: 'Safari' },
  { src: '/logos/chrome.svg', alt: '', title: 'Chrome' },
  { node: brand(SiArc, '#fff'), title: 'Arc' },
  { node: brand(SiBrave, '#FB542B'), title: 'Brave' },
  { node: <span className="connector-name">Microsoft Edge</span>, title: '', ariaLabel: 'Microsoft Edge' },
  { node: <span className="connector-name">Comet</span>, title: '', ariaLabel: 'Comet' },
];

const musicAndAi = [
  { src: '/logos/spotify.svg', alt: '', title: 'Spotify' },
  { node: brand(SiApplemusic, '#FA243C'), title: 'Apple Music' },
  { node: brand(SiYoutube, '#FF0000'), title: 'YouTube' },
  { node: brand(SiYoutubemusic, '#FF0000'), title: 'YouTube Music' },
  { node: brand(SiSoundcloud, '#FF5500'), title: 'SoundCloud' },
  { node: brand(SiClaude, '#D97757'), title: 'Claude' },
  { node: <span className="connector-name">ChatGPT</span>, title: '', ariaLabel: 'ChatGPT' },
  { node: brand(SiGooglegemini, '#8E75FF'), title: 'Gemini' },
  { node: brand(SiGoogle, '#fff'), title: 'Google sign-in' },
];

const rows = [
  { logos: schoolAndBrowsers, direction: 'left', ariaLabel: 'Apps Locken works with: school, calendar and browsers' },
  { logos: musicAndAi, direction: 'right', ariaLabel: 'Apps Locken works with: music and AI' },
];

const container = document.getElementById('connectors');
if (container) {
  createRoot(container).render(
    rows.map((row) => (
      <LogoLoop
        key={row.ariaLabel}
        logos={row.logos}
        direction={row.direction}
        speed={38}
        logoHeight={44}
        gap={64}
        labels="below"
        hoverSpeed={0}
        ariaLabel={row.ariaLabel}
      />
    ))
  );
}
