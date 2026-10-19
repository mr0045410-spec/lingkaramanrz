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

CREATE OR REPLACE FUNCTION public.is_co_member_with(p_user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    IF p_user_id = auth.uid() THEN
        RETURN TRUE;
    END IF;
    RETURN EXISTS (
        SELECT 1 FROM public.circle_members cm1
        JOIN public.circle_members cm2 ON cm1.circle_id = cm2.circle_id
        WHERE cm1.user_id = auth.uid() AND cm2.user_id = p_user_id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION public.normalize_circle_roles(p_circle_id UUID)
RETURNS INTEGER AS $$
DECLARE
    v_updated_count INTEGER;
BEGIN
    UPDATE public.circle_members cm
    SET role = 'member'
    FROM public.circles c
    WHERE cm.circle_id = p_circle_id
      AND c.id = cm.circle_id
      AND cm.role = 'admin'
      AND (c.created_by IS NULL OR cm.user_id != c.created_by);
      
    GET DIAGNOSTICS v_updated_count = ROW_COUNT;
    RETURN v_updated_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 12. Location History Table
CREATE TABLE IF NOT EXISTS public.location_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    speed DOUBLE PRECISION DEFAULT 0.0,
    battery_level INTEGER DEFAULT 100,
    recorded_at TIMESTAMPTZ DEFAULT now()
);

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
ALTER TABLE public.location_history ENABLE ROW LEVEL SECURITY;

-- Policies for Profiles
DROP POLICY IF EXISTS "Profiles are readable by authenticated users" ON public.profiles;
DROP POLICY IF EXISTS "Profiles readable by self or circle co-members" ON public.profiles;
CREATE POLICY "Profiles readable by self or circle co-members" ON public.profiles FOR SELECT TO authenticated USING (auth.uid() = id OR is_co_member_with(id));
DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;
CREATE POLICY "Users can insert own profile" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
CREATE POLICY "Users can update own profile" ON public.profiles FOR ALL TO authenticated USING (auth.uid() = id) WITH CHECK (auth.uid() = id);

-- Policies for Circles (SELECT remains open so users can preview invite codes)
DROP POLICY IF EXISTS "Authenticated users can view circles" ON public.circles;
CREATE POLICY "Authenticated users can view circles" ON public.circles FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "Users can create circles" ON public.circles;
CREATE POLICY "Users can create circles" ON public.circles FOR INSERT TO authenticated WITH CHECK (auth.uid() = created_by);

-- Policies for Circle Members
DROP POLICY IF EXISTS "Members can view circle members" ON public.circle_members;
CREATE POLICY "Members can view circle members" ON public.circle_members FOR SELECT TO authenticated USING (is_member_of(circle_id));
DROP POLICY IF EXISTS "Users can join circles" ON public.circle_members;
CREATE POLICY "Users can join circles" ON public.circle_members FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Admins or self can update circle members" ON public.circle_members;
CREATE POLICY "Admins or self can update circle members" ON public.circle_members FOR UPDATE TO authenticated USING (auth.uid() = user_id OR EXISTS (SELECT 1 FROM public.circles WHERE id = circle_members.circle_id AND created_by = auth.uid()));

-- Policies for Locations
DROP POLICY IF EXISTS "Locations readable by circle co-members" ON public.user_locations;
CREATE POLICY "Locations readable by circle co-members" ON public.user_locations FOR SELECT TO authenticated USING (user_id = auth.uid() OR is_co_member_with(user_id));
DROP POLICY IF EXISTS "Users can upsert own location" ON public.user_locations;
CREATE POLICY "Users can upsert own location" ON public.user_locations FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- Policies for SOS Alerts
DROP POLICY IF EXISTS "SOS alerts readable by circle members" ON public.sos_alerts;
CREATE POLICY "SOS alerts readable by circle members" ON public.sos_alerts FOR SELECT TO authenticated USING (user_id = auth.uid() OR (circle_id IS NOT NULL AND is_member_of(circle_id)));
DROP POLICY IF EXISTS "Users can create SOS alerts" ON public.sos_alerts;
CREATE POLICY "Users can create SOS alerts" ON public.sos_alerts FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can update SOS alerts" ON public.sos_alerts;
DROP POLICY IF EXISTS "Users can update own or circle SOS alerts" ON public.sos_alerts;
CREATE POLICY "Users can update own or circle SOS alerts" ON public.sos_alerts FOR UPDATE TO authenticated USING (user_id = auth.uid() OR (circle_id IS NOT NULL AND is_member_of(circle_id))) WITH CHECK (user_id = auth.uid() OR (circle_id IS NOT NULL AND is_member_of(circle_id)));

-- Policies for Messages
DROP POLICY IF EXISTS "Circle members can read messages" ON public.circle_messages;
CREATE POLICY "Circle members can read messages" ON public.circle_messages FOR SELECT TO authenticated USING (is_member_of(circle_id));
DROP POLICY IF EXISTS "Circle members can post messages" ON public.circle_messages;
CREATE POLICY "Circle members can post messages" ON public.circle_messages FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id AND is_member_of(circle_id));

