import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../models/models.dart';
import '../services/geofence_service.dart';
import '../services/location_service.dart';
import '../services/loud_signal_service.dart';
import '../services/supabase_service.dart';
import '../widgets/geofence_map_picker.dart';
import '../widgets/member_detail_sheet.dart';

class MapViewScreen extends StatefulWidget {
  final List<CircleModel> circles;
  final CircleModel? selectedCircle;
  final Function(CircleModel) onCircleSelected;
  final List<SosAlert> activeAlerts;
  final VoidCallback? onRefreshCircles;
  final VoidCallback? onNavigateToCircles;

  const MapViewScreen({
    super.key,
    required this.circles,
    required this.selectedCircle,
    required this.onCircleSelected,
    required this.activeAlerts,
    this.onRefreshCircles,
    this.onNavigateToCircles,
  });

  @override
  State<MapViewScreen> createState() => _MapViewScreenState();
}

class _MapViewScreenState extends State<MapViewScreen> {
  final MapController _mapController = MapController();
  final LocationService _locService = LocationService();
  final SupabaseService _supa = SupabaseService();
  final GeofenceService _geofenceService = GeofenceService();
  final LoudSignalService _loudSignalService = LoudSignalService();

  List<CircleMember> _members = [];
  List<GeofenceModel> _geofences = [];
  bool _isLoadingMembers = false;
  LatLng _center = const LatLng(-6.2088, 106.8456); // Default: Jakarta
  String _mapLayer = 'standard'; // 'standard', 'satellite', 'dark'
  bool _realtimeMovement = true;
  bool _hideCircleBanner = false;
  bool _isGpsEnabled = true;

  Position? _currentPosition;
  StreamSubscription<Position>? _positionSub;
  StreamSubscription<bool>? _gpsStatusSub;
  Timer? _realtimeRefreshTimer;

  @override
  void initState() {
    super.initState();
    _isGpsEnabled = _locService.isGpsEnabled;
    _gpsStatusSub = _locService.onGpsStatusChanged.listen((enabled) {
      if (mounted) {
        setState(() {
          _isGpsEnabled = enabled;
        });
      }
    });
    _currentPosition = _locService.currentPosition;
    if (_currentPosition != null) {
      _center = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    }
    _positionSub = _locService.onPositionChanged.listen((pos) {
      if (mounted) {
        setState(() {
          _currentPosition = pos;
        });
      }
    });
    _initMap();
    if (widget.selectedCircle != null) {
      _loadMembers(widget.selectedCircle!.id);
      if (_realtimeMovement) {
        _startRealtimeTimer();
      }
    }
  }

  @override
  void didUpdateWidget(covariant MapViewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedCircle?.id != oldWidget.selectedCircle?.id) {
      if (widget.selectedCircle != null) {
        _loadMembers(widget.selectedCircle!.id);
        if (_realtimeMovement) {
          _startRealtimeTimer();
        }
      } else {
        _stopRealtimeTimer();
      }
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _gpsStatusSub?.cancel();
    _stopRealtimeTimer();
    super.dispose();
  }

  Future<void> _initMap() async {
    final pos = await _locService.getCurrentLocation();
    if (pos != null && mounted) {
      setState(() {
        _currentPosition = pos;
        _center = LatLng(pos.latitude, pos.longitude);
      });
      _mapController.move(_center, 15);
    }
  }

  Future<void> _loadMembers(String circleId) async {
    setState(() => _isLoadingMembers = true);
    try {
      final members = await _supa.getCircleMembers(circleId);
      final geofences = await _geofenceService.getGeofences(circleId);
      if (mounted) {
        setState(() {
          _members = members;
          _geofences = geofences;
        });
      }
      // Evaluate geofence transitions
      await _geofenceService.evaluateCircleGeofences(
        circleId: circleId,
        members: members,
      );
    } catch (_) {}
    if (mounted) {
      setState(() => _isLoadingMembers = false);
    }
  }

