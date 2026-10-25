-- Admin console v2: longer history (180 days, for period-over-period comparisons), per-user activity days,
-- a merged event feed, sign-in method health and security checks. Still built only from data Supabase
-- already keeps; the app collects nothing new. SECURITY DEFINER, callable only by service_role.
CREATE OR REPLACE FUNCTION public.admin_analytics()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
with days as (
    select generate_series((now() - interval '179 days')::date, now()::date, interval '1 day')::date as d
),
activity as (
    select created_at::date as d, user_id::uuid as user_id, count(*) as refreshes
    from auth.refresh_tokens
    where user_id is not null and user_id ~ '^[0-9a-f-]{36}$'
    group by 1, 2
),
per_user as (
    select u.id,
           count(distinct a.d) as active_days,
           coalesce(sum(a.refreshes), 0) as refreshes,
           max(a.d) as last_active,
           coalesce(jsonb_agg(distinct a.d) filter (where a.d is not null and a.d > now()::date - 180), '[]'::jsonb) as active_dates,
           (select count(*) from auth.sessions s where s.user_id = u.id) as sessions,
           (select count(*) from auth.sessions s where s.user_id = u.id and (s.not_after is null or s.not_after > now())) as live_sessions,
           exists (select 1 from auth.mfa_factors f where f.user_id = u.id and f.status = 'verified') as mfa,
           (select substring(s.user_agent from 'Locken[^/]*/([0-9]+)') from auth.sessions s
              where s.user_id = u.id and s.user_agent like 'Locken%' order by coalesce(s.refreshed_at, s.updated_at, s.created_at) desc limit 1) as build
    from auth.users u
    left join activity a on a.user_id = u.id
    group by u.id
),
events as (
    select created_at as at, 'signup' as kind, id as user_id, null::text as detail from auth.users
    union all
    select email_confirmed_at, 'confirmed', id, null from auth.users where email_confirmed_at is not null
    union all
    select created_at, 'signin', user_id, substring(user_agent from 'Locken[^/]*/([0-9]+)') from auth.sessions
    union all
    select created_at, 'mfa', user_id, factor_type::text from auth.mfa_factors where status = 'verified'
    union all
    select created_at, 'feedback', user_id, rating::text from public.feedback
    union all
    select occurred_at, 'change', coalesce(row_id, actor), table_name || ' ' || lower(action) from audit.log
)
select jsonb_build_object(
    'daily', (select jsonb_agg(jsonb_build_object(
                    'day', days.d,
                    'activeUsers', (select count(distinct a.user_id) from activity a where a.d = days.d),
                    'refreshes', coalesce((select sum(a.refreshes) from activity a where a.d = days.d), 0),
                    'signups', (select count(*) from auth.users u where u.created_at::date = days.d),
                    'signIns', (select count(*) from auth.sessions s where s.created_at::date = days.d)
                ) order by days.d) from days),
    'weeklyActive', (select count(distinct user_id) from activity where d > now()::date - 7),
    'monthlyActive', (select count(distinct user_id) from activity where d > now()::date - 30),
    'returningUsers', (select count(*) from per_user where active_days >= 2),
    'oneDayUsers', (select count(*) from per_user where active_days = 1),
    'liveSessions', (select count(*) from auth.sessions where not_after is null or not_after > now()),
    'twoFactorUsers', (select count(distinct user_id) from auth.mfa_factors where status = 'verified'),
    'unconfirmed', (select count(*) from auth.users where email_confirmed_at is null),
    'builds', (select coalesce(jsonb_agg(jsonb_build_object('build', b.build, 'users', b.n) order by b.build::int desc), '[]'::jsonb)
               from (select build, count(*) as n from per_user where build is not null group by build) b),
    'perUser', (select coalesce(jsonb_agg(jsonb_build_object(
                    'id', p.id, 'activeDays', p.active_days, 'refreshes', p.refreshes, 'lastActive', p.last_active,
                    'activeDates', p.active_dates, 'sessions', p.sessions, 'liveSessions', p.live_sessions,
                    'mfa', p.mfa, 'build', p.build)), '[]'::jsonb) from per_user p),
    'signInMethods', (select coalesce(jsonb_agg(jsonb_build_object(
                    'provider', i.provider, 'accounts', i.n, 'lastUsed', i.last_used, 'newLast30', i.new30)), '[]'::jsonb)
               from (select provider, count(distinct user_id) as n, max(last_sign_in_at) as last_used,
                            count(*) filter (where created_at > now() - interval '30 days') as new30
                     from auth.identities group by provider) i),
    'events', (select coalesce(jsonb_agg(jsonb_build_object('at', e.at, 'kind', e.kind, 'userId', e.user_id, 'detail', e.detail)
                    order by e.at desc), '[]'::jsonb)
               from (select * from events where at is not null order by at desc limit 200) e),
    'security', jsonb_build_object(
        'tables', (select jsonb_agg(jsonb_build_object('table', tablename, 'rls', rowsecurity) order by tablename)
                   from pg_tables where schemaname = 'public'),
        'exposedFunctions', (select coalesce(jsonb_agg(p.proname order by p.proname), '[]'::jsonb)
                   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                   where n.nspname = 'public' and p.prosecdef
                     and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))),
        'admins', (select coalesce(jsonb_agg(user_id), '[]'::jsonb) from public.admins)
    ),
    'database', jsonb_build_object(
        'sizeMB', round(pg_database_size(current_database()) / 1048576.0, 1),
        'profiles', (select count(*) from public.profiles),
        'feedback', (select count(*) from public.feedback),
        'auditEntries', (select count(*) from audit.log),
        'focusSessions', (select count(*) from public.focus_sessions),
        'waitlist', (select count(*) from public.waitlist_subscribers)
    )
);
$function$;

revoke all on function public.admin_analytics() from public, anon, authenticated;
grant execute on function public.admin_analytics() to service_role;
