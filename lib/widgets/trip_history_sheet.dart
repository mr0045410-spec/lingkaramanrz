import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';

class TripHistorySheet extends StatefulWidget {
  final CircleMember member;
  final CircleModel circle;
  final void Function(List<TripPoint> points)? onShowOnMap;

  const TripHistorySheet({
    super.key,
    required this.member,
    required this.circle,
    this.onShowOnMap,
  });

  static Future<void> show(
    BuildContext context,
    CircleMember member,
    CircleModel circle, {
    void Function(List<TripPoint> points)? onShowOnMap,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => TripHistorySheet(
        member: member,
        circle: circle,
        onShowOnMap: onShowOnMap,
      ),
    );
  }

  @override
  State<TripHistorySheet> createState() => _TripHistorySheetState();
}

class _TripHistorySheetState extends State<TripHistorySheet> {
  final SupabaseService _supa = SupabaseService();
  bool _isLoading = true;
  List<TripPoint> _points = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final data = await _supa.getLocationHistory(widget.member.userId, limit: 100);
      if (mounted) {
        setState(() {
          _points = data;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final memberName = widget.member.profile?.fullName ?? 'Anggota';
    final isMe = widget.member.userId == _supa.currentUser?.id;
    final displayName = isMe ? '$memberName (Saya)' : memberName;
    final isAdmin = widget.member.isAdmin;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) {
        return Column(
          children: [
            // Drag Handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
            ),

            // Header Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: isMe ? Colors.blue.shade600 : Colors.teal.shade600,
                    child: Text(
                      displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                displayName,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isAdmin ? Colors.amber.shade100 : Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isAdmin ? '👑 Admin Utama' : '👤 Anggota',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isAdmin ? Colors.orange.shade900 : Colors.blue.shade800,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Linimasa Perjalanan • ${widget.circle.name}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.blue),
                    tooltip: 'Segarkan Riwayat',
                    onPressed: _loadHistory,
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Quick Stats Banner
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade50, Colors.indigo.shade50],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem(
                    icon: Icons.timeline,
                    iconColor: Colors.blue.shade700,
                    title: 'Titik Jejak',
                    value: '${_points.length} Titik',
                  ),
                  Container(width: 1, height: 28, color: Colors.blue.shade200),
                  _buildStatItem(
                    icon: Icons.speed,
                    iconColor: Colors.purple.shade700,
                    title: 'Status Kecepatan',
                    value: _points.isNotEmpty && _points.first.speed > 1.5
                        ? '${(_points.first.speed * 3.6).toStringAsFixed(1)} km/j'
                        : 'Diam / Singgah',
                  ),
                  Container(width: 1, height: 28, color: Colors.blue.shade200),
                  _buildStatItem(
                    icon: Icons.battery_charging_full,
                    iconColor: Colors.green.shade700,
                    title: 'Baterai Saat Ini',
                    value: _points.isNotEmpty ? '${_points.first.batteryLevel}%' : '-',
                  ),
                ],
              ),
            ),

            // Action: View on map
            if (_points.isNotEmpty && widget.onShowOnMap != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3A8A),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    icon: const Icon(Icons.map, size: 18),
                    label: const Text('Gambarkan Jejak Rute di Peta', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onShowOnMap?.call(_points);
                    },
                  ),
                ),
              ),

            // Timeline Content List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _points.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.history_toggle_off, size: 64, color: Colors.grey.shade400),
                                const SizedBox(height: 12),
                                const Text(
                                  'Belum Ada Riwayat Perjalanan',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Riwayat koordinat dan rute pergerakan anggota akan otomatis terekam saat ponsel anggota aktif bergerak.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadHistory,
                          child: ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                            itemCount: _points.length,
                            itemBuilder: (context, index) {
                              final pt = _points[index];
                              final isFirst = index == 0;
                              final isLast = index == _points.length - 1;
                              final timeStr = DateFormat('HH:mm').format(pt.recordedAt);
                              final dateStr = DateFormat('dd MMM yyyy').format(pt.recordedAt);
                              final speedKmh = pt.speed * 3.6;
                              final isMoving = speedKmh >= 2.0;

                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Time column
                                  SizedBox(
                                    width: 55,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          timeStr,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: isFirst ? FontWeight.bold : FontWeight.w600,
                                            color: isFirst ? Colors.blue.shade900 : Colors.black87,
                                          ),
                                        ),
                                        Text(
                                          dateStr,
                                          style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
                                        ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(width: 10),

                                  // Timeline Line & Node
                                  Column(
                                    children: [
                                      Container(
                                        width: 14,
                                        height: 14,
                                        decoration: BoxDecoration(
                                          color: isFirst
                                              ? Colors.blue.shade600
                                              : (isMoving ? Colors.teal.shade500 : Colors.grey.shade400),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: isFirst ? Colors.blue.shade100 : Colors.white,
                                            width: isFirst ? 3 : 2,
                                          ),
                                          boxShadow: isFirst
                                              ? [BoxShadow(color: Colors.blue.withValues(alpha: 0.4), blurRadius: 4)]
                                              : null,
                                        ),
                                      ),
                                      if (!isLast)
                                        Container(
                                          width: 2,
                                          height: 48,
                                          color: Colors.grey.shade200,
                                        ),
                                    ],
                                  ),

                                  const SizedBox(width: 12),

                                  // Details Card
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: isFirst ? Colors.blue.shade50.withValues(alpha: 0.5) : Colors.grey.shade50,
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: isFirst ? Colors.blue.shade200 : Colors.grey.shade200,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(
                                                  isMoving ? Icons.directions_walk : Icons.place,
                                                  size: 14,
                                                  color: isMoving ? Colors.teal.shade700 : Colors.grey.shade700,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  isMoving
                                                      ? 'Bergerak (${speedKmh.toStringAsFixed(1)} km/j)'
                                                      : 'Singgah / Berhenti',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    color: isMoving ? Colors.teal.shade900 : Colors.grey.shade800,
                                                  ),
                                                ),
                                                const Spacer(),
                                                Icon(Icons.battery_std, size: 12, color: Colors.grey.shade600),
                                                Text(
                                                  '${pt.batteryLevel}%',
                                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Koordinat: ${pt.latitude.toStringAsFixed(5)}, ${pt.longitude.toStringAsFixed(5)}',
                                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 4),
            Text(title, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
          ],
        ),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
