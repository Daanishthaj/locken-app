-- ==============================================================================
-- LOCKEN (KISSA FOCUS) — MASTER PRODUCTION DATABASE SCHEMA
-- ==============================================================================
-- Run this SQL script in your Supabase Dashboard:
-- 1. Open: https://supabase.com/dashboard/project/isohdbjcvluvaflmrfeg/sql
-- 2. Click "New Query", paste this entire script, and click "Run" (⌘ + Enter).
-- ==============================================================================

-- 1. PROFILES TABLE (Mirrors and extends auth.users)
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT UNIQUE NOT NULL,
    display_name TEXT,
    avatar_url TEXT,
    preferred_theme TEXT DEFAULT 'purple',
    daily_goal_minutes INTEGER DEFAULT 120,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Profiles RLS Policies
DROP POLICY IF EXISTS "Users can view their own profile" ON public.profiles;
CREATE POLICY "Users can view their own profile"
    ON public.profiles FOR SELECT
    TO authenticated
    USING (auth.uid() = id);

DROP POLICY IF EXISTS "Users can update their own profile" ON public.profiles;
CREATE POLICY "Users can update their own profile"
    ON public.profiles FOR UPDATE
    TO authenticated
    USING (auth.uid() = id);

-- 2. AUTOMATIC PROFILE CREATION TRIGGER (Google OAuth & Email Signups)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, email, display_name, avatar_url)
    VALUES (
        new.id,
        new.email,
        COALESCE(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
        new.raw_user_meta_data->>'avatar_url'
    )
    ON CONFLICT (id) DO UPDATE
    SET
        email = excluded.email,
        display_name = COALESCE(excluded.display_name, profiles.display_name),
        avatar_url = COALESCE(excluded.avatar_url, profiles.avatar_url),
        updated_at = now();
    RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT OR UPDATE ON auth.users
    FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- 3. FOCUS SESSIONS TABLE (Cloud Sync for Completed Sprints)
CREATE TABLE IF NOT EXISTS public.focus_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    goal_title TEXT NOT NULL,
    target_app TEXT DEFAULT 'Google Chrome',
    duration_minutes INTEGER NOT NULL,
    elapsed_seconds INTEGER NOT NULL,
    completed BOOLEAN DEFAULT true,
    energy_state TEXT DEFAULT 'focused',
    completion_percentage INTEGER DEFAULT 100,
    client_timestamp TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.focus_sessions ENABLE ROW LEVEL SECURITY;

-- Focus Sessions RLS Policies
DROP POLICY IF EXISTS "Users can manage their own focus sessions" ON public.focus_sessions;
CREATE POLICY "Users can manage their own focus sessions"
    ON public.focus_sessions FOR ALL
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Allow anonymous inserts with anon key for local guest users electing cloud backup
DROP POLICY IF EXISTS "Allow anon inserts for focus sessions" ON public.focus_sessions;
CREATE POLICY "Allow anon inserts for focus sessions"
    ON public.focus_sessions FOR INSERT
    TO anon
    WITH CHECK (true);

-- 4. PROJECT STUDIO NOTES TABLE
CREATE TABLE IF NOT EXISTS public.notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    content TEXT DEFAULT '',
    category TEXT DEFAULT 'Work',
    pinned BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.notes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can manage their own notes" ON public.notes;
CREATE POLICY "Users can manage their own notes"
    ON public.notes FOR ALL
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- 5. WAITLIST & EARLY ACCESS SUBSCRIBERS
CREATE TABLE IF NOT EXISTS public.waitlist_subscribers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT UNIQUE NOT NULL,
    source TEXT DEFAULT 'web_landing',
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.waitlist_subscribers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow anonymous waitlist registration" ON public.waitlist_subscribers;
CREATE POLICY "Allow anonymous waitlist registration"
    ON public.waitlist_subscribers FOR INSERT
    TO anon, authenticated
    WITH CHECK (email IS NOT NULL AND position('@' in email) > 1);

-- 6. SECURITY CONSTRAINTS & SANITIZATION
ALTER TABLE public.profiles
    DROP CONSTRAINT IF EXISTS check_email_length,
    ADD CONSTRAINT check_email_length CHECK (char_length(email) <= 100);

ALTER TABLE public.profiles
    DROP CONSTRAINT IF EXISTS check_name_length,
    ADD CONSTRAINT check_name_length CHECK (char_length(display_name) <= 50);

-- 7. PERFORMANCE INDEXES
CREATE INDEX IF NOT EXISTS idx_sessions_user_time ON public.focus_sessions(user_id, client_timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_notes_user_updated ON public.notes(user_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_profiles_email ON public.profiles(email);
