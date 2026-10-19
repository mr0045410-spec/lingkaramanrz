import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/location_service.dart';
import '../services/supabase_service.dart';
import '../widgets/sound_settings_dialog.dart';

class ProfileScreen extends StatefulWidget {
  final VoidCallback onSignedOut;
  const ProfileScreen({super.key, required this.onSignedOut});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final SupabaseService _supa = SupabaseService();
  final LocationService _locService = LocationService();

  UserProfile? _profile;
  bool _isLoading = false;
  bool _isEditing = false;
  bool _isLocationSharing = true;

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emergencyCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _isLocationSharing = _locService.isTracking;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emergencyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    final prof = await _supa.getProfile();
    if (mounted) {
      setState(() {
        _profile = prof;
        _nameCtrl.text = prof?.fullName ?? '';
        _phoneCtrl.text = prof?.phoneNumber ?? '';
        _emergencyCtrl.text = prof?.emergencyContactPhone ?? '';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _isLoading = true);
    try {
      await _supa.updateProfile(
        fullName: _nameCtrl.text.trim(),
        phoneNumber: _phoneCtrl.text.trim(),
        emergencyContactPhone: _emergencyCtrl.text.trim(),
      );
      await _loadProfile();
      setState(() => _isEditing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil berhasil diperbarui')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal simpan profil: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Keluar Akun'),
        content: const Text('Apakah Anda yakin ingin keluar dari akun?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _locService.stopTracking();
      await _supa.signOut();
      widget.onSignedOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _supa.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil & Pengaturan'),
        actions: [
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => setState(() => _isEditing = true),
              tooltip: 'Edit Profil',
            )
          else
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _saveProfile,
              tooltip: 'Simpan',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  // User Avatar
                  Center(
                    child: CircleAvatar(
                      radius: 46,
                      backgroundColor: Colors.indigo.shade100,
                      child: Text(
                        (_profile?.fullName.isNotEmpty == true)
                            ? _profile!.fullName[0].toUpperCase()
                            : '?',
                        style: TextStyle(fontSize: 36, color: Colors.indigo.shade900, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _profile?.fullName ?? 'Pengguna',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    user?.email ?? '',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  const SizedBox(height: 24),

                  // Profile Form / Details
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Informasi Kontak',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(height: 16),
                          if (_isEditing) ...[
                            TextField(
                              controller: _nameCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Nama Lengkap',
                                prefixIcon: Icon(Icons.person_outline),
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _phoneCtrl,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'Nomor WhatsApp / HP',
                                prefixIcon: Icon(Icons.phone_outlined),
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _emergencyCtrl,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'Nomor Kontak Darurat (Keluarga)',
                                prefixIcon: Icon(Icons.contact_phone_outlined),
                                helperText: 'Nomor yang dipanggil cepat saat tombol SOS ditekan',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ] else ...[
                            ListTile(
                              leading: const Icon(Icons.person_outline, color: Colors.indigo),
                              title: const Text('Nama Lengkap', style: TextStyle(fontSize: 12, color: Colors.grey)),
                              subtitle: Text(_profile?.fullName ?? '-', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                            ),
                            ListTile(
                              leading: const Icon(Icons.phone_outlined, color: Colors.indigo),
                              title: const Text('Nomor WhatsApp / HP', style: TextStyle(fontSize: 12, color: Colors.grey)),
                              subtitle: Text(_profile?.phoneNumber ?? '-', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                            ),
                            ListTile(
                              leading: const Icon(Icons.contact_phone_outlined, color: Colors.red),
                              title: const Text('Kontak Darurat Prioritas', style: TextStyle(fontSize: 12, color: Colors.grey)),
                              subtitle: Text(
                                _profile?.emergencyContactPhone ?? 'Belum diatur',
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.red),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Location Tracking Toggle Card
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: SwitchListTile(
                      secondary: const Icon(Icons.my_location, color: Colors.indigo),
                      title: const Text('Berbagi Lokasi Realtime', style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text('Kirim koordinat GPS dan level baterai ke lingkaran'),
                      value: _isLocationSharing,
                      onChanged: (val) {
                        setState(() => _isLocationSharing = val);
                        if (val) {
                          _locService.startTracking();
                        } else {
                          _locService.stopTracking();
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Sound & Ringtone Settings Card
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: ListTile(
                      leading: const Icon(Icons.music_note, color: Colors.indigo),
                      title: const Text('Pengaturan Nada & Ringtone', style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text('Atur nada Alarm SOS, Sinyal Suara, dan Chat'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => SoundSettingsDialog.show(context),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Sign Out Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.logout),
                      label: const Text('Keluar dari Akun', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: _signOut,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
