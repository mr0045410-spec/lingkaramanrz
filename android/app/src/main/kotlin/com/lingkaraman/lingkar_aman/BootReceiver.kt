package com.lingkaraman.lingkar_aman

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) return

        val action = intent.action ?: return
        val validActions = listOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON",
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_USER_PRESENT
        )

        if (!validActions.contains(action)) return

        val isLost = isLostModeActive(context)

        // 1. Pulihkan monitor tombol power darurat jika aktif
        val isSosPowerEnabled = try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.getBoolean("flutter.sos_power_button_enabled", true)
        } catch (_: Exception) {
            true
        }

        if (isSosPowerEnabled) {
            try {
                SosPowerService.startService(context)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        // 2. Anti-Bypass: Jika Mode HP Hilang aktif sebelum reboot / cabut baterai,
        // aktifkan kembali perlindungan dan notifikasi persisten seketika tanpa jeda!
        if (isLost) {
            try {
                LostModeProtectionService.startService(context)

                // Siapkan Intent untuk membuka paksa layar kunci Lost Mode
                val lockIntent = Intent(context, MainActivity::class.java).apply {
                    this.action = "ACTION_LOST_MODE_LOCK"
                    putExtra("lost_mode_locked", true)
                    addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                    )
                }

                // Jalankan dengan AlarmManager agar sistem boot memprioritaskan peluncuran aktivitas
                val pendingIntent = PendingIntent.getActivity(
                    context,
                    9992,
                    lockIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )

                val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
                alarmManager?.set(
                    AlarmManager.RTC_WAKEUP,
                    System.currentTimeMillis() + 800,
                    pendingIntent
                )

                // Coba jalankan langsung jika context mengizinkan
                try {
                    InternalIntentGuard.signIntent(context, lockIntent)
                context.startActivity(lockIntent)
                } catch (_: Exception) {}
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    private fun isLostModeActive(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                val directContext = context.createDeviceProtectedStorageContext()
                val directPrefs = directContext.getSharedPreferences("lingkaraman_direct_boot_prefs", Context.MODE_PRIVATE)
                if (directPrefs.contains("lost_mode_active")) {
                    return directPrefs.getBoolean("lost_mode_active", false)
                }
            } catch (_: Exception) {}
        }
        return try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.getBoolean("flutter.lost_mode_active", false)
        } catch (_: Exception) {
            false
        }
    }
}
