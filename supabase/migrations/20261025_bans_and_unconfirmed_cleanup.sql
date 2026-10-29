-- Ends every session of one account (used by admin-overview when the owner bans someone), so a banned account is
-- signed out everywhere instead of keeping its refresh tokens. Only the server's admin key can call it.
create or replace function public.admin_end_sessions(target uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from auth.sessions where user_id = target;
$$;
revoke all on function public.admin_end_sessions(uuid) from public, anon, authenticated;
grant execute on function public.admin_end_sessions(uuid) to service_role;

-- Sign-ups that never entered their email code within 24 hours are removed every night (their profile row goes with
-- them through the foreign key). Keeps bot sign-ups from piling up; a real person can simply sign up again.
create extension if not exists pg_cron;
select cron.schedule(
  'delete-unconfirmed-signups',
  '17 4 * * *',
  $$delete from auth.users where email_confirmed_at is null and created_at < now() - interval '24 hours'$$
);
