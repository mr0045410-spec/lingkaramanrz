import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/geofence_service.dart';
import '../services/supabase_service.dart';
import '../widgets/geofence_map_picker.dart';
import '../widgets/member_detail_sheet.dart';
import '../theme/app_theme.dart';
import '../widgets/app_components.dart';
import '../services/member_nickname_service.dart';

import '../services/geofence_schedule_service.dart';

class CircleScreen extends StatefulWidget {
  final List<CircleModel> circles;
  final CircleModel? selectedCircle;
  final Function(CircleModel) onCircleSelected;
  final VoidCallback onRefreshCircles;

  const CircleScreen({
    super.key,
    required this.circles,
    required this.selectedCircle,
    required this.onCircleSelected,
    required this.onRefreshCircles,
  });

  @override
  State<CircleScreen> createState() => _CircleScreenState();
}

class _CircleScreenState extends State<CircleScreen> with SingleTickerProviderStateMixin {
  final SupabaseService _supa = SupabaseService();
  final GeofenceService _geofenceService = GeofenceService();
  late TabController _tabController;
  List<CircleMember> _members = [];
  List<GeofenceModel> _geofences = [];
  List<GeofenceEventModel> _geofenceEvents = [];
  final GeofenceScheduleService _scheduleService = GeofenceScheduleService();
  Map<String, GeofenceSchedule> _schedules = {};
  bool _isLoading = false;

