package com.lingkaraman.lingkar_aman

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.IBinder
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat

class SosPowerService : Service() {
    private var screenReceiver: BroadcastReceiver? = null
    private val screenEvents = mutableListOf<Long>()

    companion object {
        const val CHANNEL_ID = "sos_power_monitor_channel"
        const val NOTIFICATION_ID = 2001
        const val PREFS_NAME = "FlutterSharedPreferences"
        const val KEY_POWER_ENABLED = "flutter.sos_power_button_enabled"
        const val KEY_POWER_COUNT = "flutter.sos_power_button_count"

        fun startService(context: Context) {
            val intent = Intent(context, SosPowerService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        fun stopService(context: Context) {
            val intent = Intent(context, SosPowerService::class.java)
            try {
                context.stopService(intent)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification())
        registerScreenReceiver()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Monitor Tombol Darurat LingkarAman",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Memonitor tombol power fisik untuk darurat SOS"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("LingkarAman Siaga Darurat")
            .setContentText("Deteksi tombol power cepat aktif untuk perlindungan")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .build()
    }

    private fun registerScreenReceiver() {
        if (screenReceiver != null) return

        screenReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val action = intent?.action ?: return
                if (action == Intent.ACTION_SCREEN_ON || action == Intent.ACTION_SCREEN_OFF) {
                    handleScreenToggle()
                }
            }
        }

        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
        }
        registerReceiver(screenReceiver, filter)
    }

    private fun handleScreenToggle() {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val isEnabled = prefs.getBoolean(KEY_POWER_ENABLED, true)
        if (!isEnabled) return

        val requiredCount = prefs.getLong(KEY_POWER_COUNT, 3L).toInt()
        val now = System.currentTimeMillis()

        synchronized(screenEvents) {
            // Remove events older than 2500 ms
            screenEvents.removeAll { now - it > 2500 }
            screenEvents.add(now)

            if (screenEvents.size >= requiredCount) {
                screenEvents.clear()
                triggerSos()
            }
        }
    }

    private fun triggerSos() {
        // Vibrate phone with distinctive SOS tactile pattern
        vibratePattern()

        // Launch MainActivity with trigger extra
        val sosIntent = Intent(this, MainActivity::class.java).apply {
            action = "ACTION_TRIGGER_SOS"
            putExtra("trigger_sos_immediately", true)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        startActivity(sosIntent)

        // Trigger via direct sender (if Flutter is dead, sends direct HTTP POST to Supabase REST)
        SosDirectSender.triggerSos(this, "Tombol Fisik Power")
    }

    private fun vibratePattern() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                val vibrator = vibratorManager?.defaultVibrator
                vibrator?.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 400, 150, 400, 150, 600), -1))
            } else {
                @Suppress("DEPRECATION")
                val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator?.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 400, 150, 400, 150, 600), -1))
                } else {
                    @Suppress("DEPRECATION")
                    vibrator?.vibrate(longArrayOf(0, 400, 150, 400, 150, 600), -1)
                }
            }
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        screenReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {}
        }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
