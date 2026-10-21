import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Pill Baterai (misal: 73% dengan icon baterai berwarna)
class BatteryPill extends StatelessWidget {
  final int? batteryLevel;
  final bool isCharging;

  const BatteryPill({
    super.key,
    required this.batteryLevel,
    this.isCharging = false,
  });

  @override
  Widget build(BuildContext context) {
    final level = batteryLevel ?? 100;
    Color color = AppColors.statusSuccess;
    if (level <= 15) {
      color = AppColors.statusEmergency;
    } else if (level <= 30) {
      color = AppColors.statusWarning;
    }

    IconData icon = Icons.battery_full_rounded;
    if (isCharging) {
      icon = Icons.battery_charging_full_rounded;
    } else if (level <= 15) {
      icon = Icons.battery_alert_rounded;
    } else if (level <= 30) {
      icon = Icons.battery_3_bar_rounded;
    } else if (level <= 60) {
      icon = Icons.battery_5_bar_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
          Text(
            '$level%',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Badge Peran Anggota: "Admin Utama" (Emas/Kuning) atau "Anggota" (Soft Navy/Abu-abu)
class RoleBadge extends StatelessWidget {
  final String role; // 'admin' atau 'member'

  const RoleBadge({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    final isAdmin = role.toLowerCase() == 'admin';

    if (isAdmin) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF3C7), // Amber 100
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFDE68A), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.workspace_premium_rounded, size: 13, color: Color(0xFFD97706)),
            SizedBox(width: 4),
            Text(
              'Admin Utama',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFFB45309),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9), // Slate 100
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        'Anggota',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(0xFF64748B),
        ),
      ),
    );
  }
}

/// Avatar Tumpuk untuk Header Keluarga di Layar 1
class FamilyAvatarStack extends StatelessWidget {
  final List<String?> avatarUrls;
  final double size;

  const FamilyAvatarStack({
    super.key,
    required this.avatarUrls,
    this.size = 28,
  });

  @override
  Widget build(BuildContext context) {
    final displayUrls = avatarUrls.take(3).toList();
    if (displayUrls.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: AppColors.primaryNavy,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.people, color: Colors.white, size: 16),
      );
    }

    return SizedBox(
      width: size + ((displayUrls.length - 1) * (size * 0.55)),
      height: size,
      child: Stack(
        children: [
          for (int i = 0; i < displayUrls.length; i++)
            Positioned(
              left: i * (size * 0.55),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  color: AppColors.primaryNavy.withOpacity(0.1 + (i * 0.2)),
                  image: (displayUrls[i] != null && displayUrls[i]!.isNotEmpty)
                      ? DecorationImage(
                          image: NetworkImage(displayUrls[i]!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: (displayUrls[i] == null || displayUrls[i]!.isEmpty)
                    ? Icon(Icons.person, size: size * 0.6, color: AppColors.primaryNavy)
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

/// Kartu Aksi Cepat Warna (Layar 8 Detail Anggota)
class ActionTileButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onTap;

  const ActionTileButton({
    super.key,
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 76,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: foregroundColor, size: 22),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foregroundColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