  void _onNicknamesChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _showEditNicknameDialog(String userId, String? currentNickname, String fullName) async {
    final ctrl = TextEditingController(text: currentNickname ?? '');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.badge_outlined, color: Colors.indigo),
            SizedBox(width: 8),
            Expanded(
              child: Text('Nama Panggilan Anggota', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ganti nama tampilan untuk $fullName (hanya terlihat oleh Anda).',
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nama Panggilan',
                hintText: 'Misal: Ayah, Ibu, Kakak, Adek',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          if (currentNickname != null && currentNickname.isNotEmpty)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () async {
                Navigator.pop(ctx);
                await MemberNicknameService.instance.removeNickname(userId);
                if (mounted) setState(() {});
              },
              child: const Text('Reset Asli'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final val = ctrl.text.trim();
              Navigator.pop(ctx);
              if (val.isEmpty) {
                await MemberNicknameService.instance.removeNickname(userId);
              } else {
                await MemberNicknameService.instance.setNickname(userId, val);
              }
              if (mounted) setState(() {});
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    MemberNicknameService.instance.addListener(_onNicknamesChanged);
    if (widget.selectedCircle != null) {
      _loadData(widget.selectedCircle!.id);
    }
  }

  @override
  void didUpdateWidget(covariant CircleScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedCircle?.id != oldWidget.selectedCircle?.id) {
      if (widget.selectedCircle != null) {
        _loadData(widget.selectedCircle!.id);
      }
    }
  }

  @override
  void dispose() {
    MemberNicknameService.instance.removeListener(_onNicknamesChanged);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData(String circleId) async {
    setState(() => _isLoading = true);
    try {
      final members = await _supa.getCircleMembers(circleId);
      final geofences = await _geofenceService.getGeofences(circleId);
      final events = await _geofenceService.getRecentEvents(circleId);
      final Map<String, GeofenceSchedule> loadedSchedules = {};
      for (final g in geofences) {
        loadedSchedules[g.id] = await _scheduleService.getSchedule(g.id);
      }
      if (mounted) {
        setState(() {
          _members = members;
          _geofences = geofences;
          _geofenceEvents = events;
          _schedules = loadedSchedules;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _showCreateCircleDialog() async {
    final nameCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Buat Lingkaran Baru'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nama Lingkaran',
            hintText: 'Misal: Keluarga Cemara, Teman Kantor',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              try {
                final circle = await _supa.createCircle(nameCtrl.text.trim());
                widget.onRefreshCircles();
                widget.onCircleSelected(circle);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Lingkaran "${circle.name}" berhasil dibuat!')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Gagal membuat lingkaran: $e')),
                  );
                }
              }
            },
            child: const Text('Buat'),
          ),
        ],
      ),
    );
  }

  Future<void> _showJoinCircleDialog() async {
    final codeCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gabung Lingkaran'),
        content: TextField(
          controller: codeCtrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Kode Undangan (6 Digit)',
            hintText: 'Misal: ABC123',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              if (codeCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              try {
                await _supa.joinCircleByCode(codeCtrl.text.trim());
                widget.onRefreshCircles();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Berhasil bergabung ke lingkaran!')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString().replaceAll('Exception:', '').trim())),
                  );
                }
              }
            },
            child: const Text('Gabung'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final circle = widget.selectedCircle;

    return Scaffold(
      appBar: AppBar(
        title: Text(circle != null ? circle.name : 'Lingkaran Saya'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Segarkan',
            onPressed: () {
              if (circle != null) {
                _loadData(circle.id);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.group_add),
            tooltip: 'Gabung Lingkaran',
            onPressed: _showJoinCircleDialog,
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Buat Lingkaran',
            onPressed: _showCreateCircleDialog,
          ),
        ],
        bottom: circle != null
            ? TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(icon: Icon(Icons.people), text: 'Anggota'),
                  Tab(icon: Icon(Icons.fmd_good_outlined), text: 'Zona Aman'),
                ],
              )
            : null,
      ),
      body: circle == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.group_off_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'Anda belum memiliki atau memilih lingkaran',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Buat Lingkaran'),
                        onPressed: _showCreateCircleDialog,
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.login),
                        label: const Text('Gabung Kode'),
                        onPressed: _showJoinCircleDialog,
                      ),
                    ],
                  ),
                ],
              ),
            )
          : TabBarView(
                    controller: _tabController,
                    children: [
                      // Tab 1: Member List
                      _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : RefreshIndicator(
                              onRefresh: () => _loadData(circle.id),
                              child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _members.length + 1,
                              itemBuilder: (ctx, index) {
                                if (index == 0) {
                                  return _buildInviteCodeCard(circle);
                                }
                                final i = index - 1;
                                final m = _members[i];
                                final isMe = m.userId == _supa.currentUser?.id;
                                final nickname = MemberNicknameService.instance.getNickname(m.userId);
                                final fullName = m.profile?.fullName ?? 'Anggota';
                                final name = isMe ? 'Saya' : (nickname ?? fullName);
                                final avatarUrl = m.profile?.avatarUrl;
                                final loc = m.location;

                                final battery = loc?.batteryLevel ?? 100;
                                final isCharging = loc?.isCharging ?? false;

                                String timeAgo = 'Baru saja';
                                if (loc != null) {
                                  final diff = DateTime.now().difference(loc.updatedAt);
                                  if (diff.inMinutes < 1) {
                                    timeAgo = 'Baru saja';
                                  } else if (diff.inMinutes < 60) {
                                    timeAgo = '${diff.inMinutes} menit lalu';
                                  } else if (diff.inHours < 24) {
                                    timeAgo = '${diff.inHours} jam lalu';
                                  } else {
                                    timeAgo = '${diff.inDays} hari lalu';
                                  }
                                }

                                final locationStatus = isMe ? 'Di sini' : (loc != null ? 'Di rumah • $timeAgo' : 'Lokasi belum aktif');

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: AppColors.border),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.02),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(18),
                                      onTap: () => MemberDetailSheet.show(context, m, circle),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                        child: Row(
                                          children: [
                                            // Avatar Bulat
                                            CircleAvatar(
                                              radius: 24,
                                              backgroundColor: isMe ? AppColors.primaryNavy : const Color(0xFF3B82F6),
                                              backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                                                  ? NetworkImage(avatarUrl)
                                                  : null,
                                              child: (avatarUrl == null || avatarUrl.isEmpty)
                                                  ? Text(
                                                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                                                    )
                                                  : null,
                                            ),
                                            const SizedBox(width: 14),

                                            // Kolom Nama, Status, dan Baterai
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Flexible(
                                                        child: Text(
                                                          name,
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                          style: const TextStyle(
                                                            fontSize: 15,
                                                            fontWeight: FontWeight.bold,
                                                            color: AppColors.textPrimary,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      RoleBadge(role: m.role),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Row(
                                                    children: [
                                                      Text(
                                                        locationStatus,
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          color: AppColors.textSecondary,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      BatteryPill(
                                                        batteryLevel: battery,
                                                        isCharging: isCharging,
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),

                                            const Icon(
                                              Icons.chevron_right,
                                              color: AppColors.textMuted,
                                              size: 22,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),

                      // Tab 2: Zona Aman (Geofencing)
                      _buildGeofencesTab(circle),

                      ],

                  ),
    );
  }

  Future<void> _showAddGeofenceDialog(CircleModel circle) async {
    final newGeo = await GeofenceMapPicker.open(context, circleId: circle.id);
    if (newGeo != null && mounted) {
      await _loadData(circle.id);
    }
  }

  Future<void> _deleteGeofence(GeofenceModel geo, CircleModel circle) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Zona Aman?'),
        content: Text('Apakah Anda yakin ingin menghapus zona "${geo.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _geofenceService.deleteGeofence(geo.id);
        await _loadData(circle.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Zona "${geo.name}" berhasil dihapus.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal menghapus zona: $e')),
          );
        }
      }
    }
  }


  Future<void> _showGeofenceScheduleDialog(GeofenceModel geo) async {
    final currentSchedule = _schedules[geo.id] ?? await _scheduleService.getSchedule(geo.id);
    bool isEnabled = currentSchedule.isEnabled;
    TimeOfDay startTime = TimeOfDay(hour: currentSchedule.startHour, minute: currentSchedule.startMinute);
    TimeOfDay endTime = TimeOfDay(hour: currentSchedule.endHour, minute: currentSchedule.endMinute);
    List<int> selectedDays = List<int>.from(currentSchedule.daysOfWeek);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.alarm_on_rounded, color: Colors.indigo.shade700, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Jadwal Cerdas: ${geo.name}',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Fitur S4: Otomatisasi jam aktif zona aman',
                                style: TextStyle(fontSize: 12, color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Aktifkan Jadwal Waktu',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      subtitle: const Text(
                        'Default NONAKTIF (24 Jam). Jika diaktifkan, hanya memantau pada jam & hari yang dipilih.',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                      activeColor: Colors.indigo,
                      value: isEnabled,
                      onChanged: (val) {
                        setModalState(() => isEnabled = val);
                      },
                    ),
                    if (isEnabled) ...[
                      const Divider(height: 24),
                      const Text(
                        'Rentang Jam Aktif',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Icons.play_arrow_rounded, color: Colors.green),
                              label: Text('Mulai: ${startTime.format(context)}'),
                              onPressed: () async {
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: startTime,
                                );
                                if (picked != null) {
                                  setModalState(() => startTime = picked);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Icons.stop_rounded, color: Colors.red),
                              label: Text('Selesai: ${endTime.format(context)}'),
                              onPressed: () async {
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: endTime,
                                );
                                if (picked != null) {
                                  setModalState(() => endTime = picked);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Hari Aktif',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          _buildDayChip('Sen', 1, selectedDays, setModalState),
                          _buildDayChip('Sel', 2, selectedDays, setModalState),
                          _buildDayChip('Rab', 3, selectedDays, setModalState),
                          _buildDayChip('Kam', 4, selectedDays, setModalState),
                          _buildDayChip('Jum', 5, selectedDays, setModalState),
                          _buildDayChip('Sab', 6, selectedDays, setModalState),
                          _buildDayChip('Min', 7, selectedDays, setModalState),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          final newSched = GeofenceSchedule(
                            geofenceId: geo.id,
                            isEnabled: isEnabled,
                            startHour: startTime.hour,
                            startMinute: startTime.minute,
                            endHour: endTime.hour,
                            endMinute: endTime.minute,
                            daysOfWeek: selectedDays.isEmpty ? const [1, 2, 3, 4, 5] : selectedDays,
                          );
                          await _scheduleService.saveSchedule(newSched);
                          setState(() {
                            _schedules[geo.id] = newSched;
                          });
                          if (mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  isEnabled
                                      ? 'Jadwal cerdas ${geo.name} aktif: ${newSched.daysSummary} (${newSched.timeRangeString})'
                                      : 'Jadwal cerdas dinonaktifkan (Zona aktif 24 jam)',
                                ),
                                backgroundColor: isEnabled ? Colors.indigo : Colors.grey.shade800,
                              ),
                            );
                          }
                        },
                        child: const Text('Simpan Pengaturan Jadwal', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDayChip(String label, int day, List<int> selectedDays, StateSetter setModalState) {
    final isSelected = selectedDays.contains(day);
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: Colors.indigo.shade100,
      checkmarkColor: Colors.indigo.shade800,
      labelStyle: TextStyle(
        color: isSelected ? Colors.indigo.shade900 : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      onSelected: (val) {
        setModalState(() {
          if (val) {
            selectedDays.add(day);
          } else {
            selectedDays.remove(day);
          }
        });
      },
    );
  }

  Widget _buildGeofencesTab(CircleModel circle) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: () => _loadData(circle.id),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.indigo.shade700, Colors.indigo.shade500],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.security, color: Colors.white, size: 24),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Geofencing Otomatis',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Deteksi otomatis kedatangan dan kepulangan anggota keluarga di lokasi penting (Rumah, Sekolah, Kantor) tanpa perlu kirim kabar manual.',
                  style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.3),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.indigo.shade900,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    icon: const Icon(Icons.add_location_alt),
                    label: const Text('Tambah Zona Aman Baru', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () => _showAddGeofenceDialog(circle),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Section 1: Daftar Zona Aktif
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Zona Aman Aktif (${_geofences.length})',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (_geofences.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: const [
                  Icon(Icons.fmd_bad_outlined, size: 40, color: Colors.grey),
                  SizedBox(height: 8),
                  Text(
                    'Belum ada zona aman di lingkaran ini.',
                    style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Tambahkan Rumah atau Sekolah agar otomatis mendapatkan pemberitahuan saat anggota tiba.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            )
          else
            ..._geofences.map((geo) {
              Color categoryColor = Colors.orange;
              IconData categoryIcon = Icons.location_on;
              String categoryLabel = 'Lainnya';

              if (geo.category == 'home') {
                categoryColor = Colors.green;
                categoryIcon = Icons.home;
                categoryLabel = 'Rumah';
              } else if (geo.category == 'school') {
                categoryColor = Colors.blue;
                categoryIcon = Icons.school;
                categoryLabel = 'Sekolah';
              } else if (geo.category == 'work') {
                categoryColor = Colors.purple;
                categoryIcon = Icons.business;
                categoryLabel = 'Kantor';
              }

                            final sched = _schedules[geo.id];
              final isSchedEnabled = sched?.isEnabled ?? false;
              final isCurrentlyActive = sched?.isCurrentlyActive(DateTime.now()) ?? true;

              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: isSchedEnabled
                        ? (isCurrentlyActive ? Colors.indigo.shade200 : Colors.amber.shade200)
                        : Colors.grey.shade200,
                    width: isSchedEnabled ? 1.5 : 1,
                  ),
                ),
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: categoryColor.withOpacity(0.15),
                          child: Icon(categoryIcon, color: categoryColor),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                geo.name,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ),
                            if (isSchedEnabled)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isCurrentlyActive ? Colors.green.shade50 : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isCurrentlyActive ? Colors.green.shade300 : Colors.grey.shade400,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.circle,
                                      size: 8,
                                      color: isCurrentlyActive ? Colors.green : Colors.grey,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      isCurrentlyActive ? 'Aktif' : 'Di Luar Jam',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: isCurrentlyActive ? Colors.green.shade900 : Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 2),
                            Text(
                              'Kategori: $categoryLabel • Radius: ${geo.radiusMeters.toInt()}m',
                              style: const TextStyle(fontSize: 12, color: Colors.black54),
                            ),
                            if (isSchedEnabled && sched != null) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.schedule_rounded, size: 13, color: Colors.indigo.shade600),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${sched.daysSummary} (${sched.timeRangeString})',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.indigo.shade800,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                isSchedEnabled ? Icons.alarm_on_rounded : Icons.alarm_add_rounded,
                                color: isSchedEnabled ? Colors.indigo : Colors.grey.shade600,
                                size: 22,
                              ),
                              tooltip: 'Atur Jadwal Cerdas (S4)',
                              onPressed: () => _showGeofenceScheduleDialog(geo),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                              tooltip: 'Hapus Zona',
                              onPressed: () => _deleteGeofence(geo, circle),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),

          const SizedBox(height: 20),

          // Section 2: Riwayat Pergerakan Zona Terkini
          const Text(
            'Riwayat Aktivitas Zona',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),

          if (_geofenceEvents.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: const Center(
                child: Text(
                  'Belum ada riwayat aktivitas zona.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _geofenceEvents.length > 10 ? 10 : _geofenceEvents.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (ctx, idx) {
                final ev = _geofenceEvents[idx];
                final isEntered = ev.eventType == 'entered';
                final userName = ev.userProfile?.fullName ?? 'Anggota';
                final zoneName = ev.geofence?.name ?? 'Zona';

                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: isEntered ? Colors.teal.shade50 : Colors.deepOrange.shade50,
                    child: Icon(
                      isEntered ? Icons.login_rounded : Icons.logout_rounded,
                      size: 16,
                      color: isEntered ? Colors.teal : Colors.deepOrange,
                    ),
                  ),
                  title: Text(
                    '$userName ${isEntered ? "tiba di" : "meninggalkan"} $zoneName',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    DateFormat('dd MMM, HH:mm').format(ev.createdAt),
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildInviteCodeCard(CircleModel circle) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      decoration: BoxDecoration(
        color: AppColors.primaryNavy,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryNavy.withOpacity(0.25),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.groups_rounded, color: Colors.white70, size: 20),
              SizedBox(width: 8),
              Text(
                'Kode Undangan Keluarga',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            circle.inviteCode,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primaryNavy,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              elevation: 0,
            ),
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text(
              'Salin Kode',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: circle.inviteCode));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: AppColors.primaryNavy,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  content: const Text('Kode undangan berhasil disalin!'),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

}
