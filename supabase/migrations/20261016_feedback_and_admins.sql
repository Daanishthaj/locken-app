-- Applied to project isohdbjcvluvaflmrfeg as migration feedback_and_admins (2026-10-16).

-- In-app feedback: signed-in users can add their own feedback and nothing else (no reading, editing or deleting).
create table if not exists public.feedback (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
    rating smallint check (rating between 1 and 5),
    message text not null default '' check (char_length(message) <= 2000),
    app_version text check (char_length(app_version) <= 20),
    created_at timestamptz not null default now()
);
alter table public.feedback enable row level security;
revoke all on public.feedback from anon, authenticated;
grant insert (rating, message, app_version) on public.feedback to authenticated;
drop policy if exists "Users add their own feedback" on public.feedback;
create policy "Users add their own feedback" on public.feedback
    for insert to authenticated with check (user_id = (select auth.uid()));
create index if not exists feedback_user_created_idx on public.feedback (user_id, created_at);

-- At most 5 feedback messages per account per day.
create or replace function public.feedback_rate_limit()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
    if (select count(*) from public.feedback f
        where f.user_id = new.user_id and f.created_at > now() - interval '1 day') >= 5 then
        raise exception 'Too much feedback today. Try again tomorrow.';
    end if;
    return new;
end;
$$;
revoke all on function public.feedback_rate_limit() from public, anon, authenticated;
drop trigger if exists feedback_rate_limit on public.feedback;
create trigger feedback_rate_limit before insert on public.feedback
    for each row execute function public.feedback_rate_limit();

drop trigger if exists audit_feedback on public.feedback;
create trigger audit_feedback after insert or update or delete on public.feedback
    for each row execute function audit.record_change();

-- Who may open the admin view. Readable only by the server (service role); no app role can read or change it.
create table if not exists public.admins (
    user_id uuid primary key references auth.users(id) on delete cascade,
    added_at timestamptz not null default now()
);
alter table public.admins enable row level security;
revoke all on public.admins from anon, authenticated;
insert into public.admins (user_id)
select id from auth.users where email in ('talk2daanish@gmail.com', 'mr.tryhard66@gmail.com', 'daanu.focus@gmail.com')
on conflict do nothing;

-- Recent audit entries for the admin view; callable only by the server.
create or replace function public.admin_recent_audit(max_rows int default 50)
returns table (occurred_at timestamptz, table_name text, action text, row_id uuid, actor uuid, changed_columns text[])
language sql security definer set search_path = '' as $$
    select l.occurred_at, l.table_name, l.action, l.row_id, l.actor, l.changed_columns
    from audit.log l order by l.occurred_at desc limit least(max_rows, 200);
$$;
revoke all on function public.admin_recent_audit(int) from public, anon, authenticated;
grant execute on function public.admin_recent_audit(int) to service_role;