-- Policies for Loud Signals (SECURED, NO ANON)
DROP POLICY IF EXISTS "Allow authenticated read/write loud_signals" ON public.loud_signals;
DROP POLICY IF EXISTS "Allow anon read/write loud_signals" ON public.loud_signals;
DROP POLICY IF EXISTS "Members can view loud signals" ON public.loud_signals;
CREATE POLICY "Members can view loud signals" ON public.loud_signals FOR SELECT TO authenticated USING (sender_id = auth.uid() OR target_user_id = auth.uid() OR (circle_id IS NOT NULL AND is_member_of(circle_id)));
DROP POLICY IF EXISTS "Members can send loud signals" ON public.loud_signals;
CREATE POLICY "Members can send loud signals" ON public.loud_signals FOR INSERT TO authenticated WITH CHECK (sender_id = auth.uid() AND (circle_id IS NULL OR is_member_of(circle_id)));
DROP POLICY IF EXISTS "Target or sender can update loud signals" ON public.loud_signals;
CREATE POLICY "Target or sender can update loud signals" ON public.loud_signals FOR UPDATE TO authenticated USING (sender_id = auth.uid() OR target_user_id = auth.uid()) WITH CHECK (sender_id = auth.uid() OR target_user_id = auth.uid());

-- Policies for App Usage Reports (SECURED, NO ANON)
DROP POLICY IF EXISTS "Allow authenticated read/write app_usage_reports" ON public.app_usage_reports;
DROP POLICY IF EXISTS "Allow anon read/write app_usage_reports" ON public.app_usage_reports;
DROP POLICY IF EXISTS "Users and co-members can view app usage" ON public.app_usage_reports;
CREATE POLICY "Users and co-members can view app usage" ON public.app_usage_reports FOR SELECT TO authenticated USING (user_id = auth.uid() OR is_co_member_with(user_id));
DROP POLICY IF EXISTS "Users can insert own app usage" ON public.app_usage_reports;
CREATE POLICY "Users can insert own app usage" ON public.app_usage_reports FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Users can update own app usage" ON public.app_usage_reports;
CREATE POLICY "Users can update own app usage" ON public.app_usage_reports FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- Policies for Geofences (SECURED, NO ANON)
DROP POLICY IF EXISTS "Allow authenticated read/write geofences" ON public.geofences;
DROP POLICY IF EXISTS "Allow anon read/write geofences" ON public.geofences;
DROP POLICY IF EXISTS "Members can view geofences" ON public.geofences;
CREATE POLICY "Members can view geofences" ON public.geofences FOR SELECT TO authenticated USING (is_member_of(circle_id));
DROP POLICY IF EXISTS "Members can create geofences" ON public.geofences;
CREATE POLICY "Members can create geofences" ON public.geofences FOR INSERT TO authenticated WITH CHECK (is_member_of(circle_id));
DROP POLICY IF EXISTS "Members can update geofences" ON public.geofences;
CREATE POLICY "Members can update geofences" ON public.geofences FOR UPDATE TO authenticated USING (is_member_of(circle_id));
DROP POLICY IF EXISTS "Members can delete geofences" ON public.geofences;
CREATE POLICY "Members can delete geofences" ON public.geofences FOR DELETE TO authenticated USING (is_member_of(circle_id));

-- Policies for Geofence Events (SECURED, NO ANON)
DROP POLICY IF EXISTS "Allow authenticated read/write geofence_events" ON public.geofence_events;
DROP POLICY IF EXISTS "Allow anon read/write geofence_events" ON public.geofence_events;
DROP POLICY IF EXISTS "Members can view geofence events" ON public.geofence_events;
CREATE POLICY "Members can view geofence events" ON public.geofence_events FOR SELECT TO authenticated USING (is_member_of(circle_id));
DROP POLICY IF EXISTS "Members can insert geofence events" ON public.geofence_events;
CREATE POLICY "Members can insert geofence events" ON public.geofence_events FOR INSERT TO authenticated WITH CHECK (is_member_of(circle_id));

-- Policies for Audio Requests
DROP POLICY IF EXISTS "Members can view audio requests for their circles" ON public.audio_requests;
CREATE POLICY "Members can view audio requests for their circles" ON public.audio_requests FOR SELECT TO authenticated USING (requester_id = auth.uid() OR target_id = auth.uid() OR (circle_id IS NOT NULL AND is_member_of(circle_id)));
DROP POLICY IF EXISTS "Members can create audio requests" ON public.audio_requests;
CREATE POLICY "Members can create audio requests" ON public.audio_requests FOR INSERT TO authenticated WITH CHECK (requester_id = auth.uid() AND (circle_id IS NULL OR is_member_of(circle_id)));
DROP POLICY IF EXISTS "Target or requester can update audio requests" ON public.audio_requests;
CREATE POLICY "Target or requester can update audio requests" ON public.audio_requests FOR UPDATE TO authenticated USING (requester_id = auth.uid() OR target_id = auth.uid()) WITH CHECK (requester_id = auth.uid() OR target_id = auth.uid());

-- Policies for Location History
DROP POLICY IF EXISTS "Users can insert own location history" ON public.location_history;
CREATE POLICY "Users can insert own location history" ON public.location_history FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "Location history readable by co-members" ON public.location_history;
CREATE POLICY "Location history readable by co-members" ON public.location_history FOR SELECT TO authenticated USING (user_id = auth.uid() OR is_co_member_with(user_id));

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

