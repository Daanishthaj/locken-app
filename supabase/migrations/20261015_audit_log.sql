-- Audit log: records when account data is created, changed or deleted, and by whom.
-- Stores no personal values: only the table, the action, the row's ID, who did it and which columns changed.
-- It lives in its own `audit` schema, which the REST API doesn't expose, and no app role can read or write it.
-- Only the project owner (dashboard / SQL editor, or the service role) can see it.

create schema if not exists audit;
revoke all on schema audit from public, anon, authenticated;

create table if not exists audit.log (
    id bigint generated always as identity primary key,
    occurred_at timestamptz not null default now(),
    table_name text not null,
    action text not null check (action in ('INSERT', 'UPDATE', 'DELETE')),
    row_id uuid,
    actor uuid,              -- the signed-in user who made the change (auth.uid()); null for the server or dashboard
    actor_role text,         -- authenticated, service_role, postgres, …
    changed_columns text[]   -- names only, never the values
);
alter table audit.log enable row level security;
revoke all on audit.log from public, anon, authenticated;
create index if not exists log_occurred_at_idx on audit.log (occurred_at);
create index if not exists log_row_id_idx on audit.log (row_id);

create or replace function audit.record_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    changed text[];
    target_id uuid;
begin
    if tg_op = 'UPDATE' then
        select array_agg(n.key order by n.key) into changed
        from jsonb_each(to_jsonb(new)) n
        join jsonb_each(to_jsonb(old)) o using (key)
        where n.value is distinct from o.value;
        -- Sign-ins rewrite timestamps on auth.users; only record changes that matter.
        if tg_table_schema = 'auth' then
            changed := array(select c from unnest(changed) c where c in ('email', 'phone', 'encrypted_password', 'banned_until', 'deleted_at'));
        end if;
        if changed is null or cardinality(changed) = 0 then
            return new;
        end if;
    end if;

    target_id := case when tg_op = 'DELETE' then (to_jsonb(old) ->> 'id')::uuid else (to_jsonb(new) ->> 'id')::uuid end;

    insert into audit.log (table_name, action, row_id, actor, actor_role, changed_columns)
    values (
        tg_table_schema || '.' || tg_table_name,
        tg_op,
        target_id,
        auth.uid(),
        coalesce(nullif(current_setting('request.jwt.claim.role', true), ''), current_user),
        changed
    );
    return case when tg_op = 'DELETE' then old else new end;
exception when others then
    -- Logging must never block a sign-up, sign-in or account deletion.
    return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function audit.record_change() from public, anon, authenticated;

drop trigger if exists audit_profiles on public.profiles;
create trigger audit_profiles after insert or update or delete on public.profiles
    for each row execute function audit.record_change();

drop trigger if exists audit_focus_sessions on public.focus_sessions;
create trigger audit_focus_sessions after insert or update or delete on public.focus_sessions
    for each row execute function audit.record_change();

drop trigger if exists audit_auth_users on auth.users;
create trigger audit_auth_users after insert or update or delete on auth.users
    for each row execute function audit.record_change();

-- Retention (applied as migration audit_log_retention): keep 24 months; each new record clears older ones.
create or replace function audit.prune_old()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    delete from audit.log where occurred_at < now() - interval '24 months';
    return null;
exception when others then
    return null;
end;
$$;
revoke all on function audit.prune_old() from public, anon, authenticated;
drop trigger if exists audit_log_prune on audit.log;
create trigger audit_log_prune after insert on audit.log
    for each statement execute function audit.prune_old();
