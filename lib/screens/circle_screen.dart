import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/geofence_service.dart';
import '../services/supabase_service.dart';
import '../widgets/geofence_map_picker.dart';
import '../widgets/member_detail_sheet.dart';
import '../services/member_nickname_service.dart';
import '../services/sound_settings_service.dart';

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
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  late TabController _tabController;
  List<CircleMember> _members = [];
  List<CircleMessage> _messages = [];
  List<GeofenceModel> _geofences = [];
  List<GeofenceEventModel> _geofenceEvents = [];
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
    _tabController = TabController(length: 3, vsync: this);
    MemberNicknameService.instance.addListener(_onNicknamesChanged);
    if (widget.selectedCircle != null) {
      _loadData(widget.selectedCircle!.id);
      _listenToChat(widget.selectedCircle!.id);
    }
  }

  @override
  void didUpdateWidget(covariant CircleScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedCircle?.id != oldWidget.selectedCircle?.id) {
      if (widget.selectedCircle != null) {
        _loadData(widget.selectedCircle!.id);
        _listenToChat(widget.selectedCircle!.id);
      }
    }
  }

  @override
  void dispose() {
    MemberNicknameService.instance.removeListener(_onNicknamesChanged);
    _tabController.dispose();
    _msgController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  void _listenToChat(String circleId) {
    _supa.subscribeToMessages(circleId, (newMsg) {
      if (mounted) {
        setState(() {
          _messages.add(newMsg);
        });
        _scrollToBottom();

        // Notifikasi & nada chat jika pesan berasal dari anggota lain
        if (newMsg.userId != _supa.currentUser?.id) {
          SoundSettingsService().previewSound('bubble_pop');
          if (_tabController.index != 2) {
            final nickname = MemberNicknameService.instance.getNickname(newMsg.userId);
            final sName = nickname ?? newMsg.senderProfile?.fullName ?? 'Anggota';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                behavior: SnackBarBehavior.floating,
                backgroundColor: const Color(0xFF1E3A8A),
                duration: const Duration(seconds: 3),
                content: Text(
                  '💬 $sName: ${newMsg.message}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                action: SnackBarAction(
                  label: 'Buka Obrolan',
                  textColor: Colors.amberAccent,
                  onPressed: () => _tabController.animateTo(2),
                ),
              ),
            );
          }
        }
      }
    });
  }

  Future<void> _loadData(String circleId) async {
    setState(() => _isLoading = true);
    try {
      final members = await _supa.getCircleMembers(circleId);
      final messages = await _supa.getMessages(circleId);
      final geofences = await _geofenceService.getGeofences(circleId);
      final events = await _geofenceService.getRecentEvents(circleId);
      if (mounted) {
        setState(() {
          _members = members;
          _messages = messages;
          _geofences = geofences;
          _geofenceEvents = events;
        });
        _scrollToBottom();
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
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

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty || widget.selectedCircle == null) return;

    _msgController.clear();
    try {
      await _supa.sendMessage(widget.selectedCircle!.id, text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal kirim pesan: $e')),
        );
      }
    }
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
                  Tab(icon: Icon(Icons.chat_bubble_outline), text: 'Obrolan'),
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
          : Column(
              children: [
                // Invite Code Banner
                Container(
                  color: Colors.indigo.shade50,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.vpn_key_outlined, size: 20, color: Colors.indigo),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text(
                              'Kode Invite: ',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                            Text(
                              circle.inviteCode,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('Salin'),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: circle.inviteCode));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Kode invite berhasil disalin!')),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                // Tabs Body
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // Tab 1: Member List
                      _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : RefreshIndicator(
                              onRefresh: () => _loadData(circle.id),
                              child: ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: _members.length,
                              separatorBuilder: (_, _) => const Divider(),
                              itemBuilder: (ctx, i) {
                                final m = _members[i];
                                final isMe = m.userId == _supa.currentUser?.id;
                                final nickname = MemberNicknameService.instance.getNickname(m.userId);
                                final fullName = m.profile?.fullName ?? 'Anggota';
                                final name = isMe ? 'Saya' : (nickname ?? fullName);
                                final avatarUrl = m.profile?.avatarUrl;
                                final loc = m.location;

                                return ListTile(
                                  onTap: () => MemberDetailSheet.show(context, m, circle),
                                  leading: CircleAvatar(
                                    backgroundColor: isMe ? Colors.blue : Colors.teal,
                                    backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                                        ? NetworkImage(avatarUrl)
                                        : null,
                                    child: (avatarUrl == null || avatarUrl.isEmpty)
                                        ? Text(
                                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                          )
                                        : null,
                                  ),
                                  title: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          name,
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (m.isAdmin) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: Colors.amber.shade100,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Text(
                                            '👑 Admin Utama',
                                            style: TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ] else ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.shade50,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            '👤 Anggota',
                                            style: TextStyle(fontSize: 10, color: Colors.blue.shade800, fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (!isMe && nickname != null)
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 2),
                                          child: Text(
                                            'Nama asli: $fullName',
                                            style: TextStyle(fontSize: 11, color: Colors.indigo.shade700, fontWeight: FontWeight.w500),
                                          ),
                                        ),
                                      loc != null
                                          ? Text(
                                              'Baterai: ${loc.batteryLevel}% ${loc.isCharging ? "(Mengisi)" : ""} • Update: ${DateFormat('HH:mm').format(loc.updatedAt)}',
                                              style: const TextStyle(fontSize: 12),
                                            )
                                          : const Text(
                                              'Lokasi belum terdeteksi',
                                              style: TextStyle(fontSize: 12, color: Colors.grey),
                                            ),
                                    ],
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (loc != null)
                                        Icon(
                                          loc.batteryLevel < 20
                                              ? Icons.battery_alert
                                              : (loc.isCharging
                                                  ? Icons.battery_charging_full
                                                  : Icons.battery_full),
                                          color: loc.batteryLevel < 20 ? Colors.red : Colors.green,
                                          size: 20,
                                        ),
                                      if (!isMe) ...[
                                        IconButton(
                                          icon: const Icon(Icons.edit_note_rounded, color: Colors.indigo, size: 22),
                                          tooltip: 'Ubah Nama Panggilan',
                                          onPressed: () => _showEditNicknameDialog(m.userId, nickname, fullName),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.mic, color: Colors.deepOrange, size: 22),
                                          tooltip: 'Dengar Suara Sekitar (15s)',
                                          onPressed: () => MemberDetailSheet.show(context, m, circle),
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),

                      // Tab 2: Zona Aman (Geofencing)
                      _buildGeofencesTab(circle),

                      // Tab 3: Chat / Feed Komunitas
                      Column(
                        children: [
                          Expanded(
                            child: _messages.isEmpty
                                ? const Center(
                                    child: Text(
                                      'Belum ada obrolan di lingkaran ini.\nKirim kabar pertama sekarang!',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  )
                                : ListView.builder(
                                    controller: _chatScrollController,
                                    padding: const EdgeInsets.all(12),
                                    itemCount: _messages.length,
                                    itemBuilder: (ctx, i) {
                                      final msg = _messages[i];
                                      final isMe = msg.userId == _supa.currentUser?.id;
                                      final nickname = MemberNicknameService.instance.getNickname(msg.userId);
                                      final fullName = msg.senderProfile?.fullName ?? 'Anggota';
                                      final senderName = isMe ? 'Saya' : (nickname ?? fullName);
                                      final senderAvatar = msg.senderProfile?.avatarUrl;

                                      return Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 4),
                                        child: Row(
                                          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            if (!isMe) ...[
                                              CircleAvatar(
                                                radius: 14,
                                                backgroundColor: Colors.indigo.shade100,
                                                backgroundImage: (senderAvatar != null && senderAvatar.isNotEmpty)
                                                    ? NetworkImage(senderAvatar)
                                                    : null,
                                                child: (senderAvatar == null || senderAvatar.isEmpty)
                                                    ? Text(
                                                        senderName.isNotEmpty ? senderName[0].toUpperCase() : '?',
                                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo.shade900),
                                                      )
                                                    : null,
                                              ),
                                              const SizedBox(width: 6),
                                            ],
                                            Flexible(
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                                decoration: BoxDecoration(
                                                  color: isMe ? Colors.indigo.shade600 : Colors.grey.shade200,
                                                  borderRadius: BorderRadius.circular(16),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                                  children: [
                                                    if (!isMe)
                                                      Text(
                                                        senderName,
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.bold,
                                                          color: Colors.indigo.shade900,
                                                        ),
                                                      ),
                                              Text(
                                                msg.message,
                                                style: TextStyle(
                                                  color: isMe ? Colors.white : Colors.black87,
                                                  fontSize: 14,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                DateFormat('HH:mm').format(msg.createdAt),
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  color: isMe ? Colors.white70 : Colors.grey.shade600,
                                                ),
                                              ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            color: Colors.white,
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _msgController,
                                    decoration: const InputDecoration(
                                      hintText: 'Ketik pesan / kabar...',
                                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.all(Radius.circular(24)),
                                      ),
                                    ),
                                    onSubmitted: (_) => _sendMessage(),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                CircleAvatar(
                                  backgroundColor: Colors.indigo,
                                  child: IconButton(
                                    icon: const Icon(Icons.send, color: Colors.white, size: 20),
                                    onPressed: _sendMessage,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
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

              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: categoryColor.withValues(alpha: 0.15),
                    child: Icon(categoryIcon, color: categoryColor),
                  ),
                  title: Text(geo.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text(
                    'Kategori: $categoryLabel • Radius: ${geo.radiusMeters.toInt()}m',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                    tooltip: 'Hapus Zona',
                    onPressed: () => _deleteGeofence(geo, circle),
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
}
