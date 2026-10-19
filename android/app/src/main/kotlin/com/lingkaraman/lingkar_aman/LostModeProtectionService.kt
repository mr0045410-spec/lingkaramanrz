package com.lingkaraman.lingkar_aman

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class LostModeProtectionService : Service() {

    companion object {
        const val CHANNEL_ID = "lost_mode_protection_channel"
        const val NOTIFICATION_ID = 3001
        const val PREFS_NAME = "FlutterSharedPreferences"
        const val KEY_LOST_MODE_ACTIVE = "flutter.lost_mode_active"
        const val KEY_CONTACT_PHONE = "flutter.lost_mode_contact_phone"
        const val KEY_MESSAGE = "flutter.lost_mode_message"
        const val KEY_SIREN = "flutter.lost_mode_siren"

        fun startService(context: Context) {
            val intent = Intent(context, LostModeProtectionService::class.java)
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
            val intent = Intent(context, LostModeProtectionService::class.java)
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
        startForeground(NOTIFICATION_ID, buildLockNotification())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val isActive = prefs.getBoolean(KEY_LOST_MODE_ACTIVE, false)
        if (!isActive) {
            stopSelf()
            return START_NOT_STICKY
        }

        // Update notification in case message or phone changed
        val manager = getSystemService(NotificationManager::class.java)
        manager?.notify(NOTIFICATION_ID, buildLockNotification())

        return START_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Mode HP Hilang & Anti-Maling LingkarAman",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifikasi darurat terkunci saat ponsel dalam status hilang"
                setShowBadge(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                enableVibration(true)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    private fun buildLockNotification(): Notification {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val contactPhone = prefs.getString(KEY_CONTACT_PHONE, "") ?: ""
        val customMsg = prefs.getString(KEY_MESSAGE, "") ?: ""

        val lockIntent = Intent(this, MainActivity::class.java).apply {
            action = "ACTION_LOST_MODE_LOCK"
            putExtra("lost_mode_locked", true)
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
            )
        }

        val pendingIntent = PendingIntent.getActivity(
            this,
            NOTIFICATION_ID,
            lockIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val contentText = if (contactPhone.isNotEmpty()) {
            "Perangkat Terkunci. Hubungi: $contactPhone"
        } else if (customMsg.isNotEmpty()) {
            customMsg
        } else {
            "HP ini dalam mode hilang. Segera hubungi pemilik untuk membuka kunci."
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("⚠️ HP INI DALAM MODE HILANG")
            .setContentText(contentText)
            .setSubText("LingkarAman Anti-Maling")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(pendingIntent)
            .setFullScreenIntent(pendingIntent, true)
            .build()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val isLostMode = prefs.getBoolean(KEY_LOST_MODE_ACTIVE, false)

        if (isLostMode) {
            // Anti-Bypass: Pencuri berusaha menghapus aplikasi dari Recent Apps / Clear Memory
            // Segera jadwalkan AlarmManager untuk membangkitkan MainActivity & Service kembali
            val restartIntent = Intent(applicationContext, MainActivity::class.java).apply {
                action = "ACTION_LOST_MODE_LOCK"
                putExtra("lost_mode_locked", true)
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                )
            }

            val restartPendingIntent = PendingIntent.getActivity(
                applicationContext,
                9991,
                restartIntent,
                PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
            )

            val alarmManager = getSystemService(Context.ALARM_SERVICE) as? AlarmManager
            alarmManager?.set(
                AlarmManager.RTC_WAKEUP,
                System.currentTimeMillis() + 300,
                restartPendingIntent
            )

            // Coba buka MainActivity langsung
            try {
                applicationContext.startActivity(restartIntent)
            } catch (_: Exception) {}

            // Re-trigger startService
            startService(applicationContext)
        }

        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
