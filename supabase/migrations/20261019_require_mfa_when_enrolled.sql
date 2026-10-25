-- Accounts with an authenticator app (a verified TOTP factor) can reach their rows only at AAL2, after the
-- 6-digit code. The function and the profiles / focus_sessions rules were already live but missing from the
-- repo; this file records them exactly, and adds the same rule to feedback, which didn't have it (2026-10-19 audit).

create schema if not exists private;

create or replace function private.mfa_requirement_met()
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  -- Users with a verified factor must be at aal2; everyone else passes.
  select coalesce((select auth.jwt() ->> 'aal'), '') = 'aal2'
      or not exists (
        select 1 from auth.mfa_factors f
        where f.user_id = (select auth.uid()) and f.status = 'verified'
      );
$$;

revoke all on function private.mfa_requirement_met() from public, anon;
grant execute on function private.mfa_requirement_met() to authenticated;

drop policy if exists "Require MFA when enrolled" on public.profiles;
create policy "Require MFA when enrolled" on public.profiles
  as restrictive for all to authenticated
  using ((select private.mfa_requirement_met()))
  with check ((select private.mfa_requirement_met()));

drop policy if exists "Require MFA when enrolled" on public.focus_sessions;
create policy "Require MFA when enrolled" on public.focus_sessions
  as restrictive for all to authenticated
  using ((select private.mfa_requirement_met()))
  with check ((select private.mfa_requirement_met()));

drop policy if exists "Require MFA when enrolled" on public.feedback;
create policy "Require MFA when enrolled" on public.feedback
  as restrictive for all to authenticated
  using ((select private.mfa_requirement_met()))
  with check ((select private.mfa_requirement_met()));
