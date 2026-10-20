package com.lingkaraman.lingkar_aman



import android.app.ActivityManager

import android.app.AppOpsManager

import android.app.Notification

import android.app.NotificationChannel

import android.app.NotificationManager

import android.app.PendingIntent

import android.app.usage.UsageStatsManager

import android.content.Context

import android.content.Intent

import android.content.pm.ShortcutInfo

import android.content.pm.ShortcutManager

import android.graphics.drawable.Icon

import android.media.AudioAttributes

import android.media.AudioManager

import android.media.MediaPlayer

import android.media.Ringtone

import android.media.RingtoneManager

import android.media.ToneGenerator

import android.net.Uri

import android.os.Build

import android.os.Bundle

import android.os.Process

import android.os.VibrationEffect

import android.os.Vibrator

import android.os.VibratorManager

import android.graphics.PixelFormat

import android.provider.Settings

import android.view.Gravity

import android.view.View

import android.view.WindowInsets

import android.view.WindowInsetsController

import android.view.WindowManager

import io.flutter.embedding.android.FlutterActivity

import io.flutter.embedding.engine.FlutterEngine

import io.flutter.plugin.common.MethodChannel

import java.util.Calendar



class MainActivity : FlutterActivity() {

    private val SOS_CHANNEL = "com.lingkaraman.lingkar_aman/sos_triggers"

    private val LOUD_SIGNAL_CHANNEL = "com.lingkaraman.lingkar_aman/loud_signal"

    private val APP_USAGE_CHANNEL = "com.lingkaraman.lingkar_aman/app_usage"

    private val LOST_MODE_CHANNEL = "com.lingkaraman.lingkar_aman/lost_mode_protection"

    private val GPS_CHANNEL = "com.lingkaraman.lingkar_aman/gps_status"

    private val GPS_NOTIFICATION_ID = 888999

    private val GPS_NOTIFICATION_CHANNEL_ID = "lingkaraman_gps_alert"

    private val SOUND_CHANNEL = "com.lingkaraman.lingkar_aman/sound_settings"
    private val OEM_SECURITY_CHANNEL = "com.lingkaraman.lingkar_aman/oem_security"

    private val CHAT_NOTIFICATION_CHANNEL_ID = "lingkaraman_chat_alert"

    private val CHAT_NOTIFICATION_ID = 777888

    private val EMERGENCY_NOTIFICATION_CHANNEL_ID = "lingkaraman_emergency_alert"

    private val EMERGENCY_NOTIFICATION_ID = 999111



    private var statusBarBlockerView: View? = null

    private var initialSosTrigger: Boolean = false

    private var initialLostModeLock: Boolean = false

    private var initialOpenChatTrigger: Boolean = false

    private var alarmPlayer: MediaPlayer? = null

    private var alarmRingtone: Ringtone? = null

    private var previewTone: ToneGenerator? = null

    private var previewRingtone: Ringtone? = null



    companion object {

        var activeSosChannel: MethodChannel? = null

        var activeLoudChannel: MethodChannel? = null

        var activeLostModeChannel: MethodChannel? = null

        var activeSoundChannel: MethodChannel? = null



        fun notifySosTriggered() {

            activeSosChannel?.invokeMethod("onSosTriggered", null)

        }



        fun notifyLostModeTriggered() {

            activeLostModeChannel?.invokeMethod("onLostModeLockTriggered", null)

        }



        fun notifyOpenChat() {

            activeSoundChannel?.invokeMethod("onOpenChatTriggered", null)

        }

    }



    override fun onCreate(savedInstanceState: Bundle?) {

        super.onCreate(savedInstanceState)



        if (intent?.getBooleanExtra("trigger_sos_immediately", false) == true) {

            initialSosTrigger = true

        }

        if (intent?.getBooleanExtra("lost_mode_locked", false) == true || isLostModeActive()) {

            initialLostModeLock = true

            applyLockWindowFlags(true)

        }

        if (intent?.action == "ACTION_OPEN_CHAT") {

            initialOpenChatTrigger = true

        }

    }



    override fun onResume() {

        super.onResume()

    }



