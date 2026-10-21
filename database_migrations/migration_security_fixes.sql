-- ====================================================================
-- SKRIP MIGRASI PERBAIKAN KEAMANAN & PRIVASI LINGKARAMAN (REVISI TAHAP 2)
-- Berkas: migration_security_fixes.sql
-- Status: Proposal Terevisi untuk Ditinjau (Review Before Apply)
-- Target Instance: uwxecnbeqeysnlzwdcha (dan mirror lingkungan dev)
-- ====================================================================

-- --------------------------------------------------------------------
-- 1. PERBAIKAN SEC-01: Mengunci Tabel Circles (Cegah Pencurian Invite Code)
-- --------------------------------------------------------------------
-- Menutup SELECT terbuka (USING true).
-- Hanya pembuat lingkaran atau anggota aktif yang dapat melihat data lingkaran.
DROP POLICY IF EXISTS "Authenticated users can view circles" ON public.circles;
DROP POLICY IF EXISTS "Members or creators can view circles" ON public.circles;

CREATE POLICY "Members or creators can view circles" ON public.circles 
    FOR SELECT TO authenticated 
    USING (
        created_by = auth.uid() 
        OR public.is_member_of(id)
    );

-- --------------------------------------------------------------------
-- 2. PERBAIKAN SEC-03: Mencegah Eskalasi Peran pada circle_members (A2)
-- --------------------------------------------------------------------
-- Pengguna biasa TIDAK BOLEH bisa mengangkat dirinya sendiri menjadi admin.
-- User biasa hanya boleh mengubah is_sharing_location miliknya sendiri.
DROP POLICY IF EXISTS "Admins or self can update circle members" ON public.circle_members;
DROP POLICY IF EXISTS "Members can update own location sharing" ON public.circle_members;
DROP POLICY IF EXISTS "Admins or creators can update circle members" ON public.circle_members;
DROP POLICY IF EXISTS "Users can leave or admins can remove members" ON public.circle_members;

-- 2a. Anggota biasa hanya boleh memperbarui status berbagi lokasi miliknya
CREATE POLICY "Members can update own location sharing" ON public.circle_members
    FOR UPDATE TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id AND role = 'member');

-- 2b. Hanya creator circle atau admin yang berhak mengubah role atau status anggota lain
-- Catatan Revisi A2: Menambahkan WITH CHECK eksplisit (mirror dari USING)
CREATE POLICY "Admins or creators can update circle members" ON public.circle_members
    FOR UPDATE TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.circles c
            WHERE c.id = circle_members.circle_id
              AND (
                  c.created_by = auth.uid()
                  OR EXISTS (
                      SELECT 1 FROM public.circle_members cm
                      WHERE cm.circle_id = circle_members.circle_id
                        AND cm.user_id = auth.uid()
                        AND cm.role = 'admin'
                  )
              )
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.circles c
            WHERE c.id = circle_members.circle_id
              AND (
                  c.created_by = auth.uid()
                  OR EXISTS (
                      SELECT 1 FROM public.circle_members cm
                      WHERE cm.circle_id = circle_members.circle_id
                        AND cm.user_id = auth.uid()
                        AND cm.role = 'admin'
                  )
              )
        )
    );

-- 2c. Tambahkan hak DELETE: Memungkinkan user keluar lingkaran atau admin mengeluarkan member
CREATE POLICY "Users can leave or admins can remove members" ON public.circle_members
    FOR DELETE TO authenticated
    USING (
        auth.uid() = user_id
        OR EXISTS (
            SELECT 1 FROM public.circles c
            WHERE c.id = circle_members.circle_id
              AND (
                  c.created_by = auth.uid()
                  OR EXISTS (
                      SELECT 1 FROM public.circle_members cm
                      WHERE cm.circle_id = circle_members.circle_id
                        AND cm.user_id = auth.uid()
                        AND cm.role = 'admin'
                  )
              )
        )
    );

