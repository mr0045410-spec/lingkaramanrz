import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../models/models.dart';
import '../services/geofence_service.dart';
import '../services/location_service.dart';

class GeofenceMapPicker extends StatefulWidget {
  final String circleId;
  final LatLng? initialCenter;
  final String initialCategory;
  final double initialRadius;

  const GeofenceMapPicker({
    super.key,
    required this.circleId,
    this.initialCenter,
    this.initialCategory = 'home',
    this.initialRadius = 150.0,
  });

  static Future<GeofenceModel?> open(
    BuildContext context, {
    required String circleId,
    LatLng? initialCenter,
    String initialCategory = 'home',
  }) {
    return Navigator.of(context).push<GeofenceModel>(
      MaterialPageRoute(
        builder: (_) => GeofenceMapPicker(
          circleId: circleId,
          initialCenter: initialCenter,
          initialCategory: initialCategory,
        ),
      ),
    );
  }

  @override
  State<GeofenceMapPicker> createState() => _GeofenceMapPickerState();
}

class _GeofenceMapPickerState extends State<GeofenceMapPicker> {
  final MapController _mapController = MapController();
  final GeofenceService _geofenceService = GeofenceService();
  final LocationService _locService = LocationService();
  late final TextEditingController _nameController;

  late LatLng _center;
  late String _category;
  late double _radiusMeters;
  bool _isSaving = false;
  bool _isLoadingGps = false;

