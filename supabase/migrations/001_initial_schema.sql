-- ============================================
-- Supabase Database Migration
-- Family Tracker App
-- ============================================
-- Run this SQL in Supabase SQL Editor:
-- https://supabase.com/dashboard/project/mftfgumaftkhjwlavpxh/sql

-- ────────────────────────────────────────────
-- 1. USERS TABLE
-- ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    photo_url TEXT,
    family_id TEXT NOT NULL,
    is_location_sharing BOOLEAN DEFAULT FALSE,
    last_seen TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- Policies: authenticated users can read all users, write own data
CREATE POLICY "Users can view all users"
    ON public.users FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "Users can insert own profile"
    ON public.users FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update own profile"
    ON public.users FOR UPDATE
    TO authenticated
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

-- Allow service role to update family_id when adding members
CREATE POLICY "Authenticated users can update family members"
    ON public.users FOR UPDATE
    TO authenticated
    USING (true)
    WITH CHECK (true);

-- ────────────────────────────────────────────
-- 2. LOCATIONS TABLE
-- ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.locations (
    user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    timestamp TIMESTAMPTZ DEFAULT NOW(),
    accuracy DOUBLE PRECISION,
    address TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Authenticated users can view all locations"
    ON public.locations FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "Users can insert own location"
    ON public.locations FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own location"
    ON public.locations FOR UPDATE
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- ────────────────────────────────────────────
-- 3. FAMILIES TABLE
-- ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.families (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    created_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    members TEXT[] DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.families ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Authenticated users can view families"
    ON public.families FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "Authenticated users can create families"
    ON public.families FOR INSERT
    TO authenticated
    WITH CHECK (true);

CREATE POLICY "Authenticated users can update families"
    ON public.families FOR UPDATE
    TO authenticated
    USING (true)
    WITH CHECK (true);

-- ────────────────────────────────────────────
-- 4. SAFE ZONES TABLE
-- ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.safe_zones (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    radius_meters DOUBLE PRECISION DEFAULT 100.0,
    family_id TEXT REFERENCES public.families(id) ON DELETE CASCADE,
    notify_on_enter BOOLEAN DEFAULT TRUE,
    notify_on_exit BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.safe_zones ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Authenticated users can view safe zones"
    ON public.safe_zones FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "Authenticated users can create safe zones"
    ON public.safe_zones FOR INSERT
    TO authenticated
    WITH CHECK (true);

CREATE POLICY "Authenticated users can update safe zones"
    ON public.safe_zones FOR UPDATE
    TO authenticated
    USING (true)
    WITH CHECK (true);

CREATE POLICY "Authenticated users can delete safe zones"
    ON public.safe_zones FOR DELETE
    TO authenticated
    USING (true);

-- ────────────────────────────────────────────
-- 5. INDEXES
-- ────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_users_family_id ON public.users(family_id);
CREATE INDEX IF NOT EXISTS idx_users_email ON public.users(email);
CREATE INDEX IF NOT EXISTS idx_locations_user_id ON public.locations(user_id);
CREATE INDEX IF NOT EXISTS idx_safe_zones_family_id ON public.safe_zones(family_id);

-- ────────────────────────────────────────────
-- 6. ENABLE REALTIME
-- ────────────────────────────────────────────
-- Enable realtime for all tables
ALTER PUBLICATION supabase_realtime ADD TABLE public.users;
ALTER PUBLICATION supabase_realtime ADD TABLE public.locations;
ALTER PUBLICATION supabase_realtime ADD TABLE public.families;
ALTER PUBLICATION supabase_realtime ADD TABLE public.safe_zones;

-- ────────────────────────────────────────────
-- 7. FUNCTIONS (auto-update timestamps)
-- ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_locations_updated_at
    BEFORE UPDATE ON public.locations
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at();
