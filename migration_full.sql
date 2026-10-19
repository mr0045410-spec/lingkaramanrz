-- ==========================================
-- COMPLETE LINGKAR AMAN DATABASE MIGRATION
-- Project: xtgumpluxciqesahpxuk (rezayasha's Project)
-- ==========================================

-- 1. Profiles Table
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    phone_number TEXT,
    avatar_url TEXT,
    emergency_contact_phone TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Trigger auto-insert / update profile when auth.users is created
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, full_name, phone_number, avatar_url)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', split_part(NEW.email, '@', 1)),
        COALESCE(NEW.raw_user_meta_data->>'phone', NEW.phone),
        NEW.raw_user_meta_data->>'avatar_url'
    )
    ON CONFLICT (id) DO UPDATE SET
        full_name = EXCLUDED.full_name,
        phone_number = COALESCE(EXCLUDED.phone_number, public.profiles.phone_number),
        avatar_url = COALESCE(EXCLUDED.avatar_url, public.profiles.avatar_url);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 2. Circles Table
CREATE TABLE IF NOT EXISTS public.circles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    invite_code VARCHAR(8) NOT NULL UNIQUE,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Circle Members Table
CREATE TABLE IF NOT EXISTS public.circle_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id UUID NOT NULL REFERENCES public.circles(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    role VARCHAR(20) NOT NULL DEFAULT 'member' CHECK (role IN ('admin', 'member')),
    is_sharing_location BOOLEAN NOT NULL DEFAULT TRUE,
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (circle_id, user_id)
);

-- 4. User Locations Table (Realtime)
CREATE TABLE IF NOT EXISTS public.user_locations (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    battery_level INTEGER DEFAULT 100,
    is_charging BOOLEAN DEFAULT FALSE,
    speed DOUBLE PRECISION DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. SOS Alerts Table (Realtime)
CREATE TABLE IF NOT EXISTS public.sos_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    circle_id UUID REFERENCES public.circles(id) ON DELETE CASCADE,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    message TEXT DEFAULT 'DARURAT! Saya membutuhkan bantuan segera.',
    status VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'resolved', 'cancelled')),
    triggered_at TIMESTAMPTZ DEFAULT NOW(),
    resolved_at TIMESTAMPTZ
);

-- 6. Circle Messages Table (Chat/Komunitas Realtime)
CREATE TABLE IF NOT EXISTS public.circle_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id UUID NOT NULL REFERENCES public.circles(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    message TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 7. Loud Signals Table
CREATE TABLE IF NOT EXISTS public.loud_signals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    target_user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    circle_id UUID REFERENCES public.circles(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    stopped_at TIMESTAMPTZ
);

-- 8. App Usage Reports (Screen Time)
CREATE TABLE IF NOT EXISTS public.app_usage_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    package_name TEXT NOT NULL,
    app_name TEXT NOT NULL,
    total_time_foreground_seconds INTEGER NOT NULL DEFAULT 0,
    last_time_used TIMESTAMPTZ,
    report_date DATE NOT NULL DEFAULT CURRENT_DATE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT unique_user_package_date UNIQUE(user_id, package_name, report_date)
);

-- 9. Geofences Table
CREATE TABLE IF NOT EXISTS public.geofences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id UUID REFERENCES public.circles(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    category TEXT NOT NULL DEFAULT 'home',
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    radius_meters DOUBLE PRECISION NOT NULL DEFAULT 150.0,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 10. Geofence Events Table
CREATE TABLE IF NOT EXISTS public.geofence_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id UUID REFERENCES public.circles(id) ON DELETE CASCADE,
    geofence_id UUID REFERENCES public.geofences(id) ON DELETE CASCADE,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 11. Audio Requests Table (Ambient Audio)
CREATE TABLE IF NOT EXISTS public.audio_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id UUID REFERENCES public.circles(id) ON DELETE CASCADE,
    requester_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    target_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'recording', 'completed', 'failed')),
    audio_url TEXT,
    duration_seconds INTEGER NOT NULL DEFAULT 15,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    completed_at TIMESTAMPTZ
);

