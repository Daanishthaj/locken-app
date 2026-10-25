-- Least privilege for signed-in users. RLS already blocks these, but the rights themselves shouldn't exist.
-- Applied to project isohdbjcvluvaflmrfeg on 2026-10-12.

-- Profiles are created by the handle_new_user trigger and removed by the cascade from auth.users,
-- so no app ever inserts or deletes them. Updates stay limited to full_name and avatar_url.
revoke insert, delete on public.profiles from authenticated;

-- A session row can't be moved to another owner or have its id or timestamp rewritten.
revoke update on public.focus_sessions from authenticated;
grant update (session_name, duration_minutes, completed) on public.focus_sessions to authenticated;

-- Every RLS check filters on user_id (performance advisor: unindexed foreign key).
create index if not exists focus_sessions_user_id_idx on public.focus_sessions (user_id);
