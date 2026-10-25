// The startup padlock reveal, ported from the Mac app's LaunchRevealView (same steps and timings): a 60-tick dial
// sweeps in, the shackle draws from both ends, the body tips up into place, the keyhole appears, the shackle snaps
// shut with a squash, a sheen and glow pass, the ticks flash, then "Locken" writes on and the tagline fades in.
// A click or any key skips it. Reduce Motion shows the finished lock briefly instead.

const easeOut = 'cubic-bezier(0.23, 1, 0.32, 1)';
const easeInOut = 'cubic-bezier(0.77, 0, 0.175, 1)';
const spring = 'cubic-bezier(0.34, 1.56, 0.64, 1)';

export function playLaunchReveal(tagline = 'Focus for Windows') {
  return new Promise((resolve) => {
    const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    const root = document.createElement('div');
    root.className = 'launch';
    root.setAttribute('aria-hidden', 'true');
    root.innerHTML = `
      <div class="launch-glow"></div>
      <div class="launch-stack">
        <div class="launch-mark">
          <div class="launch-dial"></div>
          <div class="launch-lock">
            <div class="launch-lock-glow"></div>
            <svg class="launch-shackle" viewBox="0 0 70 66" width="70" height="66">
              <defs><linearGradient id="lr-shackle" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#B98AF0"/><stop offset="1" stop-color="#8C33E6"/></linearGradient></defs>
              <path class="lr-half lr-left" d="M6.5 66 V35 A28.5 28.5 0 0 1 35 6.5" />
              <path class="lr-half lr-right" d="M63.5 66 V35 A28.5 28.5 0 0 0 35 6.5" />
            </svg>
            <div class="launch-body"><div class="launch-sheen"></div><div class="launch-keyhole"><span></span><i></i></div></div>
          </div>
        </div>
        <div class="launch-words">
          <p class="launch-wordmark">Locken</p>
          <p class="launch-tagline">${tagline}</p>
        </div>
      </div>`;
    const dial = root.querySelector('.launch-dial');
    for (let i = 0; i < 60; i++) {
      const tick = document.createElement('span');
      tick.className = i % 5 === 0 ? 'tick major' : 'tick';
      tick.style.transform = `rotate(${i * 6}deg) translateY(-132px)`;
      tick.style.setProperty('--d-show', `${i * 7}ms`);
      tick.style.setProperty('--d-lit', `${i * 6}ms`);
      dial.append(tick);
    }
    document.body.append(root);

    let leaving = false;
    const timers = [];
    const at = (ms, fn) => timers.push(setTimeout(fn, ms));
    const finish = () => {
      if (leaving) return;
      leaving = true;
      timers.forEach(clearTimeout);
      root.classList.add('leaving');
      setTimeout(() => { root.remove(); resolve(); }, reduce ? 200 : 450);
    };
    root.addEventListener('click', finish);
    window.addEventListener('keydown', finish, { once: true });

    if (reduce) {
      root.classList.add('ticks', 'shackle', 'body', 'keyhole', 'locked', 'words', 'tagline', 'calm');
      at(700, finish);
      return;
    }
    // Same order and gaps as the Mac app.
    requestAnimationFrame(() => root.classList.add('ticks'));
    let t = 250;
    at(t, () => root.classList.add('shackle'));
    t += 220; at(t, () => root.classList.add('body'));
    t += 380; at(t, () => root.classList.add('keyhole'));
    t += 180; at(t, () => root.classList.add('locked'));
    t += 170; at(t, () => root.classList.add('squash', 'glow', 'lit', 'sheen'));
    t += 90; at(t, () => root.classList.remove('squash'));
    t += 260; at(t, () => { root.classList.remove('lit', 'glow'); root.classList.add('words', 'calm'); });
    t += 450; at(t, () => root.classList.add('tagline'));
    t += 650; at(t, finish);
  });
}