  void _startRealtimeTimer() {
    _realtimeRefreshTimer?.cancel();
    if (!_realtimeMovement) return;
    _realtimeRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && widget.selectedCircle != null) {
        _loadMembersSilent(widget.selectedCircle!.id);
      }
    });
  }

  void _stopRealtimeTimer() {
    _realtimeRefreshTimer?.cancel();
    _realtimeRefreshTimer = null;
  }

  void _toggleRealtimeMovement() {
    setState(() {
      _realtimeMovement = !_realtimeMovement;
    });
    if (_realtimeMovement) {
      _startRealtimeTimer();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.sensors, color: Colors.greenAccent, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text('Pergerakan Real-time AKTIF (pembaruan lokasi cepat)'),
              ),
            ],
          ),
          backgroundColor: Color(0xFF14291F),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      _stopRealtimeTimer();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.sensors_off, color: Colors.white70, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text('Pergerakan Real-time MATI (mode hemat baterai)'),
              ),
            ],
          ),
          backgroundColor: Color(0xFF2A2D3A),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _loadMembersSilent(String circleId) async {
    try {
      final members = await _supa.getCircleMembers(circleId);
      final geofences = await _geofenceService.getGeofences(circleId);
      if (mounted) {
        setState(() {
          _members = members;
          _geofences = geofences;
        });
      }
    } catch (_) {}
  }

  void _moveToMyLocation() async {
    final pos = await _locService.getCurrentLocation();
    if (pos != null && mounted) {
      setState(() {
        _currentPosition = pos;
      });
      final target = LatLng(pos.latitude, pos.longitude);
      _mapController.move(target, 16);
    } else if (_currentPosition != null) {
      final target = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
      _mapController.move(target, 16);
    }
  }

  GeofenceModel? _findGeofenceForLocation(double lat, double lng) {
    const distance = Distance();
    for (final geo in _geofences) {
      final d = distance.as(
        LengthUnit.Meter,
        LatLng(lat, lng),
        LatLng(geo.latitude, geo.longitude),
      );
      if (d <= geo.radiusMeters) {
        return geo;
      }
    }
    return null;
  }

  Color _getGeofenceColor(String category) {
    switch (category) {
      case 'home':
        return Colors.green.shade600;
      case 'school':
        return Colors.blue.shade600;
      case 'work':
        return Colors.purple.shade600;
      default:
        return Colors.orange.shade700;
    }
  }

  IconData _getGeofenceIcon(String category) {
    switch (category) {
      case 'home':
        return Icons.home_rounded;
      case 'school':
        return Icons.school_rounded;
      case 'work':
        return Icons.business_rounded;
      default:
        return Icons.location_on_rounded;
    }
  }

  String _getTileUrl() {
    switch (_mapLayer) {
      case 'satellite':
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
      case 'dark':
        return 'https://cartodb-basemaps-a.global.ssl.fastly.net/dark_all/{z}/{x}/{y}.png';
      default:
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    }
  }

  void _showMapLayerDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E212B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Tampilan Peta',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _buildMapTypeOption('standard', 'Standar', Icons.map_outlined),
                    const SizedBox(width: 12),
                    _buildMapTypeOption('satellite', 'Satelit', Icons.satellite_alt_rounded),
                    const SizedBox(width: 12),
                    _buildMapTypeOption('dark', 'Gelap', Icons.dark_mode_rounded),
                  ],
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMapTypeOption(String key, String title, IconData icon) {
    final isSelected = _mapLayer == key;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          setState(() => _mapLayer = key);
          Navigator.of(context).pop();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blueAccent.withValues(alpha: 0.2) : Colors.white10,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? Colors.blueAccent : Colors.white24,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? Colors.blueAccent : Colors.white, size: 28),
              const SizedBox(height: 6),
              Text(
                title,
                style: TextStyle(
                  color: isSelected ? Colors.blueAccent : Colors.white,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCircleSelectorSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E212B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Pilih Lingkaran',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 12),
                if (widget.circles.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      children: [
                        const Text(
                          'Belum ada lingkaran keluarga aktif.\nBuat lingkaran baru atau gabung dengan kode undangan keluarga.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blueAccent,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Buat Lingkaran', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _showCreateCircleDialog();
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Colors.white30),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                icon: const Icon(Icons.group_add, size: 18),
                                label: const Text('Gabung Kode', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _showJoinCircleDialog();
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                else ...[
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: widget.circles.length,
                      separatorBuilder: (_, _) => const Divider(color: Colors.white12, height: 1),
                      itemBuilder: (context, idx) {
                        final c = widget.circles[idx];
                        final isSelected = c.id == widget.selectedCircle?.id;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          leading: CircleAvatar(
                            backgroundColor: isSelected ? Colors.blueAccent : Colors.white12,
                            child: Icon(
                              Icons.group,
                              color: isSelected ? Colors.white : Colors.white70,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            c.name,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            'Kode Undangan: ${c.inviteCode}',
                            style: const TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                          trailing: isSelected
                              ? const Icon(Icons.check_circle_rounded, color: Colors.blueAccent)
                              : null,
                          onTap: () {
                            widget.onCircleSelected(c);
                            Navigator.of(context).pop();
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: const BorderSide(color: Colors.white24),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('+ Buat Baru', style: TextStyle(fontSize: 12)),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _showCreateCircleDialog();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: const BorderSide(color: Colors.white24),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          icon: const Icon(Icons.group_add, size: 16),
                          label: const Text('# Gabung Kode', style: TextStyle(fontSize: 12)),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _showJoinCircleDialog();
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
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
            hintText: 'Misal: Keluarga Cemara',
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
                widget.onRefreshCircles?.call();
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
                widget.onRefreshCircles?.call();
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

  void _showQuickLoudSignalDialog() {
    final otherMembers = _members.where((m) => m.userId != _supa.currentUser?.id).toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E212B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: const [
                    Icon(Icons.wifi_tethering, color: Colors.redAccent, size: 24),
                    SizedBox(width: 8),
                    Text(
                      'Kirim Sinyal Keras',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Membunyikan alarm ponsel anggota secara maksimal meskipun ponsel dalam mode Hening / Jangan Ganggu (DND).',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 14),
                if (otherMembers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text(
                        'Tidak ada anggota lain di lingkaran ini.',
                        style: TextStyle(color: Colors.white60),
                      ),
                    ),
                  )
                else
                  ...otherMembers.map((m) {
                    final name = m.profile?.fullName ?? 'Anggota';
                    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.teal,
                          child: Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          m.location != null ? 'Baterai: ${m.location!.batteryLevel}%' : 'Lokasi tidak diketahui',
                          style: const TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                        trailing: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.volume_up, size: 16),
                          label: const Text('Bunyikan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          onPressed: () async {
                            Navigator.of(context).pop();
                            try {
                              await _loudSignalService.sendLoudSignal(
                                targetUserId: m.userId,
                                circleId: widget.selectedCircle?.id,
                              );
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Sinyal Keras berhasil dikirim ke $name!'),
                                    backgroundColor: Colors.teal.shade800,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Gagal mengirim sinyal: $e'),
                                    backgroundColor: Colors.red.shade800,
                                  ),
                                );
                              }
                            }
                          },
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showQuickAmbientAudioDialog() {
    final otherMembers = _members.where((m) => m.userId != _supa.currentUser?.id).toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E212B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: const [
                      Icon(Icons.mic, color: Colors.deepOrangeAccent, size: 24),
                      SizedBox(width: 8),
                      Text(
                        'Dengar Suara Sekitar',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Dengarkan suara lingkungan anak/anggota secara hening, atau lakukan tes rekaman mikrofon di HP ini.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 14),

                  // Self Test Card
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.deepOrange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.deepOrange.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.deepOrange,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.mic_external_on, color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'Uji Coba di HP Ini (Self-Test)',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Rekam 10 detik & langsung dengar suara sekitar Anda sekarang',
                                style: TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepOrange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            final myMember = _members.firstWhere(
                              (m) => m.userId == _supa.currentUser?.id,
                              orElse: () => _members.first,
                            );
                            MemberDetailSheet.show(context, myMember, widget.selectedCircle);
                          },
                          child: const Text('Mulai Tes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),
                  const Text(
                    'Atau Minta Suara Anggota Lingkaran:',
                    style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 8),

                  if (otherMembers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Center(
                        child: Text(
                          'Tidak ada anggota lain di lingkaran ini.',
                          style: TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                      ),
                    )
                  else
                    ...otherMembers.map((m) {
                      final name = m.profile?.fullName ?? 'Anggota';
                      final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.teal,
                            child: Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                          title: Text(
                            name,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            m.location != null ? 'Baterai: ${m.location!.batteryLevel}%' : 'Lokasi tidak diketahui',
                            style: const TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                          trailing: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepOrange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.hearing, size: 16),
                            label: const Text('Minta Suara', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              MemberDetailSheet.show(context, m, widget.selectedCircle);
                            },
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGlassButton({
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
    Color iconColor = Colors.white,
    int badgeCount = 0,
    bool isLoading = false,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isLoading ? null : onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFF1E212B),
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (isLoading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent),
              )
            else
              Icon(icon, color: iconColor, size: 20),
            if (badgeCount > 0)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$badgeCount',
                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberMarker(CircleMember member) {
    final isMe = member.userId == _supa.currentUser?.id;
    final loc = member.location;
    if (loc == null && !isMe) return const SizedBox.shrink();

    final name = isMe ? 'Saya' : (member.profile?.fullName ?? 'Anggota');
    final initials = name.isNotEmpty ? name[0].toUpperCase() : '?';

    final batteryLevel = isMe ? _locService.batteryLevel : (loc?.batteryLevel ?? 100);
    final isCharging = isMe ? false : (loc?.isCharging ?? false);

    Color batteryColor = Colors.green;
    if (batteryLevel < 20) {
      batteryColor = Colors.red;
    } else if (batteryLevel < 50) {
      batteryColor = Colors.orange;
    }

    final lat = isMe && _currentPosition != null ? _currentPosition!.latitude : (loc?.latitude ?? 0.0);
    final lng = isMe && _currentPosition != null ? _currentPosition!.longitude : (loc?.longitude ?? 0.0);

    final zone = _findGeofenceForLocation(lat, lng);
    final hasZone = zone != null;
    final zoneColor = hasZone ? _getGeofenceColor(zone.category) : (isMe ? Colors.blueAccent : Colors.indigo.shade800);
    final zoneIcon = hasZone ? _getGeofenceIcon(zone.category) : (isMe ? Icons.my_location_rounded : Icons.directions_walk_rounded);
    final zoneText = hasZone ? 'Di ${zone.name}' : (isMe ? 'Saya (Di sini)' : 'Bergerak');

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => MemberDetailSheet.show(context, member, widget.selectedCircle),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Find My Kids Style Status Pill: [ 🏠 Di Rumah • 85% ⚡ ]
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1)),
              ],
              border: Border.all(
                color: hasZone ? zoneColor.withValues(alpha: 0.6) : (isMe ? Colors.blueAccent.withValues(alpha: 0.7) : Colors.grey.shade300),
                width: isMe ? 1.5 : 1.2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(zoneIcon, size: 11, color: zoneColor),
                const SizedBox(width: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 75),
                  child: Text(
                    zoneText,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: zoneColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 5),
                Container(width: 1, height: 9, color: Colors.grey.shade300),
                const SizedBox(width: 5),
                Icon(
                  isCharging ? Icons.battery_charging_full : Icons.battery_std,
                  size: 11,
                  color: batteryColor,
                ),
                Text(
                  '$batteryLevel%',
                  style: TextStyle(fontSize: 9, color: batteryColor, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 3),

          // Avatar Pin
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isMe ? Colors.blueAccent : Colors.teal,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                if (isMe)
                  BoxShadow(color: Colors.blueAccent.withValues(alpha: 0.45), blurRadius: 10, spreadRadius: 3),
                const BoxShadow(color: Colors.black38, blurRadius: 6),
              ],
            ),
            child: Center(
              child: Text(
                initials,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentUserMarker(Position pos) {
    final name = _supa.currentUser?.userMetadata?['full_name'] as String? ?? 'Saya';
    final initials = name.isNotEmpty ? name[0].toUpperCase() : 'S';
    final battery = _locService.batteryLevel;

    Color batteryColor = Colors.green;
    if (battery < 20) {
      batteryColor = Colors.red;
    } else if (battery < 50) {
      batteryColor = Colors.orange;
    }

    final zone = _findGeofenceForLocation(pos.latitude, pos.longitude);
    final hasZone = zone != null;
    final zoneColor = hasZone ? _getGeofenceColor(zone.category) : Colors.blueAccent;
    final zoneIcon = hasZone ? _getGeofenceIcon(zone.category) : Icons.my_location_rounded;
    final zoneText = hasZone ? 'Di ${zone.name}' : 'Saya (Di sini)';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.selectedCircle != null
                  ? 'Lokasi Anda saat ini (${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)})'
                  : 'Lokasi Anda saat ini. Pilih atau buat Lingkaran untuk membagikan dengan keluarga.',
            ),
            duration: const Duration(seconds: 3),
            action: widget.selectedCircle == null && widget.onNavigateToCircles != null
                ? SnackBarAction(
                    label: 'LINGKARAN',
                    textColor: Colors.blueAccent,
                    onPressed: widget.onNavigateToCircles!,
                  )
                : null,
          ),
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Find My Kids Style Status Pill: [ 📍 Saya (Di sini) • 100% ⚡ ]
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1)),
              ],
              border: Border.all(
                color: Colors.blueAccent.withValues(alpha: 0.7),
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(zoneIcon, size: 11, color: zoneColor),
                const SizedBox(width: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 80),
                  child: Text(
                    zoneText,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: zoneColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 5),
                Container(width: 1, height: 9, color: Colors.grey.shade300),
                const SizedBox(width: 5),
                Icon(
                  Icons.battery_std,
                  size: 11,
                  color: batteryColor,
                ),
                Text(
                  '$battery%',
                  style: TextStyle(fontSize: 9, color: batteryColor, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 3),

          // Glowing Blue Avatar Pin
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.blueAccent,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.blueAccent.withValues(alpha: 0.45),
                  blurRadius: 10,
                  spreadRadius: 3,
                ),
                const BoxShadow(color: Colors.black38, blurRadius: 6),
              ],
            ),
            child: Center(
              child: Text(
                initials,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSosMarker(SosAlert alert) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
          ),
          child: const Text(
            'SOS DARURAT',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
          ),
        ),
        const SizedBox(height: 2),
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.red,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [BoxShadow(color: Colors.redAccent, blurRadius: 10, spreadRadius: 3)],
          ),
          child: const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 26),
        ),
      ],
    );
  }

  void _showSosDetailDialog(SosAlert alert) {
    final isIntruder = alert.message.contains('[JEBAKAN PENYUSUP]');
    String? photoUrl;
    if (isIntruder) {
      final match = RegExp(r'Foto:\s*(https?://\S+)').firstMatch(alert.message);
      if (match != null) {
        photoUrl = match.group(1);
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: const Color(0xFF1E1E2C),
        title: Row(
          children: [
            Icon(
              isIntruder ? Icons.camera_front : Icons.warning_amber_rounded,
              color: isIntruder ? Colors.deepOrangeAccent : Colors.redAccent,
              size: 28,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isIntruder ? 'JEBAKAN PENYUSUP' : 'PERINGATAN DARURAT',
                style: TextStyle(
                  color: isIntruder ? Colors.deepOrangeAccent : Colors.redAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (photoUrl != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    photoUrl,
                    height: 220,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return Container(
                        height: 220,
                        color: Colors.black26,
                        child: const Center(child: CircularProgressIndicator()),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) => Container(
                      height: 120,
                      color: Colors.black26,
                      alignment: Alignment.center,
                      child: const Text(
                        'Foto tidak dapat dimuat atau telah kedaluwarsa.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                alert.message,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.white54, size: 14),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Koordinat: ${alert.latitude.toStringAsFixed(5)}, ${alert.longitude.toStringAsFixed(5)}',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.access_time, color: Colors.white54, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    'Waktu: ${alert.triggeredAt.toLocal().toString().split('.')[0]}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _mapController.move(LatLng(alert.latitude, alert.longitude), 17.0);
            },
            child: const Text('Lihat di Peta', style: TextStyle(color: Colors.cyanAccent)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  Widget _buildGeofenceMarker(GeofenceModel geo) {
    final color = _getGeofenceColor(geo.category);
    final icon = _getGeofenceIcon(geo.category);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
          child: Text(
            geo.name,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: color, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
          child: Icon(icon, color: color, size: 16),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[];

    // Add Geofence markers
    for (var geo in _geofences) {
      markers.add(
        Marker(
          point: LatLng(geo.latitude, geo.longitude),
          width: 120,
          height: 60,
          child: _buildGeofenceMarker(geo),
        ),
      );
    }

    final currentUserId = _supa.currentUser?.id;
    bool hasMyMarkerAdded = false;

    // Add Member markers
    for (var m in _members) {
      final isMe = m.userId == currentUserId;
      final LatLng? memberPoint = isMe
          ? (_currentPosition != null
              ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
              : (m.location != null ? LatLng(m.location!.latitude, m.location!.longitude) : null))
          : (m.location != null && m.isSharingLocation
              ? LatLng(m.location!.latitude, m.location!.longitude)
              : null);

      if (memberPoint != null) {
        if (isMe) hasMyMarkerAdded = true;
        markers.add(
          Marker(
            point: memberPoint,
            width: 140,
            height: 75,
            child: _buildMemberMarker(m),
          ),
        );
      }
    }

    // Always guarantee user's own location is displayed!
    if (!hasMyMarkerAdded && _currentPosition != null) {
      markers.add(
        Marker(
          point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          width: 140,
          height: 75,
          child: _buildCurrentUserMarker(_currentPosition!),
        ),
      );
    }

    // Add Active SOS markers
    for (var alert in widget.activeAlerts) {
      markers.add(
        Marker(
          point: LatLng(alert.latitude, alert.longitude),
          width: 100,
          height: 80,
          child: GestureDetector(
            onTap: () => _showSosDetailDialog(alert),
            child: _buildSosMarker(alert),
          ),
        ),
      );
    }

    return Stack(
      children: [
        // 1. FlutterMap with Dynamic Tile Layer & Geofences
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _center,
            initialZoom: 15.0,
            minZoom: 4.0,
            maxZoom: 19.0,
          ),
          children: [
            TileLayer(
              urlTemplate: _getTileUrl(),
              userAgentPackageName: 'com.lingkaraman.lingkar_aman',
            ),
            CircleLayer(
              circles: _geofences.map((geo) {
                final color = _getGeofenceColor(geo.category);
                return CircleMarker(
                  point: LatLng(geo.latitude, geo.longitude),
                  radius: geo.radiusMeters,
                  useRadiusInMeter: true,
                  color: color.withValues(alpha: 0.18),
                  borderColor: color,
                  borderStrokeWidth: 2.0,
                );
              }).toList(),
            ),
            MarkerLayer(markers: markers),
          ],
        ),

        // 2. Modern Floating Header Bar (Pill Selector, Layers, Notifications)
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                _buildGlassButton(
                  icon: Icons.refresh,
                  tooltip: 'Segarkan Lokasi',
                  isLoading: _isLoadingMembers,
                  onTap: () {
                    if (widget.selectedCircle != null) {
                      _loadMembers(widget.selectedCircle!.id);
                    }
                  },
                ),
                const SizedBox(width: 8),

                // Center Floating Pill: [ Family ⌵ ] with Realtime Status Badge
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _showCircleSelectorSheet,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E212B),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: _realtimeMovement
                              ? Colors.greenAccent.withValues(alpha: 0.35)
                              : Colors.white12,
                          width: 1.2,
                        ),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2)),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.shield_outlined, color: Colors.blueAccent, size: 15),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  widget.selectedCircle?.name ?? 'Pilih Lingkaran',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70, size: 18),
                            ],
                          ),
                          const SizedBox(height: 2),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _toggleRealtimeMovement,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _realtimeMovement ? Colors.greenAccent : Colors.grey,
                                    boxShadow: _realtimeMovement
                                        ? [
                                            BoxShadow(
                                              color: Colors.greenAccent.withValues(alpha: 0.7),
                                              blurRadius: 4,
                                              spreadRadius: 1,
                                            )
                                          ]
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  _realtimeMovement ? 'REALTIME: AKTIF' : 'REALTIME: MATI',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                    color: _realtimeMovement ? Colors.greenAccent : Colors.white38,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Notification Bell
                _buildGlassButton(
                  icon: widget.activeAlerts.isNotEmpty ? Icons.notifications_active : Icons.notifications_none,
                  iconColor: widget.activeAlerts.isNotEmpty ? Colors.redAccent : Colors.white,
                  badgeCount: widget.activeAlerts.length,
                  tooltip: 'Peringatan Darurat',
                  onTap: () {
                    if (widget.activeAlerts.isNotEmpty) {
                      _showSosDetailDialog(widget.activeAlerts.first);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Tidak ada peringatan darurat saat ini.'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(width: 8),

                // Map Layers Switcher Button [ ⧉ ]
                _buildGlassButton(
                  icon: Icons.layers_rounded,
                  tooltip: 'Ganti Lapisan Peta',
                  onTap: _showMapLayerDialog,
                ),
              ],
            ),
          ),
        ),

        // Banner peringatan jika GPS mati
        if (!_isGpsEnabled)
          Positioned(
            top: 114,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF2A1515).withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.6), width: 1.2),
                boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3))],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.location_off_rounded, color: Colors.redAccent, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Text(
                          'Layanan Lokasi (GPS) Nonaktif',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Lokasi Anda tidak dapat diperbarui. Nyalakan GPS agar keluarga dapat memantau posisi Anda.',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _locService.openGpsSettings(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Nyalakan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
            ),
          ),

        // Banner info jika belum ada lingkaran yang dipilih
        if (widget.selectedCircle == null && !_hideCircleBanner)
          Positioned(
            top: !_isGpsEnabled ? 190 : 114,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E212B).withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.4), width: 1.2),
                boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3))],
              ),
              child: Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _showCircleSelectorSheet,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.my_location_rounded, color: Colors.blueAccent, size: 18),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _showCircleSelectorSheet,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Text(
                            'Lokasi Anda Terlacak di Peta',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Titik "Saya" aktif. Tekan untuk membuat / memilih Lingkaran keluarga.',
                            style: TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _hideCircleBanner = true),
                    child: const Padding(
                      padding: EdgeInsets.all(4.0),
                      child: Icon(Icons.close_rounded, color: Colors.white54, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // 3. Floating Quick-Action Bar (Find My Kids Pattern)
        Positioned(
          left: 16,
          right: 16,
          bottom: _members.isNotEmpty ? 76 : 24,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Sinyal Keras Pill
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _showQuickLoudSignalDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E212B),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.wifi_tethering, color: Colors.redAccent, size: 16),
                        SizedBox(width: 6),
                        Text(
                          'Sinyal Keras',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Dengar Suara Pill (Find My Kids Pattern)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _showQuickAmbientAudioDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E212B),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.mic, color: Colors.deepOrangeAccent, size: 16),
                        SizedBox(width: 6),
                        Text(
                          'Dengar Suara',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Realtime Movements Toggle Pill
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleRealtimeMovement,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: _realtimeMovement ? const Color(0xFF0F2E1E) : const Color(0xFF1E212B),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _realtimeMovement ? Colors.greenAccent : Colors.white24,
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _realtimeMovement
                              ? Colors.greenAccent.withValues(alpha: 0.2)
                              : Colors.black26,
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _realtimeMovement ? Icons.sensors_rounded : Icons.sensors_off_rounded,
                          color: _realtimeMovement ? Colors.greenAccent : Colors.grey,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Pergerakan Real-time:',
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _realtimeMovement
                                ? Colors.greenAccent.withValues(alpha: 0.25)
                                : Colors.white10,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _realtimeMovement ? Colors.greenAccent : Colors.grey,
                                  boxShadow: _realtimeMovement
                                      ? [
                                          BoxShadow(
                                            color: Colors.greenAccent.withValues(alpha: 0.8),
                                            blurRadius: 3,
                                          )
                                        ]
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _realtimeMovement ? 'AKTIF' : 'MATI',
                                style: TextStyle(
                                  color: _realtimeMovement ? Colors.greenAccent : Colors.white54,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Quick Add Geofence Shortcut
                if (widget.selectedCircle != null)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () async {
                      final newGeo = await GeofenceMapPicker.open(
                        context,
                        circleId: widget.selectedCircle!.id,
                        initialCenter: _center,
                      );
                      if (newGeo != null && mounted) {
                        await _loadMembers(widget.selectedCircle!.id);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E212B),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.add_location_alt_rounded, color: Colors.amber, size: 16),
                          SizedBox(width: 4),
                          Text(
                            '+ Tempat',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // 4. Bottom Member Horizontal Quick Bar
        if (_members.isNotEmpty)
          Positioned(
            left: 16,
            right: 76,
            bottom: 16,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _members.map((m) {
                  final isMe = m.userId == _supa.currentUser?.id;
                  final name = isMe ? 'Saya' : (m.profile?.fullName ?? 'Anggota');
                  final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
                  final zone = m.location != null
                      ? _findGeofenceForLocation(m.location!.latitude, m.location!.longitude)
                      : null;

                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        if (m.location != null) {
                          _mapController.move(
                            LatLng(m.location!.latitude, m.location!.longitude),
                            16,
                          );
                        }
                        MemberDetailSheet.show(context, m, widget.selectedCircle);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E212B),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 13,
                              backgroundColor: isMe ? Colors.blueAccent : Colors.teal,
                              child: Text(
                                initial,
                                style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  name.length > 9 ? '${name.substring(0, 9)}..' : name,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                if (zone != null)
                                  Text(
                                    'Di ${zone.name}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: _getGeofenceColor(zone.category),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                              ],
                            ),
                            if (m.location != null) ...[
                              const SizedBox(width: 6),
                              Icon(
                                m.location!.isCharging ? Icons.battery_charging_full : Icons.battery_std,
                                size: 13,
                                color: m.location!.batteryLevel < 20 ? Colors.red : Colors.greenAccent,
                              ),
                              Text(
                                '${m.location!.batteryLevel}%',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: m.location!.batteryLevel < 20 ? Colors.red : Colors.greenAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

        // 5. Bottom Right Floating Controls (My Location & Fit All)
        Positioned(
          bottom: 16,
          right: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.small(
                heroTag: 'my_loc_btn',
                backgroundColor: const Color(0xFF1E212B),
                foregroundColor: Colors.blueAccent,
                onPressed: _moveToMyLocation,
                child: const Icon(Icons.my_location),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                heroTag: 'fit_all_btn',
                backgroundColor: const Color(0xFF1E212B),
                foregroundColor: Colors.white,
                tooltip: 'Lihat Semua Anggota',
                onPressed: () {
                  final validLocs = _members
                      .where((m) => m.location != null)
                      .map((m) => LatLng(m.location!.latitude, m.location!.longitude))
                      .toList();
                  if (validLocs.isNotEmpty) {
                    final bounds = LatLngBounds.fromPoints(validLocs);
                    _mapController.fitCamera(
                      CameraFit.bounds(
                        bounds: bounds,
                        padding: const EdgeInsets.all(50),
                      ),
                    );
                  }
                },
                child: const Icon(Icons.zoom_out_map),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