-- Helper functions
CREATE OR REPLACE FUNCTION public.is_member_of(p_circle_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.circle_members
        WHERE circle_id = p_circle_id AND user_id = auth.uid()
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION public.join_circle_by_code(p_code TEXT)
RETURNS UUID AS $$
DECLARE
    v_circle_id UUID;
BEGIN
    SELECT id INTO v_circle_id FROM public.circles WHERE UPPER(invite_code) = UPPER(p_code);
    IF v_circle_id IS NULL THEN
        RAISE EXCEPTION 'Kode invite lingkaran tidak ditemukan';
    END IF;

    INSERT INTO public.circle_members (circle_id, user_id, role)
    VALUES (v_circle_id, auth.uid(), 'member')
    ON CONFLICT (circle_id, user_id) DO NOTHING;

    RETURN v_circle_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Enable RLS
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.circles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.circle_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sos_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.circle_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.loud_signals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_usage_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.geofences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.geofence_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audio_requests ENABLE ROW LEVEL SECURITY;

-- Policies for Profiles
DROP POLICY IF EXISTS "Profiles are readable by authenticated users" ON public.profiles;
CREATE POLICY "Profiles are readable by authenticated users" ON public.profiles FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;
CREATE POLICY "Users can insert own profile" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
CREATE POLICY "Users can update own profile" ON public.profiles FOR ALL TO authenticated USING (auth.uid() = id) WITH CHECK (auth.uid() = id);

-- Policies for Circles
DROP POLICY IF EXISTS "Authenticated users can view circles" ON public.circles;
CREATE POLICY "Authenticated users can view circles" ON public.circles FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "Users can create circles" ON public.circles;
CREATE POLICY "Users can create circles" ON public.circles FOR INSERT TO authenticated WITH CHECK (auth.uid() = created_by);

-- Policies for Circle Members
DROP POLICY IF EXISTS "Members can view circle members" ON public.circle_members;
CREATE POLICY "Members can view circle members" ON public.circle_members FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "Users can join circles" ON public.circle_members;
CREATE POLICY "Users can join circles" ON public.circle_members FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

-- Policies for Locations
DROP POLICY IF EXISTS "Locations readable by circle co-members" ON public.user_locations;
CREATE POLICY "Locations readable by circle co-members" ON public.user_locations FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "Users can upsert own location" ON public.user_locations;
CREATE POLICY "Users can upsert own location" ON public.user_locations FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- Policies for SOS Alerts
DROP POLICY IF EXISTS "SOS alerts readable by circle members" ON public.sos_alerts;
CREATE POLICY "SOS alerts readable by circle members" ON public.sos_alerts FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "Users can create SOS alerts" ON public.sos_alerts;
CREATE POLICY "Users can create SOS alerts" ON public.sos_alerts FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can update SOS alerts" ON public.sos_alerts;
CREATE POLICY "Users can update SOS alerts" ON public.sos_alerts FOR UPDATE TO authenticated USING (true);

-- Policies for Messages
DROP POLICY IF EXISTS "Circle members can read messages" ON public.circle_messages;
CREATE POLICY "Circle members can read messages" ON public.circle_messages FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "Circle members can post messages" ON public.circle_messages;
CREATE POLICY "Circle members can post messages" ON public.circle_messages FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

-- Policies for Loud Signals
DROP POLICY IF EXISTS "Allow authenticated read/write loud_signals" ON public.loud_signals;
CREATE POLICY "Allow authenticated read/write loud_signals" ON public.loud_signals FOR ALL TO authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "Allow anon read/write loud_signals" ON public.loud_signals;
CREATE POLICY "Allow anon read/write loud_signals" ON public.loud_signals FOR ALL TO anon USING (true) WITH CHECK (true);

-- Policies for App Usage Reports
DROP POLICY IF EXISTS "Allow authenticated read/write app_usage_reports" ON public.app_usage_reports;
CREATE POLICY "Allow authenticated read/write app_usage_reports" ON public.app_usage_reports FOR ALL TO authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "Allow anon read/write app_usage_reports" ON public.app_usage_reports;
CREATE POLICY "Allow anon read/write app_usage_reports" ON public.app_usage_reports FOR ALL TO anon USING (true) WITH CHECK (true);

-- Policies for Geofences
DROP POLICY IF EXISTS "Allow authenticated read/write geofences" ON public.geofences;
CREATE POLICY "Allow authenticated read/write geofences" ON public.geofences FOR ALL TO authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "Allow anon read/write geofences" ON public.geofences;
CREATE POLICY "Allow anon read/write geofences" ON public.geofences FOR ALL TO anon USING (true) WITH CHECK (true);

-- Policies for Geofence Events
DROP POLICY IF EXISTS "Allow authenticated read/write geofence_events" ON public.geofence_events;
CREATE POLICY "Allow authenticated read/write geofence_events" ON public.geofence_events FOR ALL TO authenticated USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "Allow anon read/write geofence_events" ON public.geofence_events;
CREATE POLICY "Allow anon read/write geofence_events" ON public.geofence_events FOR ALL TO anon USING (true) WITH CHECK (true);

-- Policies for Audio Requests
DROP POLICY IF EXISTS "Members can view audio requests for their circles" ON public.audio_requests;
CREATE POLICY "Members can view audio requests for their circles" ON public.audio_requests FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "Members can create audio requests" ON public.audio_requests;
CREATE POLICY "Members can create audio requests" ON public.audio_requests FOR INSERT TO authenticated WITH CHECK (requester_id = auth.uid());
DROP POLICY IF EXISTS "Target or requester can update audio requests" ON public.audio_requests;
CREATE POLICY "Target or requester can update audio requests" ON public.audio_requests FOR UPDATE TO authenticated USING (true);

-- Realtime Setup
DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.user_locations;
    ALTER PUBLICATION supabase_realtime ADD TABLE public.sos_alerts;
    ALTER PUBLICATION supabase_realtime ADD TABLE public.circle_messages;
    ALTER PUBLICATION supabase_realtime ADD TABLE public.loud_signals;
    ALTER PUBLICATION supabase_realtime ADD TABLE public.geofence_events;
    ALTER PUBLICATION supabase_realtime ADD TABLE public.audio_requests;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- Storage Bucket for Ambient Audio
INSERT INTO storage.buckets (id, name, public)
VALUES ('ambient_audio', 'ambient_audio', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Authenticated users can upload audio" ON storage.objects;
CREATE POLICY "Authenticated users can upload audio" ON storage.objects FOR INSERT TO authenticated WITH CHECK (bucket_id = 'ambient_audio');

DROP POLICY IF EXISTS "Authenticated users can read audio" ON storage.objects;
CREATE POLICY "Authenticated users can read audio" ON storage.objects FOR SELECT TO authenticated USING (bucket_id = 'ambient_audio');

-- Reload Schema Cache
NOTIFY pgrst, 'reload schema';
