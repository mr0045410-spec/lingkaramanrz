import 'package:flutter/material.dart';
import '../services/sound_settings_service.dart';

class SoundSettingsDialog extends StatefulWidget {
  const SoundSettingsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (ctx) => const SoundSettingsDialog(),
    );
  }

  @override
  State<SoundSettingsDialog> createState() => _SoundSettingsDialogState();
}

class _SoundSettingsDialogState extends State<SoundSettingsDialog> with SingleTickerProviderStateMixin {
  final SoundSettingsService _soundService = SoundSettingsService();
  late TabController _tabController;

  String _selectedSosAlarm = 'siren_pulse';
  String _selectedLoudSignal = 'radar_beep';
  String _selectedChat = 'bubble_pop';
  String? _currentlyPreviewingId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadSettings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _soundService.stopPreview();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final sos = await _soundService.getSelectedSound(SoundSettingsService.keySosAlarm);
    final loud = await _soundService.getSelectedSound(SoundSettingsService.keyLoudSignal);
    final chat = await _soundService.getSelectedSound(SoundSettingsService.keyChat);

    if (mounted) {
      setState(() {
        _selectedSosAlarm = sos;
        _selectedLoudSignal = loud;
        _selectedChat = chat;
        _isLoading = false;
      });
    }
  }

  Future<void> _selectSound(String categoryKey, String soundId) async {
    await _soundService.setSelectedSound(categoryKey, soundId);
    setState(() {
      if (categoryKey == SoundSettingsService.keySosAlarm) {
        _selectedSosAlarm = soundId;
      } else if (categoryKey == SoundSettingsService.keyLoudSignal) {
        _selectedLoudSignal = soundId;
      } else if (categoryKey == SoundSettingsService.keyChat) {
        _selectedChat = soundId;
      }
    });
    _preview(soundId);
  }

  void _preview(String soundId) {
    if (_currentlyPreviewingId == soundId) {
      _soundService.stopPreview();
      setState(() => _currentlyPreviewingId = null);
    } else {
      setState(() => _currentlyPreviewingId = soundId);
      _soundService.previewSound(soundId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: const BoxConstraints(maxHeight: 560),
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.music_note, color: Colors.indigo.shade700, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pengaturan Nada & Ringtone',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Pilih nada dering sesuai kenyamanan',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Category Tab Bar
            TabBar(
              controller: _tabController,
              labelColor: Colors.indigo.shade700,
              unselectedLabelColor: Colors.grey.shade600,
              indicatorColor: Colors.indigo.shade700,
              labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              tabs: const [
                Tab(icon: Icon(Icons.crisis_alert, size: 18), text: 'Alarm SOS'),
                Tab(icon: Icon(Icons.volume_up, size: 18), text: 'Sinyal Suara'),
                Tab(icon: Icon(Icons.chat, size: 18), text: 'Chat'),
              ],
            ),

            const Divider(height: 1),

            // Tab Views
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        // 1. SOS Alarm Tab
                        _buildSoundList(
                          options: SoundSettingsService.sosAlarmOptions,
                          selectedId: _selectedSosAlarm,
                          categoryKey: SoundSettingsService.keySosAlarm,
                          categoryNotice: 'Nada ini berbunyi keras saat tombol SOS atau Mode HP Hilang aktif.',
                        ),

                        // 2. Loud Signal Tab
                        _buildSoundList(
                          options: SoundSettingsService.loudSignalOptions,
                          selectedId: _selectedLoudSignal,
                          categoryKey: SoundSettingsService.keyLoudSignal,
                          categoryNotice: 'Nada ini diputar saat keluarga mengirim sinyal keras pencarian posisi.',
                        ),

                        // 3. Chat Notification Tab
                        _buildSoundList(
                          options: SoundSettingsService.chatOptions,
                          selectedId: _selectedChat,
                          categoryKey: SoundSettingsService.keyChat,
                          categoryNotice: 'Nada ini berbunyi saat ada pesan masuk di obrolan lingkaran.',
                        ),
                      ],
                    ),
            ),

            const Divider(height: 1),

            // Footer
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Simpan Pengaturan'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSoundList({
    required List<SoundOption> options,
    required String selectedId,
    required String categoryKey,
    required String categoryNotice,
  }) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.amber.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: Colors.amber.shade900),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  categoryNotice,
                  style: TextStyle(fontSize: 11, color: Colors.amber.shade900),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ...options.map((opt) {
          final isSelected = opt.id == selectedId;
          final isPreviewing = _currentlyPreviewingId == opt.id;

          return Card(
            elevation: isSelected ? 2 : 0,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: isSelected ? Colors.indigo.shade600 : Colors.grey.shade200,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            color: isSelected ? Colors.indigo.shade50.withValues(alpha: 0.4) : Colors.white,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              onTap: () => _selectSound(categoryKey, opt.id),
              leading: Icon(
                isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: isSelected ? Colors.indigo.shade700 : Colors.grey,
                size: 20,
              ),
              title: Text(
                opt.name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected ? Colors.indigo.shade900 : Colors.black87,
                ),
              ),
              subtitle: Text(
                opt.description,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
              trailing: IconButton(
                icon: Icon(
                  isPreviewing ? Icons.stop_circle : Icons.play_circle_fill,
                  color: isPreviewing ? Colors.red : Colors.indigo.shade600,
                  size: 28,
                ),
                tooltip: isPreviewing ? 'Hentikan Contoh' : 'Dengarkan Contoh',
                onPressed: () => _preview(opt.id),
              ),
            ),
          );
        }),
      ],
    );
  }
}
