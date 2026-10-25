-- Birth month and year, and when the Terms were agreed, now live on the account, so every Mac and PC uses the same
-- answer (before, each computer kept its own and could be given a different one).
--
-- Rules, enforced here rather than trusted to the apps:
--   * Write-once: the birth month and year can be set only while empty; changing them later is refused.
--   * Under 13 is refused, so a child's birth date is never stored (the app then deletes the account).
--   * The agreement time is set by the server (now()), once.
--   * Users still read and update only their own row (existing RLS), and only these columns plus name and avatar.

alter table public.profiles
  add column if not exists birth_month smallint check (birth_month between 1 and 12),
  add column if not exists birth_year smallint check (birth_year between 1900 and 2100),
  add column if not exists terms_agreed_at timestamptz;

create or replace function private.guard_profile_consent()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  years int;
begin
  if new.birth_month is distinct from old.birth_month or new.birth_year is distinct from old.birth_year then
    if old.birth_month is not null or old.birth_year is not null then
      raise exception 'birth month and year are already set' using errcode = '42501';
    end if;
    if (new.birth_month is null) <> (new.birth_year is null) then
      raise exception 'birth month and year go together' using errcode = '22023';
    end if;
    -- Whole years, the same way the apps count them: the birthday month itself still counts as the younger age.
    years := extract(year from now())::int - new.birth_year
             - case when extract(month from now())::int > new.birth_month then 0 else 1 end;
    if years < 13 or years > 120 then
      raise exception 'age not allowed' using errcode = '22023';
    end if;
  end if;

  if new.terms_agreed_at is distinct from old.terms_agreed_at then
    if old.terms_agreed_at is not null then
      raise exception 'terms already agreed' using errcode = '42501';
    end if;
    new.terms_agreed_at := now();
  end if;
  return new;
end;
$$;

revoke all on function private.guard_profile_consent() from public, anon, authenticated;

drop trigger if exists guard_profile_consent on public.profiles;
create trigger guard_profile_consent
  before update on public.profiles
  for each row execute function private.guard_profile_consent();

grant select (birth_month, birth_year, terms_agreed_at) on public.profiles to authenticated;
grant update (birth_month, birth_year, terms_agreed_at) on public.profiles to authenticated;
