-- Owner analytics for the admin console, built only from data Supabase Auth already keeps.
-- Activity = refresh-token rotations per day; build = the "Locken/NN" user agent on the latest session.
-- SECURITY DEFINER and callable only by service_role (the admin-overview edge function).
CREATE OR REPLACE FUNCTION public.admin_analytics()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
with days as (
    select generate_series((now() - interval '29 days')::date, now()::date, interval '1 day')::date as d
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
           (select count(*) from auth.sessions s where s.user_id = u.id) as sessions,
           (select substring(s.user_agent from 'Locken[^/]*/([0-9]+)') from auth.sessions s
              where s.user_id = u.id and s.user_agent like 'Locken%' order by coalesce(s.refreshed_at, s.updated_at, s.created_at) desc limit 1) as build
    from auth.users u
    left join activity a on a.user_id = u.id
    group by u.id
)
select jsonb_build_object(
    'daily', (select jsonb_agg(jsonb_build_object(
                    'day', days.d,
                    'activeUsers', (select count(distinct a.user_id) from activity a where a.d = days.d),
                    'refreshes', coalesce((select sum(a.refreshes) from activity a where a.d = days.d), 0),
                    'signups', (select count(*) from auth.users u where u.created_at::date = days.d)
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
                    'id', p.id, 'activeDays', p.active_days, 'refreshes', p.refreshes,
                    'lastActive', p.last_active, 'sessions', p.sessions, 'build', p.build)), '[]'::jsonb) from per_user p),
    'database', jsonb_build_object(
        'sizeMB', round(pg_database_size(current_database()) / 1048576.0, 1),
        'profiles', (select count(*) from public.profiles),
        'feedback', (select count(*) from public.feedback),
        'auditEntries', (select count(*) from audit.log),
        'focusSessions', (select count(*) from public.focus_sessions)
    )
);
$function$;

revoke all on function public.admin_analytics() from public, anon, authenticated;
grant execute on function public.admin_analytics() to service_role;