-- --------------------------------------------------------------------
-- 3. PERBAIKAN SEC-04: Menghormati Sakelar is_sharing_location
-- --------------------------------------------------------------------
-- Fungsi terpusat untuk memvalidasi hak melihat lokasi target
CREATE OR REPLACE FUNCTION public.can_view_location_of(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Lokasi milik sendiri selalu boleh dilihat
    IF p_user_id = auth.uid() THEN
        RETURN TRUE;
    END IF;

    -- Pengecualian darurat: Jika target sedang dalam status SOS aktif, lokasi selalu diizinkan
    IF EXISTS (
        SELECT 1 FROM public.sos_alerts 
        WHERE user_id = p_user_id AND status = 'active'
    ) THEN
        RETURN TRUE;
    END IF;

    -- Pengguna hanya boleh melihat lokasi jika berada dalam lingkaran yang sama
    -- DAN target secara sukarela mengaktifkan is_sharing_location = TRUE
    RETURN EXISTS (
        SELECT 1 FROM public.circle_members cm_viewer
        JOIN public.circle_members cm_target ON cm_viewer.circle_id = cm_target.circle_id
        WHERE cm_viewer.user_id = auth.uid() 
          AND cm_target.user_id = p_user_id
          AND cm_target.is_sharing_location = TRUE
    );
END;
$$;

-- Terapkan ke tabel user_locations
DROP POLICY IF EXISTS "Locations readable by circle co-members" ON public.user_locations;
DROP POLICY IF EXISTS "Locations readable by authorized co-members" ON public.user_locations;

CREATE POLICY "Locations readable by authorized co-members" ON public.user_locations
    FOR SELECT TO authenticated
    USING (public.can_view_location_of(user_id));

-- Terapkan ke tabel location_history
DROP POLICY IF EXISTS "Location history readable by co-members" ON public.location_history;
DROP POLICY IF EXISTS "Location history readable by authorized co-members" ON public.location_history;

CREATE POLICY "Location history readable by authorized co-members" ON public.location_history
    FOR SELECT TO authenticated
    USING (public.can_view_location_of(user_id));

-- Izinkan pengguna menghapus riwayat lokasinya sendiri (Hak Privasi / GDPR)
DROP POLICY IF EXISTS "Users can delete own location history" ON public.location_history;
CREATE POLICY "Users can delete own location history" ON public.location_history
    FOR DELETE TO authenticated
    USING (auth.uid() = user_id);

-- --------------------------------------------------------------------
-- 4. PERBAIKAN SEC-05: Mengunci remote_commands dari Injeksi Sembarangan
-- --------------------------------------------------------------------
DROP POLICY IF EXISTS "Circle members can manage remote commands" ON public.remote_commands;
DROP POLICY IF EXISTS "Users can view relevant remote commands" ON public.remote_commands;
DROP POLICY IF EXISTS "Authorized members can send remote commands" ON public.remote_commands;
DROP POLICY IF EXISTS "Target can update status of remote commands" ON public.remote_commands;

CREATE POLICY "Users can view relevant remote commands" ON public.remote_commands
    FOR SELECT TO authenticated
    USING (
        sender_id = auth.uid()
        OR target_user_id = auth.uid()
        OR (circle_id IS NOT NULL AND public.is_member_of(circle_id))
    );

CREATE POLICY "Authorized members can send remote commands" ON public.remote_commands
    FOR INSERT TO authenticated
    WITH CHECK (
        sender_id = auth.uid()
        AND circle_id IS NOT NULL
        AND public.is_member_of(circle_id)
        AND (
            -- Perintah penguncian untuk diri sendiri
            target_user_id = auth.uid()
            -- ATAU dikirim oleh creator/admin lingkaran kepada anggota lingkaran yang sama
            OR EXISTS (
                SELECT 1 FROM public.circles c
                WHERE c.id = remote_commands.circle_id
                  AND (
                      c.created_by = auth.uid()
                      OR EXISTS (
                          SELECT 1 FROM public.circle_members cm
                          WHERE cm.circle_id = remote_commands.circle_id
                            AND cm.user_id = auth.uid()
                            AND cm.role = 'admin'
                      )
                  )
            )
        )
        AND EXISTS (
            SELECT 1 FROM public.circle_members cm_target
            WHERE cm_target.circle_id = remote_commands.circle_id
              AND cm_target.user_id = remote_commands.target_user_id
        )
    );

CREATE POLICY "Target can update status of remote commands" ON public.remote_commands
    FOR UPDATE TO authenticated
    USING (target_user_id = auth.uid() OR sender_id = auth.uid())
    WITH CHECK (target_user_id = auth.uid() OR sender_id = auth.uid());

-- --------------------------------------------------------------------
-- 5. PERBAIKAN SEC-06: Mencegah Sinyal Keras & Sadap Audio Lintas Lingkaran
-- --------------------------------------------------------------------
-- Hapus klausa 'circle_id IS NULL'
DROP POLICY IF EXISTS "Members can send loud signals" ON public.loud_signals;
CREATE POLICY "Members can send loud signals" ON public.loud_signals 
    FOR INSERT TO authenticated 
    WITH CHECK (
        sender_id = auth.uid() 
        AND circle_id IS NOT NULL 
        AND public.is_member_of(circle_id)
        AND EXISTS (
            SELECT 1 FROM public.circle_members cm
            WHERE cm.circle_id = loud_signals.circle_id
              AND cm.user_id = loud_signals.target_user_id
        )
    );

DROP POLICY IF EXISTS "Members can create audio requests" ON public.audio_requests;
CREATE POLICY "Members can create audio requests" ON public.audio_requests 
    FOR INSERT TO authenticated 
    WITH CHECK (
        requester_id = auth.uid() 
        AND circle_id IS NOT NULL 
        AND public.is_member_of(circle_id)
        AND EXISTS (
            SELECT 1 FROM public.circle_members cm
            WHERE cm.circle_id = audio_requests.circle_id
              AND cm.user_id = audio_requests.target_id
        )
    );

-- --------------------------------------------------------------------
-- 6. PERBAIKAN SEC-07: Batasi DELETE Geofences Hanya untuk Admin/Creator
-- --------------------------------------------------------------------
DROP POLICY IF EXISTS "Members can delete geofences" ON public.geofences;
DROP POLICY IF EXISTS "Admins or creators can delete geofences" ON public.geofences;

CREATE POLICY "Admins or creators can delete geofences" ON public.geofences 
    FOR DELETE TO authenticated 
    USING (
        created_by = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.circles c
            WHERE c.id = geofences.circle_id
              AND (
                  c.created_by = auth.uid()
                  OR EXISTS (
                      SELECT 1 FROM public.circle_members cm
                      WHERE cm.circle_id = geofences.circle_id
                        AND cm.user_id = auth.uid()
                        AND cm.role = 'admin'
                  )
              )
        )
    );

