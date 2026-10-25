-- Applied to project isohdbjcvluvaflmrfeg on 2026-10-10.

-- Defense in depth: the public (anon) key never needs account tables, so it loses every privilege on them,
-- even if a policy were ever written wrong.
revoke all on table public.profiles, public.focus_sessions from anon;

-- RLS doesn't apply to TRUNCATE, REFERENCES or TRIGGER, and signed-in users never need them.
revoke truncate, references, trigger on table public.profiles, public.focus_sessions from authenticated;

-- The live site has no waitlist form, and this policy let anyone with the public key insert rows with no
-- rate limit. Close it; existing rows stay. A future waitlist should go through a rate-limited Edge Function.
drop policy if exists "Allow anonymous waitlist signups" on public.waitlist_subscribers;
revoke all on table public.waitlist_subscribers from anon, authenticated;
alter table public.waitlist_subscribers
  add constraint waitlist_email_length check (char_length(email) <= 254) not valid;
