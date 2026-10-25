-- ==============================================================================
-- LOCKEN — SUPABASE PRODUCTION DATABASE SCHEMA & ROW LEVEL SECURITY (RLS)
-- ==============================================================================
-- Run this SQL in your Supabase Dashboard: SQL Editor -> New Query -> Run

-- 1. PROFILES TABLE (Linked to auth.users)
create table if not exists public.profiles (
  id uuid references auth.users on delete cascade not null primary key,
  email text unique not null,
  full_name text,
  avatar_url text,
  plan text default 'free' check (plan in ('free', 'pro', 'enterprise')),
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Enable Row Level Security (Strict isolation between users)
alter table public.profiles enable row level security;

-- Policy 1: Users can only read their own profile
create policy "Users can view own profile"
  on public.profiles
  for select
  using (auth.uid() = id);

-- Policy 2: Users can only update their own profile
create policy "Users can update own profile"
  on public.profiles
  for update
  using (auth.uid() = id);

-- 2. AUTOMATIC PROFILE CREATION TRIGGER ON SIGNUP (Google OAuth or Email)
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, email, full_name, avatar_url)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)),
    new.raw_user_meta_data->>'avatar_url'
  )
  on conflict (id) do update
  set
    email = excluded.email,
    full_name = coalesce(excluded.full_name, profiles.full_name),
    avatar_url = coalesce(excluded.avatar_url, profiles.avatar_url),
    updated_at = timezone('utc'::text, now());
  return new;
end;
$$ language plpgsql security definer;

-- Drop trigger if already exists and recreate
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert or update on auth.users
  for each row execute procedure public.handle_new_user();

-- 3. WAITLIST SUBSCRIBERS TABLE
create table if not exists public.waitlist_subscribers (
  id uuid default gen_random_uuid() primary key,
  email text unique not null,
  source text default 'web_landing',
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Enable RLS for waitlist
alter table public.waitlist_subscribers enable row level security;

-- Allow public anonymous inserts to waitlist
create policy "Allow public to subscribe to waitlist"
  on public.waitlist_subscribers
  for insert
  with check (true);

-- Restrict waitlist reading to authenticated service role only
create policy "Only service role can view waitlist"
  on public.waitlist_subscribers
  for select
  using (auth.jwt() ->> 'role' = 'service_role');

-- 4. SERVER-SIDE ROLE-BASED ACCESS CONTROL (RBAC) — NO CLIENT-SIDE ADMIN CHECKS
-- Protects against client-side role manipulation, parameter tampering, and privilege escalation
create table if not exists public.user_roles (
  user_id uuid references auth.users on delete cascade not null primary key,
  role text not null check (role in ('user', 'moderator', 'admin')) default 'user',
  granted_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Enable strict RLS on user_roles
alter table public.user_roles enable row level security;

-- Service role alone manages and assigns roles (Client requests can NEVER elevate roles)
create policy "Service role alone manages roles"
  on public.user_roles
  for all
  using (auth.jwt() ->> 'role' = 'service_role');

-- Users can only read their own role (read-only)
create policy "Users can read own role"
  on public.user_roles
  for select
  using (auth.uid() = user_id);

-- 5. DATABASE INTEGRITY & INPUT LENGTH CONSTRAINTS (Defense-in-Depth)
alter table public.profiles
  drop constraint if exists check_email_length,
  add constraint check_email_length check (char_length(email) <= 100);

alter table public.profiles
  drop constraint if exists check_name_length,
  add constraint check_name_length check (char_length(full_name) <= 50);

alter table public.waitlist_subscribers
  drop constraint if exists check_waitlist_email_length,
  add constraint check_waitlist_email_length check (char_length(email) <= 100);


-- Secure PostgreSQL Server Function to verify admin status strictly on the database server
create or replace function public.is_admin(check_user_id uuid)
returns boolean as $$
begin
  return exists (
    select 1 from public.user_roles
    where user_roles.user_id = check_user_id and role = 'admin'
  );
end;
$$ language plpgsql security definer;