export const launchRevealCss = `
.launch { position: fixed; inset: 0; z-index: 100; display: grid; place-items: center; background: #0b0b0f; cursor: default;
  transition: opacity 0.45s ${easeOut}; }
.launch-glow { position: absolute; inset: 0; background: radial-gradient(460px circle at 50% 50%, rgba(140, 51, 230, 0.05), transparent 70%); transition: background 0.25s ${easeOut}; }
.launch.glow .launch-glow { background: radial-gradient(460px circle at 50% 50%, rgba(140, 51, 230, 0.2), transparent 70%); }
.launch.calm .launch-glow { background: radial-gradient(460px circle at 50% 50%, rgba(140, 51, 230, 0.11), transparent 70%); transition-duration: 0.6s; }
.launch-stack { position: relative; display: flex; flex-direction: column; align-items: center; gap: 26px; transition: transform 0.45s ${easeOut}, filter 0.45s ${easeOut}; }
.launch-mark { position: relative; width: 304px; height: 304px; display: grid; place-items: center; }
.launch-dial { position: absolute; inset: 0; transition: transform 0.45s ${easeOut}; }
.launch .tick { position: absolute; left: 50%; top: 50%; width: 1px; height: 7px; margin: -3.5px 0 0 -0.5px; border-radius: 1px; background: #fff; opacity: 0;
  transition: opacity 0.3s ${easeOut} var(--d-show), background-color 0.22s ${easeOut} var(--d-lit); }
.launch .tick.major { width: 2px; height: 12px; margin: -6px 0 0 -1px; }
.launch.ticks .tick { opacity: 0.16; }
.launch.ticks .tick.major { opacity: 0.38; }
.launch.lit .tick { opacity: 0.95; background: #c599f2; transition: opacity 0.22s ${easeOut} var(--d-lit), background-color 0.22s ${easeOut} var(--d-lit); }
.launch-lock { position: relative; width: 150px; height: 150px; transform: translateY(-18px); }
.launch-lock-glow { position: absolute; left: 0; top: 50px; width: 150px; height: 150px; border-radius: 50%; background: #8c33e6; filter: blur(44px); opacity: 0; transition: opacity 0.25s ${easeOut}; }
.launch.glow .launch-lock-glow { opacity: 0.68; }
.launch.calm .launch-lock-glow { opacity: 0.27; transition-duration: 0.6s; }
.launch-shackle { position: absolute; left: 40px; top: 0; transform: translateY(-4px); transition: transform 0.22s ${easeInOut}; overflow: visible; }
.launch.locked .launch-shackle { transform: translateY(8px); }
.lr-half { fill: none; stroke: url(#lr-shackle); stroke-width: 13; stroke-linecap: round; stroke-dasharray: 76; stroke-dashoffset: 76; transition: stroke-dashoffset 0.6s ${easeOut}; }
.launch.shackle .lr-half { stroke-dashoffset: 0; }
.launch-body { position: absolute; left: 17px; top: 58px; width: 116px; height: 92px; border-radius: 22px; overflow: hidden; opacity: 0;
  background: linear-gradient(135deg, #a15eea, rgba(139, 92, 246, 0.95), #8c33e6); box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.35), 0 12px 18px rgba(0, 0, 0, 0);
  transform-origin: 50% 100%; transform: perspective(300px) translateY(16px) rotateX(38deg);
  transition: transform 0.5s ${spring}, opacity 0.3s ease, box-shadow 0.4s ease; }
.launch.body .launch-body { opacity: 1; transform: perspective(300px) translateY(0) rotateX(0); box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.35), 0 12px 18px rgba(0, 0, 0, 0.45); }
.launch.squash .launch-body { transform: perspective(300px) scale(1.02, 0.97); transition: transform 0.08s ease-out; }
.launch-sheen { position: absolute; top: -20%; left: -60%; width: 45%; height: 140%; transform: rotate(18deg) translateX(-140%);
  background: linear-gradient(90deg, transparent, rgba(255, 255, 255, 0.32), transparent); }
.launch.sheen .launch-sheen { transform: rotate(18deg) translateX(420%); transition: transform 0.7s ${easeInOut}; }
.launch-keyhole { position: absolute; left: 50%; top: 50%; display: flex; flex-direction: column; align-items: center; transform: translate(-50%, -42%) scale(0.6); opacity: 0;
  transition: transform 0.28s ${easeOut}, opacity 0.28s ${easeOut}; }
.launch-keyhole span { width: 20px; height: 20px; border-radius: 50%; background: #0b0b0f; box-shadow: 0 1px 0 rgba(255, 255, 255, 0.18); }
.launch-keyhole i { width: 8px; height: 22px; margin-top: -4px; border-radius: 4px; background: #0b0b0f; box-shadow: 0 1px 0 rgba(255, 255, 255, 0.18); }
.launch.keyhole .launch-keyhole { opacity: 1; transform: translate(-50%, -42%) scale(1); }
.launch-words { display: flex; flex-direction: column; align-items: center; gap: 6px; }
.launch-wordmark { margin: 0; font: 400 50px/1.1 "Locken Script", "Segoe Script", cursive; color: #fff;
  -webkit-mask-image: linear-gradient(90deg, #fff 0, #fff 82%, transparent 100%); -webkit-mask-size: 140% 100%; -webkit-mask-repeat: no-repeat; -webkit-mask-position: -140% 0;
  mask-image: linear-gradient(90deg, #fff 0, #fff 82%, transparent 100%); mask-size: 140% 100%; mask-repeat: no-repeat; mask-position: -140% 0; }
.launch.words .launch-wordmark { -webkit-mask-position: 0 0; mask-position: 0 0; transition: -webkit-mask-position 0.7s linear, mask-position 0.7s linear; }
.launch-tagline { margin: 0; font: 500 12px "Montserrat", sans-serif; letter-spacing: 2.4px; color: rgba(255, 255, 255, 0.6); opacity: 0; transform: translateY(4px);
  transition: opacity 0.4s ${easeOut}, transform 0.4s ${easeOut}; }
.launch.tagline .launch-tagline { opacity: 1; transform: none; }
.launch.leaving { opacity: 0; }
.launch.leaving .launch-stack { transform: translateY(-12px); filter: blur(8px); }
.launch.leaving .launch-dial { transform: scale(1.35); }
@media (prefers-reduced-motion: reduce) { .launch * { transition-duration: 0s !important; } }
`;
