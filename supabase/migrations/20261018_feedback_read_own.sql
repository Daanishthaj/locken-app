-- Download My Data includes the feedback a user sent, so each signed-in user may read their own feedback rows.
-- Row Level Security keeps everyone else's rows invisible; nobody gets UPDATE or DELETE (rows go with the account).
grant select on table public.feedback to authenticated;

create policy "Users read their own feedback"
  on public.feedback
  for select
  to authenticated
  using (user_id = (select auth.uid()));