    override fun onNewIntent(intent: Intent) {

        super.onNewIntent(intent)

        setIntent(intent)

        if (intent.getBooleanExtra("trigger_sos_immediately", false)) {

            notifySosTriggered()

        }

        if (intent.getBooleanExtra("lost_mode_locked", false) || isLostModeActive()) {

            applyLockWindowFlags(true)

            notifyLostModeTriggered()

        }

        if (intent.action == "ACTION_OPEN_CHAT") {

            notifyOpenChat()

        }

    }



    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {

        super.configureFlutterEngine(flutterEngine)



        // 1. SOS Channel

        val sosChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SOS_CHANNEL)

        activeSosChannel = sosChannel



        sosChannel.setMethodCallHandler { call, result ->

            when (call.method) {

                "getInitialSosTrigger" -> {

                    val trigger = initialSosTrigger

                    initialSosTrigger = false

                    result.success(trigger)

                }

                "updatePowerButtonSettings" -> {

                    val enabled = call.argument<Boolean>("enabled") ?: true

                    val count = call.argument<Int>("count") ?: 3



                    val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

                    prefs.edit()

                        .putBoolean("flutter.sos_power_button_enabled", enabled)

                        .putLong("flutter.sos_power_button_count", count.toLong())

                        .apply()



                    if (enabled) {

                        SosPowerService.startService(this)

                    } else {

                        SosPowerService.stopService(this)

                    }

                    result.success(true)

                }

                "pinSosShortcut" -> {

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {

                        val shortcutManager = getSystemService(ShortcutManager::class.java)

                        if (shortcutManager != null && shortcutManager.isRequestPinShortcutSupported) {

                            val pinIntent = Intent(this, MainActivity::class.java).apply {

                                action = "ACTION_TRIGGER_SOS"

                                putExtra("trigger_sos_immediately", true)

                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)

                            }

                            val pinShortcutInfo = ShortcutInfo.Builder(this, "sos_shortcut")

                                .setShortLabel("SOS Darurat")

                                .setLongLabel("Kirim Sinyal SOS Darurat")

                                .setIcon(Icon.createWithResource(this, R.mipmap.ic_launcher))

                                .setIntent(pinIntent)

                                .build()



                            val pinnedShortcutCallbackIntent = shortcutManager.createShortcutResultIntent(pinShortcutInfo)

                            val successCallback = PendingIntent.getBroadcast(

                                this, 0, pinnedShortcutCallbackIntent,

                                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

                            )



                            val requested = shortcutManager.requestPinShortcut(pinShortcutInfo, successCallback.intentSender)

                            result.success(requested)

                        } else {

                            result.error("UNSUPPORTED", "Launcher tidak mendukung pin shortcut", null)

                        }

                    } else {

                        result.error("UNSUPPORTED", "Versi Android tidak mendukung pin shortcut", null)

                    }

                }

                "isPinShortcutSupported" -> {

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {

                        val shortcutManager = getSystemService(ShortcutManager::class.java)

                        result.success(shortcutManager?.isRequestPinShortcutSupported == true)

                    } else {

                        result.success(false)

                    }

                }

                else -> result.notImplemented()

            }

        }



        // 2. Loud Signal Channel (Bypass Silent/DND)

        val loudChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOUD_SIGNAL_CHANNEL)

        activeLoudChannel = loudChannel



        loudChannel.setMethodCallHandler { call, result ->

            when (call.method) {

                "playLoudAlarm" -> {

                    try {

                        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager



                        // 1. Keluar dari mode hening/getar (Silent / Vibrate) paksa ke RINGER_MODE_NORMAL

                        try {

                            audioManager.ringerMode = AudioManager.RINGER_MODE_NORMAL

                        } catch (_: Exception) {}



                        // 2. Maksimalkan volume di semua saluran audio darurat

                        val targetStreams = intArrayOf(

                            AudioManager.STREAM_ALARM,

                            AudioManager.STREAM_MUSIC,

                            AudioManager.STREAM_RING,

                            AudioManager.STREAM_NOTIFICATION

                        )

                        for (st in targetStreams) {

                            try {

                                val max = audioManager.getStreamMaxVolume(st)

                                audioManager.setStreamVolume(st, max, 0)

                            } catch (_: Exception) {}

                        }



                        stopLoudAlarmInternal()



                        // 3. AudioAttributes USAGE_ALARM + FLAG_AUDIBILITY_ENFORCED agar tembus silent mode OS

                        val audioAttributes = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {

                            AudioAttributes.Builder()

                                .setUsage(AudioAttributes.USAGE_ALARM)

                                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)

                                .setFlags(AudioAttributes.FLAG_AUDIBILITY_ENFORCED)

                                .build()

                        } else {

                            null

                        }



                        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

                        val chosenSound = prefs.getString("flutter.ringtone_loud_signal", "radar_beep") ?: "radar_beep"



                        val alertUri: Uri? = if (chosenSound == "system_ringtone") {

                            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)

                                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)

                        } else {

                            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)

                                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)

                                ?: Settings.System.DEFAULT_ALARM_ALERT_URI

                        }



                        var mpStarted = false

                        if (alertUri != null) {

                            try {

                                alarmPlayer = MediaPlayer().apply {

                                    if (audioAttributes != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {

                                        setAudioAttributes(audioAttributes)

                                    } else {

                                        @Suppress("DEPRECATION")

                                        setAudioStreamType(AudioManager.STREAM_ALARM)

                                    }

                                    setDataSource(applicationContext, alertUri)

                                    isLooping = true

                                    setVolume(1.0f, 1.0f)

                                    prepare()

                                    start()

                                }

                                mpStarted = true

                            } catch (e: Exception) {

                                e.printStackTrace()

                            }

                        }



                        if (!mpStarted) {

                            if (alertUri != null) {

                                alarmRingtone = RingtoneManager.getRingtone(applicationContext, alertUri)?.apply {

                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP && audioAttributes != null) {

                                        this.audioAttributes = audioAttributes

                                    }

                                    play()

                                }

                            }

                            playSoundTone(chosenSound)

                        }



                        // Alarm vibration

                        vibrateAlarm()

                        result.success(true)

                    } catch (e: Exception) {

                        result.error("PLAY_ERROR", e.message, null)

                    }

                }

                "stopLoudAlarm" -> {

                    try {

                        stopLoudAlarmInternal()

                        result.success(true)

                    } catch (e: Exception) {

                        result.error("STOP_ERROR", e.message, null)

                    }

                }

                else -> result.notImplemented()

            }

        }



        // 3. App Usage Statistics Channel

        val appUsageChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_USAGE_CHANNEL)

        appUsageChannel.setMethodCallHandler { call, result ->

            when (call.method) {

                "hasUsagePermission" -> {

                    val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager

                    val mode = appOps.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)

                    result.success(mode == AppOpsManager.MODE_ALLOWED)

                }

                "openUsageSettings" -> {

                    try {

                        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {

                            flags = Intent.FLAG_ACTIVITY_NEW_TASK

                        }

                        startActivity(intent)

                        result.success(true)

                    } catch (e: Exception) {

                        result.error("OPEN_SETTINGS_ERROR", e.message, null)

                    }

                }

                "getTodayAppUsage" -> {

                    try {

                        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager

                        val calendar = Calendar.getInstance().apply {

                            set(Calendar.HOUR_OF_DAY, 0)

                            set(Calendar.MINUTE, 0)

                            set(Calendar.SECOND, 0)

                            set(Calendar.MILLISECOND, 0)

                        }

                        val startTime = calendar.timeInMillis

                        val endTime = System.currentTimeMillis()



                        val aggregatedStats = usageStatsManager.queryAndAggregateUsageStats(startTime, endTime)

                        val pm = packageManager

                        val results = mutableListOf<Map<String, Any>>()



                        aggregatedStats.values

                            .filter { it.totalTimeInForeground > 60000 } // Used more than 1 minute (60,000 ms)

                            .sortedByDescending { it.totalTimeInForeground }

                            .take(25)

                            .forEach { u ->

                                val appName = try {

                                    val appInfo = pm.getApplicationInfo(u.packageName, 0)

                                    pm.getApplicationLabel(appInfo).toString()

                                } catch (_: Exception) {

                                    u.packageName.substringAfterLast('.')

                                }



                                results.add(

                                    mapOf(

                                        "packageName" to u.packageName,

                                        "appName" to appName,

                                        "totalTimeSeconds" to (u.totalTimeInForeground / 1000).toInt(),

                                        "lastTimeUsed" to u.lastTimeUsed

                                    )

                                )

                            }



                        result.success(results)

                    } catch (e: Exception) {

                        result.error("USAGE_STATS_ERROR", e.message, null)

                    }

                }

                else -> result.notImplemented()

            }

        }



        // 4. Lost Mode Anti-Theft Protection Channel

        val lostModeChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOST_MODE_CHANNEL)

        activeLostModeChannel = lostModeChannel



        lostModeChannel.setMethodCallHandler { call, result ->

            when (call.method) {

                "getInitialLostModeLock" -> {

                    val locked = initialLostModeLock || isLostModeActive()

                    initialLostModeLock = false

                    result.success(locked)

                }

                "enableAntiBypass" -> {

                    val phone = call.argument<String>("contactPhone") ?: ""

                    val msg = call.argument<String>("message") ?: ""

                    val siren = call.argument<Boolean>("enableSiren") ?: true



                    saveLostModeState(true, phone, msg, siren)



                    applyLockWindowFlags(true)

                    setRecentsExclusion(true)

                    LostModeProtectionService.startService(this)



                    result.success(true)

                }

                "disableAntiBypass" -> {

                    saveLostModeState(false, "", "", false)



                    applyLockWindowFlags(false)

                    setRecentsExclusion(false)

                    LostModeProtectionService.stopService(this)



                    result.success(true)

                }

                "isAntiBypassActive" -> {

                    result.success(isLostModeActive())

                }

                "hasOverlayPermission" -> {

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {

                        result.success(Settings.canDrawOverlays(this))

                    } else {

                        result.success(true)

                    }

                }

                "requestOverlayPermission" -> {

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {

                        try {

                            val intent = Intent(

                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,

                                Uri.parse("package:$packageName")

                            ).apply {

                                flags = Intent.FLAG_ACTIVITY_NEW_TASK

                            }

                            startActivity(intent)

                        } catch (_: Exception) {

                            try {

                                val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION).apply {

                                    flags = Intent.FLAG_ACTIVITY_NEW_TASK

                                }

                                startActivity(intent)

                            } catch (_: Exception) {}

                        }

                    }

                    result.success(true)

                }

                else -> result.notImplemented()

            }

        }



        // 5. GPS Status & Notification Channel

        val gpsChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, GPS_CHANNEL)

        gpsChannel.setMethodCallHandler { call, result ->

            when (call.method) {

                "showGpsNotification" -> {

                    showGpsDisabledNotification()

                    result.success(true)

                }

                "cancelGpsNotification" -> {

                    cancelGpsDisabledNotification()

                    result.success(true)

                }

                "openGpsSettings" -> {

                    try {

                        val intent = Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS).apply {

                            flags = Intent.FLAG_ACTIVITY_NEW_TASK

                        }

                        startActivity(intent)

                        result.success(true)

                    } catch (e: Exception) {

                        result.error("OPEN_SETTINGS_ERROR", e.message, null)

                    }

                }

                else -> result.notImplemented()

            }

        }



        // 6. Sound Settings & Chat Notification Channel

        val soundChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SOUND_CHANNEL)

        activeSoundChannel = soundChannel

        soundChannel.setMethodCallHandler { call, result ->

            when (call.method) {

                "getInitialOpenChatTrigger" -> {

                    val trigger = initialOpenChatTrigger

                    initialOpenChatTrigger = false

                    result.success(trigger)

                }

                "previewSound" -> {

                    val soundId = call.argument<String>("soundId") ?: "bubble_pop"

                    playSoundTone(soundId)

                    result.success(true)

                }

                "stopPreview" -> {

                    stopSoundPreview()

                    result.success(true)

                }

                "showChatNotification" -> {

                    val title = call.argument<String>("title") ?: "Pesan Obrolan Baru"

                    val message = call.argument<String>("message") ?: ""

                    val soundId = call.argument<String>("soundId") ?: "bubble_pop"

                    showChatNotification(title, message, soundId)

                    result.success(true)

                }

                "showEmergencyNotification" -> {

                    val title = call.argument<String>("title") ?: "🚨 Mode HP Hilang Aktif"

                    val message = call.argument<String>("message") ?: "Perangkat anggota sedang dikunci & dilacak."

                    showEmergencyNotification(title, message)

                    result.success(true)

                }

                "cancelEmergencyNotification" -> {

                    cancelEmergencyNotification()

                    result.success(true)

                }

                else -> result.notImplemented()

            }

        }

        // 7. OEM Security & Accessibility Channel
        val oemChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OEM_SECURITY_CHANNEL)
        oemChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getDeviceInfo" -> {
                    val info = mapOf(
                        "manufacturer" to OemWhitelistHelper.getManufacturer(),
                        "brandDisplayName" to OemWhitelistHelper.getBrandDisplayName(),
                        "isKnownVendor" to true
                    )
                    result.success(info)
                }
                "openAutostartSettings" -> {
                    val opened = OemWhitelistHelper.openAutostartSettings(this)
                    result.success(opened)
                }
                "isAccessibilityServiceEnabled" -> {
                    val isEnabled = isAccessibilityServiceEnabledInternal()
                    result.success(isEnabled)
                }
                "openAccessibilitySettings" -> {
                    val opened = openAccessibilitySettingsInternal()
                    result.success(opened)
                }
                else -> result.notImplemented()
            }
        }

    }



    



    
    private fun isAccessibilityServiceEnabledInternal(): Boolean {
        return try {
            if (AntiShutdownAccessibilityService.isRunning) return true
            val expectedComponentName = "com.lingkaraman.lingkar_aman/.AntiShutdownAccessibilityService"
            val altComponentName = "com.lingkaraman.lingkar_aman/com.lingkaraman.lingkar_aman.AntiShutdownAccessibilityService"
            val enabledServices = Settings.Secure.getString(
                contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ) ?: ""
            val colonSplitter = android.text.TextUtils.SimpleStringSplitter(':')
            colonSplitter.setString(enabledServices)
            while (colonSplitter.hasNext()) {
                val componentName = colonSplitter.next()
                if (componentName.equals(expectedComponentName, ignoreCase = true) ||
                    componentName.equals(altComponentName, ignoreCase = true) ||
                    componentName.contains("AntiShutdownAccessibilityService", ignoreCase = true)) {
                    return true
                }
            }
            false
        } catch (_: Exception) {
            false
        }
    }

    private fun openAccessibilitySettingsInternal(): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }


    private fun showGpsDisabledNotification() {

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {

            val channel = NotificationChannel(

                GPS_NOTIFICATION_CHANNEL_ID,

                "Peringatan Status GPS",

                NotificationManager.IMPORTANCE_HIGH

            ).apply {

                description = "Peringatan ketika GPS / Layar Lokasi ponsel belum diaktifkan"

                setShowBadge(true)

            }

            manager.createNotificationChannel(channel)

        }



        val settingsIntent = Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS).apply {

            flags = Intent.FLAG_ACTIVITY_NEW_TASK

        }

        val pendingIntent = PendingIntent.getActivity(

            this,

            GPS_NOTIFICATION_ID,

            settingsIntent,

            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

        )



        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {

            Notification.Builder(this, GPS_NOTIFICATION_CHANNEL_ID)

        } else {

            Notification.Builder(this)

        }



        val notif = builder

            .setContentTitle("⚠️ GPS Belum Dinyalakan!")

            .setContentText("Ketuk untuk menyalakan GPS agar posisi Anda terpantau keluarga.")

            .setSmallIcon(R.mipmap.ic_launcher)

            .setContentIntent(pendingIntent)

            .setAutoCancel(true)

            .setOngoing(true)

            .build()



        manager.notify(GPS_NOTIFICATION_ID, notif)

    }



    private fun cancelGpsDisabledNotification() {

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager

        manager?.cancel(GPS_NOTIFICATION_ID)

    }



    private fun saveLostModeState(active: Boolean, phone: String, msg: String, siren: Boolean) {

        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

        prefs.edit()

            .putBoolean("flutter.lost_mode_active", active)

            .putString("flutter.lost_mode_contact_phone", phone)

            .putString("flutter.lost_mode_message", msg)

            .putBoolean("flutter.lost_mode_siren", siren)

            .apply()



        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {

            try {

                val directContext = createDeviceProtectedStorageContext()

                val directPrefs = directContext.getSharedPreferences("lingkaraman_direct_boot_prefs", Context.MODE_PRIVATE)

                directPrefs.edit()

                    .putBoolean("lost_mode_active", active)

                    .putString("lost_mode_contact_phone", phone)

                    .putString("lost_mode_message", msg)

                    .putBoolean("lost_mode_siren", siren)

                    .apply()

            } catch (e: Exception) {

                e.printStackTrace()

            }

        }

    }



    private fun isLostModeActive(): Boolean {

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {

            try {

                val directContext = createDeviceProtectedStorageContext()

                val directPrefs = directContext.getSharedPreferences("lingkaraman_direct_boot_prefs", Context.MODE_PRIVATE)

                if (directPrefs.contains("lost_mode_active")) {

                    return directPrefs.getBoolean("lost_mode_active", false)

                }

            } catch (_: Exception) {}

        }

        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

        return prefs.getBoolean("flutter.lost_mode_active", false)

    }



    private fun applyLockWindowFlags(enabled: Boolean) {

        try {

            if (enabled) {

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {

                    setShowWhenLocked(true)

                    setTurnScreenOn(true)

                } else {

                    @Suppress("DEPRECATION")

                    window.addFlags(

                        WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or

                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or

                        WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD

                    )

                }

                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)



                // Hide system bars and enable immersive sticky mode

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {

                    window.insetsController?.let { controller ->

                        controller.hide(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())

                        controller.systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE

                    }

                } else {

                    @Suppress("DEPRECATION")

                    window.decorView.systemUiVisibility = (

                        View.SYSTEM_UI_FLAG_FULLSCREEN or

                        View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or

                        View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or

                        View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or

                        View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or

                        View.SYSTEM_UI_FLAG_LAYOUT_STABLE

                    )

                }

                enableStatusBarBlocker(true)

            } else {

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {

                    setShowWhenLocked(false)

                    setTurnScreenOn(false)

                }

                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {

                    window.insetsController?.show(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())

                } else {

                    @Suppress("DEPRECATION")

                    window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_VISIBLE

                }

                enableStatusBarBlocker(false)

            }

        } catch (e: Exception) {

            e.printStackTrace()

        }

    }



    private fun getStatusBarHeight(): Int {

        var result = 0

        val resourceId = resources.getIdentifier("status_bar_height", "dimen", "android")

        if (resourceId > 0) {

            result = resources.getDimensionPixelSize(resourceId)

        }

        return if (result > 0) result else 120

    }



    private fun collapseStatusBar() {

        try {

            val statusBarService = getSystemService("statusbar")

            val statusBarManager = Class.forName("android.app.StatusBarManager")

            val collapse = statusBarManager.getMethod("collapsePanels")

            collapse.invoke(statusBarService)

        } catch (_: Exception) {}

        try {

            @Suppress("DEPRECATION")

            sendBroadcast(Intent(Intent.ACTION_CLOSE_SYSTEM_DIALOGS))

        } catch (_: Exception) {}

    }



    private fun enableStatusBarBlocker(enable: Boolean) {

        runOnUiThread {

            try {

                val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager

                if (enable) {

                    if (statusBarBlockerView == null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && Settings.canDrawOverlays(this)) {

                        val overlayType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {

                            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY

                        } else {

                            @Suppress("DEPRECATION")

                            WindowManager.LayoutParams.TYPE_PHONE

                        }

                        val params = WindowManager.LayoutParams(

                            WindowManager.LayoutParams.MATCH_PARENT,

                            getStatusBarHeight() + 70,

                            overlayType,

                            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or

                                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,

                            PixelFormat.TRANSLUCENT

                        ).apply {

                            gravity = Gravity.TOP or Gravity.FILL_HORIZONTAL

                        }



                        val view = View(this).apply {

                            setOnTouchListener { _, _ ->

                                collapseStatusBar()

                                true

                            }

                        }

                        wm.addView(view, params)

                        statusBarBlockerView = view

                    }

                } else {

                    statusBarBlockerView?.let { view ->

                        wm.removeView(view)

                    }

                    statusBarBlockerView = null

                }

            } catch (e: Exception) {

                e.printStackTrace()

            }

        }

    }



    private fun showEmergencyNotification(title: String, message: String) {

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {

            val channel = NotificationChannel(

                EMERGENCY_NOTIFICATION_CHANNEL_ID,

                "Peringatan Darurat & Mode Hilang",

                NotificationManager.IMPORTANCE_HIGH

            ).apply {

                description = "Status pemantauan darurat dan mode HP hilang"

                enableVibration(true)

                setShowBadge(true)

            }

            manager.createNotificationChannel(channel)

        }



        val launchIntent = Intent(this, MainActivity::class.java).apply {

            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP

        }

        val pendingIntent = PendingIntent.getActivity(

            this,

            EMERGENCY_NOTIFICATION_ID,

            launchIntent,

            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

        )



        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {

            Notification.Builder(this, EMERGENCY_NOTIFICATION_CHANNEL_ID)

        } else {

            @Suppress("DEPRECATION")

            Notification.Builder(this)

        }



        val notif = builder

            .setContentTitle(title)

            .setContentText(message)

            .setSmallIcon(R.mipmap.ic_launcher)

            .setContentIntent(pendingIntent)

            .setOngoing(true)

            .setAutoCancel(false)

            .setPriority(if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.PRIORITY_HIGH else Notification.PRIORITY_MAX)

            .build()



        manager.notify(EMERGENCY_NOTIFICATION_ID, notif)

    }



    private fun cancelEmergencyNotification() {

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager

        manager?.cancel(EMERGENCY_NOTIFICATION_ID)

    }



    private fun bringLockToFront() {

        try {

            val intent = Intent(this, MainActivity::class.java).apply {

                action = "ACTION_LOST_MODE_LOCK"

                putExtra("lost_mode_locked", true)

                addFlags(

                    Intent.FLAG_ACTIVITY_NEW_TASK or

                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or

                    Intent.FLAG_ACTIVITY_SINGLE_TOP

                )

            }

            startActivity(intent)

        } catch (e: Exception) {

            e.printStackTrace()

        }

    }



    override fun onUserLeaveHint() {

        super.onUserLeaveHint()

        if (isLostModeActive()) {

            bringLockToFront()

        }

    }



    override fun onPause() {

        super.onPause()

        if (isLostModeActive()) {

            bringLockToFront()

        }

    }



    override fun onWindowFocusChanged(hasFocus: Boolean) {

        super.onWindowFocusChanged(hasFocus)

        if (isLostModeActive()) {

            collapseStatusBar()

            applyLockWindowFlags(true)

            if (!hasFocus) {

                bringLockToFront()

            }

        }

    }



    private fun setRecentsExclusion(exclude: Boolean) {

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {

            try {

                val am = getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager

                val tasks = am?.appTasks

                if (!tasks.isNullOrEmpty()) {

                    tasks[0].setExcludeFromRecents(exclude)

                }

            } catch (e: Exception) {

                e.printStackTrace()

            }

        }

    }



    private fun vibrateAlarm() {

        try {

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {

                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager

                vibratorManager?.defaultVibrator?.vibrate(

                    VibrationEffect.createWaveform(longArrayOf(0, 800, 300, 800, 300, 800), 0)

                )

            } else {

                @Suppress("DEPRECATION")

                val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {

                    vibrator?.vibrate(

                        VibrationEffect.createWaveform(longArrayOf(0, 800, 300, 800, 300, 800), 0)

                    )

                } else {

                    @Suppress("DEPRECATION")

                    vibrator?.vibrate(longArrayOf(0, 800, 300, 800, 300, 800), 0)

                }

            }

        } catch (_: Exception) {}

    }



    private fun stopVibrate() {

        try {

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {

                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager

                vibratorManager?.defaultVibrator?.cancel()

            } else {

                @Suppress("DEPRECATION")

                val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator

                vibrator?.cancel()

            }

        } catch (_: Exception) {}

    }



    private fun stopLoudAlarmInternal() {

        stopSoundPreview()

        try {

            alarmPlayer?.apply {

                if (isPlaying) {

                    stop()

                }

                reset()

                release()

            }

        } catch (_: Exception) {}

        alarmPlayer = null



        alarmRingtone?.stop()

        alarmRingtone = null

        stopVibrate()

    }



    private fun showChatNotification(title: String, message: String, soundId: String?) {

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {

            val channel = NotificationChannel(

                CHAT_NOTIFICATION_CHANNEL_ID,

                "Obrolan Lingkaran",

                NotificationManager.IMPORTANCE_HIGH

            ).apply {

                description = "Notifikasi pesan obrolan lingkaran keluarga"

                enableVibration(true)

                vibrationPattern = longArrayOf(0, 150, 100, 150)

                setShowBadge(true)

            }

            manager.createNotificationChannel(channel)

        }



        val chatIntent = Intent(this, MainActivity::class.java).apply {

            action = "ACTION_OPEN_CHAT"

            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP

        }

        val pendingIntent = PendingIntent.getActivity(

            this,

            CHAT_NOTIFICATION_ID,

            chatIntent,

            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

        )



        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {

            Notification.Builder(this, CHAT_NOTIFICATION_CHANNEL_ID)

        } else {

            @Suppress("DEPRECATION")

            Notification.Builder(this)

        }



        val notif = builder

            .setContentTitle(title)

            .setContentText(message)

            .setSmallIcon(android.R.drawable.stat_notify_chat)

            .setContentIntent(pendingIntent)

            .setAutoCancel(true)

            .setPriority(Notification.PRIORITY_HIGH)

            .setDefaults(Notification.DEFAULT_ALL)

            .setVisibility(Notification.VISIBILITY_PUBLIC)

            .build()



        val notifId = (System.currentTimeMillis() % 100000).toInt() + 1000

        manager.notify(notifId, notif)



        // Play the chosen notification sound tone

        playSoundTone(soundId ?: "bubble_pop")

    }



    private fun playSoundTone(soundId: String) {

        try {

            stopSoundPreview()

            when (soundId) {

                "siren_pulse" -> {

                    previewTone = ToneGenerator(AudioManager.STREAM_ALARM, 100)

                    previewTone?.startTone(ToneGenerator.TONE_CDMA_EMERGENCY_RINGBACK, 3000)

                }

                "siren_fire" -> {

                    previewTone = ToneGenerator(AudioManager.STREAM_ALARM, 100)

                    previewTone?.startTone(ToneGenerator.TONE_CDMA_NETWORK_USA_RINGBACK, 3000)

                }

                "radar_beep" -> {

                    previewTone = ToneGenerator(AudioManager.STREAM_ALARM, 95)

                    previewTone?.startTone(ToneGenerator.TONE_PROP_BEEP, 1200)

                }

                "digital_bell" -> {

                    previewTone = ToneGenerator(AudioManager.STREAM_RING, 90)

                    previewTone?.startTone(ToneGenerator.TONE_CDMA_ABBR_ALERT, 1000)

                }

                "bubble_pop" -> {

                    previewTone = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 85)

                    previewTone?.startTone(ToneGenerator.TONE_PROP_ACK, 400)

                }

                "crystal_ping" -> {

                    previewTone = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 85)

                    previewTone?.startTone(ToneGenerator.TONE_PROP_PROMPT, 400)

                }

                "double_tone" -> {

                    previewTone = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 85)

                    previewTone?.startTone(ToneGenerator.TONE_CDMA_ALERT_AUTOREDIAL_LITE, 500)

                }

                "system_alarm" -> {

                    val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)

                    previewRingtone = RingtoneManager.getRingtone(applicationContext, uri)?.apply { play() }

                }

                "system_ringtone" -> {

                    val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)

                    previewRingtone = RingtoneManager.getRingtone(applicationContext, uri)?.apply { play() }

                }

                "system_notif" -> {

                    val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)

                    previewRingtone = RingtoneManager.getRingtone(applicationContext, uri)?.apply { play() }

                }

                else -> {

                    previewTone = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 85)

                    previewTone?.startTone(ToneGenerator.TONE_PROP_ACK, 400)

                }

            }

        } catch (e: Exception) {

            e.printStackTrace()

        }

    }



    private fun stopSoundPreview() {

        try {

            previewTone?.stopTone()

            previewTone?.release()

            previewTone = null

            previewRingtone?.stop()

            previewRingtone = null

        } catch (_: Exception) {}

    }



    override fun onDestroy() {

        enableStatusBarBlocker(false)

        cancelEmergencyNotification()

        stopLoudAlarmInternal()

        if (activeSosChannel == activeSosChannel) {

            activeSosChannel = null

        }

        activeLoudChannel = null

        activeLostModeChannel = null

        super.onDestroy()

    }

}