-- --------------------------------------------------------------------
-- 7. PERBAIKAN SEC-02 & REVISI A1: Mengunci Storage Bucket ambient_audio
-- --------------------------------------------------------------------
UPDATE storage.buckets 
SET public = false 
WHERE id = 'ambient_audio';

DROP POLICY IF EXISTS "Authenticated users can upload audio" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can read audio" ON storage.objects;
DROP POLICY IF EXISTS "Users can upload to own storage folder" ON storage.objects;
DROP POLICY IF EXISTS "Authorized users can read storage objects" ON storage.objects;

-- Upload dibatasi hanya ke folder ID masing-masing: <user_id>/...
CREATE POLICY "Users can upload to own storage folder" ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'ambient_audio'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

-- Catatan Revisi A1: Menambahkan guard regex UUID sebelum casting ::uuid
-- Mencegah query crash pada file legacy dengan prefix non-UUID seperti 'intruder_photos/...'
CREATE POLICY "Authorized users can read storage objects" ON storage.objects
    FOR SELECT TO authenticated
    USING (
        bucket_id = 'ambient_audio'
        AND (
            (storage.foldername(name))[1] = auth.uid()::text
            OR (
                (storage.foldername(name))[1] ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                AND public.is_co_member_with(((storage.foldername(name))[1])::uuid)
            )
        )
    );

-- --------------------------------------------------------------------
-- 8. FUNGSI KELUAR LINGKARAN & PEMBERSIHAN DATA PRIBADI (DENGAN CATATAN A3)
-- --------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.leave_circle(p_circle_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'unauthorized';
    END IF;

    -- Hapus keanggotaan pengguna di lingkaran tersebut
    DELETE FROM public.circle_members
    WHERE circle_id = p_circle_id AND user_id = auth.uid();
END;
$$;

GRANT EXECUTE ON FUNCTION public.leave_circle(UUID) TO authenticated;

-- ====================================================================
-- CATATAN REVISI A3: KETERBATASAN DIKETAHUI PADA delete_my_account()
-- ====================================================================
-- 1. Fungsi SQL di bawah ini HANYA menghapus data di skema public (profiles,
--    user_locations, location_history, user_devices, dll).
-- 2. Baris auth.users di skema auth TIDAK DAPAT dihapus melalui kueri SQL
--    pengguna/SECURITY DEFINER biasa karena dikelola eksklusif oleh GoTrue.
--    Jika user login kembali, trigger handle_new_user() akan membuat profil baru.
-- 3. File fisik pada bucket Storage (ambient_audio) tidak dihapus otomatis.
-- 4. TINDAK LANJUT WAJIB: Untuk penghapusan akun penuh sesuai standar hukum
--    UU PDP / GDPR, diperlukan Edge Function backend dengan service_role key
--    (supabase.auth.admin.deleteUser(uid)) serta pembersihan storage.objects.
-- ====================================================================
CREATE OR REPLACE FUNCTION public.delete_my_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'unauthorized';
    END IF;

    -- 1. Bersihkan lingkaran yang dibuat jika tidak ada anggota lain
    DELETE FROM public.circles 
    WHERE created_by = v_uid 
      AND id NOT IN (SELECT circle_id FROM public.circle_members WHERE user_id != v_uid);

    -- 2. Bersihkan profil (Cascades ke circle_members, sos_alerts, messages, dsb)
    DELETE FROM public.profiles WHERE id = v_uid;
    
    -- 3. Hapus koordinat realtime & linimasa perjalanan
    DELETE FROM public.user_locations WHERE user_id = v_uid;
    DELETE FROM public.location_history WHERE user_id = v_uid;
    DELETE FROM public.user_devices WHERE user_id = v_uid;
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_my_account() TO authenticated;

-- Refresh cache PostgREST
NOTIFY pgrst, 'reload schema';
