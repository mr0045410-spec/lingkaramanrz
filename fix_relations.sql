-- 1. Add foreign keys to public.profiles so PostgREST can embed profiles(*)
ALTER TABLE public.circle_members 
    DROP CONSTRAINT IF EXISTS fk_circle_members_profile,
    ADD CONSTRAINT fk_circle_members_profile FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

ALTER TABLE public.sos_alerts 
    DROP CONSTRAINT IF EXISTS fk_sos_alerts_profile,
    ADD CONSTRAINT fk_sos_alerts_profile FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

ALTER TABLE public.circle_messages 
    DROP CONSTRAINT IF EXISTS fk_circle_messages_profile,
    ADD CONSTRAINT fk_circle_messages_profile FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- 2. Allow authenticated users to view circles (e.g. to see name or lookup invite code)
DROP POLICY IF EXISTS "Members can view their circles" ON public.circles;
DROP POLICY IF EXISTS "Authenticated users can view circles" ON public.circles;
CREATE POLICY "Authenticated users can view circles" ON public.circles
    FOR SELECT TO authenticated USING (true);

-- 3. Notify PostgREST to reload schema cache
NOTIFY pgrst, 'reload schema';
