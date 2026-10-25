// Preview-only: answer the few Supabase calls the app makes at start with a fake signed-in user. Never shipped.
const realFetch = window.fetch.bind(window);
window.fetch = async (url, options = {}) => {
  const path = String(url).replace(/^https:\/\/[^/]+/, '');
  const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
  // Two-factor: window.__mfa = true makes the account enrolled; the code 123456 passes and returns an AAL2 token.
  const FACTOR = '11111111-2222-3333-4444-555555555555';
  const aal2 = `x.${btoa(JSON.stringify({ aal: 'aal2' }))}.y`;
  if (path.startsWith('/auth/v1/user')) return json({ id: 'preview-user', email: 'mohammed@example.com', factors: window.__mfa ? [{ id: FACTOR, factor_type: 'totp', status: 'verified' }] : [] });
  if (path === '/auth/v1/factors') return json({ id: FACTOR, totp: { qr_code: "data:image/svg+xml;utf-8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 4 4'><rect width='2' height='2'/><rect x='2' y='2' width='2' height='2'/></svg>", secret: 'JBSWY3DPEHPK3PXP' } });
  if (path.endsWith('/challenge')) return json({ id: 'challenge-1' });
  if (path.endsWith('/verify') && path.includes('/factors/')) {
    const ok = JSON.parse(options.body || '{}').code === '123456';
    if (ok) { window.__mfa = true; window.__aal2 = true; }
    return ok ? json({ access_token: aal2, refresh_token: 'preview-refresh' }) : json({ msg: 'invalid' }, 422);
  }
  if (path.startsWith('/auth/v1/factors/') && options.method === 'DELETE') { window.__mfa = false; return json({}); }
  if (path.startsWith('/rest/v1/profiles')) return json([{ birth_month: 5, birth_year: 2000, terms_agreed_at: '2026-10-01T00:00:00Z' }]);
  if (path.startsWith('/rest/v1/feedback')) return json({}, 201);
  if (path.startsWith('/auth/v1/verify') || path.startsWith('/auth/v1/token')) return json({ access_token: 'preview-access', refresh_token: 'preview-refresh', user: { email: 'mohammed@example.com' } });
  if (path.startsWith('/auth/v1/')) return json({});
  return realFetch(url, options);
};
await import('../src/main.js');
