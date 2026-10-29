// Cloudflare Turnstile, the bot check in front of sign-in (same as the Mac app). Supabase verifies its token on
// sign-up, sign-in, email codes and password reset once CAPTCHA protection is switched on in the dashboard.
// Off until TURNSTILE_SITE_KEY is set: captchaToken() then returns null and nothing changes.
// The widget is invisible unless Cloudflare asks the person to click; each token is used once.

export const TURNSTILE_SITE_KEY = '0x4AAAAAAFo_JiXIrKghT2dE';

let widgetId = null;
let pending = null;
let readyPromise = null;

function container() {
  let box = document.getElementById('turnstile');
  if (!box) {
    box = document.createElement('div');
    box.id = 'turnstile';
    box.className = 'turnstile';
    box.hidden = true;
    document.body.appendChild(box);
  }
  return box;
}

function finish(error, token) {
  const waiting = pending;
  pending = null;
  container().hidden = true;
  if (!waiting) return;
  if (error) waiting.reject(error); else waiting.resolve(token);
}

function load() {
  if (readyPromise) return readyPromise;
  readyPromise = new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';
    script.async = true;
    script.onerror = () => { readyPromise = null; reject(new Error('blocked')); };
    script.onload = () => {
      widgetId = window.turnstile.render(container(), {
        sitekey: TURNSTILE_SITE_KEY,
        execution: 'execute',
        appearance: 'interaction-only',
        theme: 'dark',
        callback: (token) => finish(null, token),
        'error-callback': () => { finish(new Error('failed')); return true; },
        'before-interactive-callback': () => { container().hidden = false; },
        'after-interactive-callback': () => { container().hidden = true; },
      });
      resolve();
    };
    document.head.appendChild(script);
  });
  return readyPromise;
}

/** A fresh single-use token, or null when the bot check is off. */
export async function captchaToken() {
  if (!TURNSTILE_SITE_KEY) return null;
  const failed = "Couldn't confirm you're a person. Check your internet connection and try again.";
  try { await load(); } catch { throw new Error(failed); }
  if (pending) finish(new Error(failed));
  return new Promise((resolve, reject) => {
    pending = { resolve, reject: () => reject(new Error(failed)) };
    window.turnstile.reset(widgetId);
    window.turnstile.execute(widgetId);
    setTimeout(() => { if (pending) finish(new Error(failed)); }, 120000);
  });
}
