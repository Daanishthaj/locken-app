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
  // Admin: window.__admin = false hides the Admin page; bans flip the user's flag.
  if (path === '/functions/v1/admin-overview') {
    if (window.__admin === false) return json({ error: 'Not allowed' }, 403);
    const body = JSON.parse(options.body || '{}');
    window.__adminUsers ??= [
      { id: 'preview-user', email: 'mohammed@example.com', provider: 'email', createdAt: '2026-10-01T10:00:00Z', lastSignInAt: new Date().toISOString(), confirmed: true, banned: false },
      { id: 'a1b2c3d4-0000-4000-8000-000000000001', email: 'student@school.org', provider: 'google', createdAt: '2026-10-20T10:00:00Z', lastSignInAt: '2026-10-26T18:00:00Z', confirmed: true, banned: false },
      { id: 'a1b2c3d4-0000-4000-8000-000000000002', email: '<b>spam</b>@bots.example', provider: 'email', createdAt: '2026-10-27T03:00:00Z', lastSignInAt: null, confirmed: false, banned: false },
    ];
    if (body.check) return json({ admin: true });
    if (body.action) { const u = window.__adminUsers.find((x) => x.id === body.userId); if (u) u.banned = body.action === 'ban'; return json({ ok: true }); }
    return json({ generatedAt: new Date().toISOString(), totals: { accounts: 3, newLast7Days: 2, activeLast7Days: 2, activeLast30Days: 2, neverSignedIn: 1, google: 1, banned: window.__adminUsers.filter((u) => u.banned).length, feedback: 1, averageRating: 5 },
      users: window.__adminUsers, feedback: [{ email: 'student@school.org', rating: 5, message: 'Love the focus timer!', appVersion: '2.0.8', createdAt: '2026-10-25T12:00:00Z' }], audit: [],
      analytics: { security: { admins: ['preview-user'] }, events: [{ at: '2026-10-27T03:00:00Z', kind: 'sign_up', userId: 'a1b2c3d4-0000-4000-8000-000000000002' }] },
      liveVersion: { version: '2.0.8', build: 59, maintenanceMode: false }, updateServer: { reachable: true, ms: 120, status: 200 }, database: { ms: 40, ok: true } });
  }
  if (path.startsWith('/auth/v1/verify') || path.startsWith('/auth/v1/token')) return json({ access_token: 'preview-access', refresh_token: 'preview-refresh', user: { email: 'mohammed@example.com' } });
  if (path.startsWith('/auth/v1/')) return json({});
  return realFetch(url, options);
};
await import('../src/main.js');
