package com.lingkaraman.lingkar_aman

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

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

        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val isLostMode = prefs.getBoolean("flutter.lost_mode_active", false)
        val isSosPowerEnabled = prefs.getBoolean("flutter.sos_power_button_enabled", true)

        // 1. Pulihkan monitor tombol power darurat jika aktif
        if (isSosPowerEnabled) {
            try {
                SosPowerService.startService(context)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        // 2. Anti-Bypass: Jika Mode HP Hilang aktif sebelum reboot / cabut baterai,
        // aktifkan kembali perlindungan seketika tanpa jeda!
        if (isLostMode) {
            try {
                LostModeProtectionService.startService(context)

                // Siapkan Intent untuk membuka paksa layar kunci Lost Mode
                val lockIntent = Intent(context, MainActivity::class.java).apply {
                    this.action = "ACTION_LOST_MODE_LOCK"
                    putExtra("lost_mode_locked", true)
                    addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                    )
                }

                // Jalankan dengan AlarmManager agar sistem boot memprioritaskan peluncuran aktivitas
                val pendingIntent = PendingIntent.getActivity(
                    context,
                    9992,
                    lockIntent,
                    PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
                )

                val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
                alarmManager?.set(
                    AlarmManager.RTC_WAKEUP,
                    System.currentTimeMillis() + 800,
                    pendingIntent
                )

                // Coba jalankan langsung jika context mengizinkan
                try {
                    context.startActivity(lockIntent)
                } catch (_: Exception) {}
            } catch (e: Exception) {
                e.printStackTrace()
            }
        } else {
            // 3. Normal Boot: Jalankan aplikasi otomatis setelah handphone dinyalakan ulang (Auto-start on boot)
            try {
                val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                    ?: Intent(context, MainActivity::class.java).apply {
                        this.action = Intent.ACTION_MAIN
                        addCategory(Intent.CATEGORY_LAUNCHER)
                    }

                launchIntent.apply {
                    addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                    )
                }

                val pendingIntent = PendingIntent.getActivity(
                    context,
                    9991,
                    launchIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )

                // Jadwalkan peluncuran otomatis melalui AlarmManager 1 detik setelah boot
                val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
                alarmManager?.set(
                    AlarmManager.RTC_WAKEUP,
                    System.currentTimeMillis() + 1000,
                    pendingIntent
                )

                // Tampilkan notifikasi dengan full-screen intent agar langsung membuka aplikasi pada lockscreen/startup
                showBootAutoStartNotification(context, pendingIntent)

                // Coba panggil startActivity langsung jika sistem mengizinkan
                try {
                    context.startActivity(launchIntent)
                } catch (_: Exception) {}
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    private fun showBootAutoStartNotification(context: Context, pendingIntent: PendingIntent) {
        try {
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
            val channelId = "lingkaraman_autostart_channel"

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    channelId,
                    "LingkarAman Mulai Otomatis",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Memastikan aplikasi langsung berjalan dan melindungi keluarga setelah handphone dinyalakan"
                    setShowBadge(true)
                }
                notificationManager.createNotificationChannel(channel)
            }

            val notification = NotificationCompat.Builder(context, channelId)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("LingkarAman Aktif")
                .setContentText("Aplikasi berjalan otomatis untuk melindungi keluarga.")
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_STATUS)
                .setContentIntent(pendingIntent)
                .setFullScreenIntent(pendingIntent, false)
                .setAutoCancel(true)
                .build()

            notificationManager.notify(9995, notification)
        } catch (_: Exception) {}
    }
}
