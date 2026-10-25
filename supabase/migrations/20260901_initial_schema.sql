-- ==============================================================================
-- LOCKEN — SUPABASE DATABASE ARCHITECTURE & SCHEMA
-- Production Schema with Row-Level Security (RLS) & Offline-Safe Operations
-- ==============================================================================

-- 1. WAITLIST & EARLY ACCESS SUBSCRIBERS
CREATE TABLE IF NOT EXISTS public.waitlist_subscribers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT UNIQUE NOT NULL,
    source TEXT DEFAULT 'web_landing',
    referrer TEXT,
    ip_country TEXT,
    is_verified BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS for waitlist
ALTER TABLE public.waitlist_subscribers ENABLE ROW LEVEL SECURITY;

-- Allow anonymous visitors to subscribe to the waitlist
CREATE POLICY "Allow anonymous waitlist registration"
    ON public.waitlist_subscribers
    FOR INSERT
    TO anon, authenticated
    WITH CHECK (email IS NOT NULL AND position('@' in email) > 1);

-- Restrict waitlist reading to authenticated service roles only
CREATE POLICY "Allow service role waitlist reading"
    ON public.waitlist_subscribers
    FOR SELECT
    TO service_role
    USING (true);

-- 2. USER PROFILES & SETTINGS
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

CREATE POLICY "Users can view their own profile"
    ON public.profiles
    FOR SELECT
    TO authenticated
    USING (auth.uid() = id);

CREATE POLICY "Users can update their own profile"
    ON public.profiles
    FOR UPDATE
    TO authenticated
    USING (auth.uid() = id);

-- 3. FOCUS SESSIONS (Optional Cloud Sync)
CREATE TABLE IF NOT EXISTS public.focus_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    goal_title TEXT NOT NULL,
    target_app TEXT DEFAULT 'Xcode',
    duration_minutes INTEGER NOT NULL,
    elapsed_seconds INTEGER NOT NULL,
    completed BOOLEAN DEFAULT true,
    energy_state TEXT,
    completion_percentage INTEGER DEFAULT 100,
    client_timestamp TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.focus_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage their own focus sessions"
    ON public.focus_sessions
    FOR ALL
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- 4. PROJECT STUDIO NOTES (Encrypted/Encapsulated Markdown)
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

CREATE POLICY "Users can manage their own notes"
    ON public.notes
    FOR ALL
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Indexes for lightning fast queries
CREATE INDEX IF NOT EXISTS idx_waitlist_email ON public.waitlist_subscribers(email);
CREATE INDEX IF NOT EXISTS idx_sessions_user_time ON public.focus_sessions(user_id, client_timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_notes_user_updated ON public.notes(user_id, updated_at DESC);
