-- 1. Create Storage Bucket for Ambient Audio
INSERT INTO storage.buckets (id, name, public)
VALUES ('ambient_audio', 'ambient_audio', true)
ON CONFLICT (id) DO NOTHING;

-- Storage Policy: Authenticated users can upload and read audio clips
DROP POLICY IF EXISTS "Authenticated users can upload audio" ON storage.objects;
CREATE POLICY "Authenticated users can upload audio" ON storage.objects
    FOR INSERT TO authenticated WITH CHECK (bucket_id = 'ambient_audio');

DROP POLICY IF EXISTS "Authenticated users can read audio" ON storage.objects;
CREATE POLICY "Authenticated users can read audio" ON storage.objects
    FOR SELECT TO authenticated USING (bucket_id = 'ambient_audio');

-- 2. Create audio_requests Table
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

-- Enable RLS on audio_requests
ALTER TABLE public.audio_requests ENABLE ROW LEVEL SECURITY;

-- Policies for audio_requests
DROP POLICY IF EXISTS "Members can view audio requests for their circles" ON public.audio_requests;
CREATE POLICY "Members can view audio requests for their circles" ON public.audio_requests
    FOR SELECT TO authenticated USING (
        requester_id = auth.uid() OR target_id = auth.uid() OR public.is_member_of(circle_id)
    );

DROP POLICY IF EXISTS "Members can create audio requests" ON public.audio_requests;
CREATE POLICY "Members can create audio requests" ON public.audio_requests
    FOR INSERT TO authenticated WITH CHECK (requester_id = auth.uid());

DROP POLICY IF EXISTS "Target or requester can update audio requests" ON public.audio_requests;
CREATE POLICY "Target or requester can update audio requests" ON public.audio_requests
    FOR UPDATE TO authenticated USING (
        target_id = auth.uid() OR requester_id = auth.uid()
    );

-- Add to Realtime Publication
DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.audio_requests;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;