  @override
  void initState() {
    super.initState();
    _center = widget.initialCenter ?? const LatLng(-6.2088, 106.8456); // Jakarta default
    _category = widget.initialCategory;
    _radiusMeters = widget.initialRadius;

    final defaultName = _getDefaultNameForCategory(_category);
    _nameController = TextEditingController(text: defaultName);

    if (widget.initialCenter == null) {
      _fetchInitialGps();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String _getDefaultNameForCategory(String cat) {
    switch (cat) {
      case 'home':
        return 'Rumah';
      case 'school':
        return 'Sekolah';
      case 'work':
        return 'Kantor';
      default:
        return 'Tempat Aman';
    }
  }

  Color _getCategoryColor(String cat) {
    switch (cat) {
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

  IconData _getCategoryIcon(String cat) {
    switch (cat) {
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

  Future<void> _fetchInitialGps() async {
    setState(() => _isLoadingGps = true);
    try {
      final pos = await _locService.getCurrentLocation();
      if (pos != null && mounted) {
        final newCenter = LatLng(pos.latitude, pos.longitude);
        setState(() => _center = newCenter);
        _mapController.move(newCenter, 16.0);
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoadingGps = false);
  }

  Future<void> _recenterToGps() async {
    setState(() => _isLoadingGps = true);
    try {
      final pos = await _locService.getCurrentLocation();
      if (pos != null && mounted) {
        final target = LatLng(pos.latitude, pos.longitude);
        setState(() => _center = target);
        _mapController.move(target, 16.0);
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoadingGps = false);
  }

  Future<void> _saveGeofence() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama tempat aman tidak boleh kosong')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final geofence = await _geofenceService.createGeofence(
        circleId: widget.circleId,
        name: name,
        category: _category,
        latitude: _center.latitude,
        longitude: _center.longitude,
        radiusMeters: _radiusMeters,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Tempat aman "$name" berhasil ditambahkan!'),
            backgroundColor: Colors.teal.shade800,
          ),
        );
        Navigator.of(context).pop(geofence);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menyimpan tempat aman: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = _getCategoryColor(_category);

    return Scaffold(
      body: Stack(
        children: [
          // 1. FlutterMap (Interactive, movable)
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 16.0,
              minZoom: 4.0,
              maxZoom: 19.0,
              onPositionChanged: (camera, hasGesture) {
                // Update center coordinate in realtime as user drags the map
                setState(() {
                  _center = camera.center;
                });
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.lingkaraman.lingkar_aman',
              ),
              // Dynamic Geofence Radius Circle centered on current map center
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: _center,
                    radius: _radiusMeters,
                    useRadiusInMeter: true,
                    color: themeColor.withValues(alpha: 0.22),
                    borderColor: themeColor,
                    borderStrokeWidth: 2.5,
                  ),
                ],
              ),
            ],
          ),

          // 2. Fixed Center Target Pin (Crosshair Pin like Find My Kids)
          Center(
            child: IgnorePointer(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Floating Tooltip above pin
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
                      ],
                    ),
                    child: const Text(
                      'Geser peta untuk menentukan titik zona',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Pin Head with Category Icon
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: themeColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: themeColor.withValues(alpha: 0.4),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(_getCategoryIcon(_category), color: Colors.white, size: 26),
                  ),

                  // Pointer Arrow & Anchor Shadow
                  CustomPaint(
                    size: const Size(14, 10),
                    painter: _TrianglePainter(color: themeColor),
                  ),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      shape: BoxShape.circle,
                      boxShadow: const [
                        BoxShadow(color: Colors.black38, blurRadius: 4, spreadRadius: 1),
                      ],
                    ),
                  ),
                  // Offset by half height to make the point the true center
                  const SizedBox(height: 44),
                ],
              ),
            ),
          ),

          // 3. Top Floating Bar (Back button, Title, GPS recenter)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.white,
                    radius: 22,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.black87),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 8),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(_getCategoryIcon(_category), color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Pilih Lokasi ${_nameController.text.isEmpty ? "Zona" : _nameController.text}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  CircleAvatar(
                    backgroundColor: Colors.white,
                    radius: 22,
                    child: _isLoadingGps
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            icon: const Icon(Icons.my_location, color: Colors.indigo),
                            onPressed: _recenterToGps,
                            tooltip: 'Pusatkan ke Lokasi Saya',
                          ),
                  ),
                ],
              ),
            ),
          ),

          // 4. Bottom Controls Card (Category, Radius, Name & Save Action)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(color: Colors.black12, blurRadius: 16, offset: Offset(0, -4)),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Drag Handle Bar
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
                    const SizedBox(height: 12),

                    // Category Chips (Rumah, Sekolah, Kantor, Lainnya)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildCategoryChip('home', 'Rumah', Icons.home_rounded, Colors.green.shade600),
                          const SizedBox(width: 8),
                          _buildCategoryChip('school', 'Sekolah', Icons.school_rounded, Colors.blue.shade600),
                          const SizedBox(width: 8),
                          _buildCategoryChip('work', 'Kantor', Icons.business_rounded, Colors.purple.shade600),
                          const SizedBox(width: 8),
                          _buildCategoryChip('other', 'Lainnya', Icons.location_on_rounded, Colors.orange.shade700),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Name Input
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'Nama Tempat Aman',
                        hintText: 'Misal: Rumah Utama, SD Sukamaju',
                        prefixIcon: Icon(_getCategoryIcon(_category), color: themeColor),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Radius Selection Chips
                    Row(
                      children: [
                        const Text(
                          'Radius:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [100.0, 150.0, 300.0, 500.0, 1000.0].map((r) {
                                final isSelected = _radiusMeters == r;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 6.0),
                                  child: ChoiceChip(
                                    label: Text(r >= 1000 ? '${(r / 1000).toStringAsFixed(0)} km' : '${r.toInt()} m'),
                                    selected: isSelected,
                                    selectedColor: themeColor.withValues(alpha: 0.15),
                                    labelStyle: TextStyle(
                                      color: isSelected ? themeColor : Colors.black87,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      fontSize: 12,
                                    ),
                                    onSelected: (val) {
                                      if (val) setState(() => _radiusMeters = r);
                                    },
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Big Save Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: themeColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 2,
                        ),
                        icon: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Icon(Icons.check_circle_rounded),
                        label: Text(
                          _isSaving ? 'Menyimpan...' : 'Zona Aman Ada di Sini',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        onPressed: _isSaving ? null : _saveGeofence,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(String cat, String label, IconData icon, Color color) {
    final isSelected = _category == cat;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        setState(() {
          _category = cat;
          if (_nameController.text.isEmpty ||
              _nameController.text == 'Rumah' ||
              _nameController.text == 'Sekolah' ||
              _nameController.text == 'Kantor' ||
              _nameController.text == 'Tempat Aman') {
            _nameController.text = _getDefaultNameForCategory(cat);
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : Colors.black87),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.black87,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  final Color color;
  _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TrianglePainter oldDelegate) => oldDelegate.color != color;
}
