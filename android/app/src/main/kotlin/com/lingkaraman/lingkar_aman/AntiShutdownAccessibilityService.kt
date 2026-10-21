package com.lingkaraman.lingkar_aman

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

class AntiShutdownAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "AntiShutdownService"
        var isRunning: Boolean = false
            private set
        var instance: AntiShutdownAccessibilityService? = null
            private set

        fun dismissNotificationShade(): Boolean {
            return instance?.let { s ->
                s.dismissNotificationShadeInternal()
                true
            } ?: false
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        isRunning = true
        Log.i(TAG, "Anti-Shutdown & Anti-Status-Bar Accessibility Service Terhubung & Aktif.")
    }

    override fun onDestroy() {
        if (instance == this) {
            instance = null
        }
        isRunning = false
        Log.i(TAG, "Anti-Shutdown Accessibility Service Dihentikan.")
        super.onDestroy()
    }

    override fun onInterrupt() {
        Log.w(TAG, "Anti-Shutdown Accessibility Service Terinterupsi.")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        // Hanya bertindak jika Mode HP Hilang atau Fake Shutdown sedang aktif
        if (!isProtectionActive()) return

        val eventType = event.eventType
        if (eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED ||
            eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) {

            val className = event.className?.toString().orEmpty().lowercase()
            val packageName = event.packageName?.toString().orEmpty().lowercase()

            // 1. Deteksi GlobalActions / Power Dialog / Shutdown Menu
            val isGlobalActions = className.contains("globalactions") ||
                    className.contains("powerdialog") ||
                    className.contains("shutdown") ||
                    packageName.contains("globalactions")

            // 2. Deteksi Usaha Membuka Pengaturan HP atau Copot Pemasangan (Uninstall)
            val isSettingsOrInstaller = (packageName.contains("settings") && !packageName.contains("com.lingkaraman")) ||
                    packageName.contains("packageinstaller") ||
                    packageName.contains("permissioncontroller")

            // 3. Deteksi Penarikan Tirai Status Bar / Notification Shade / Quick Settings
            val isSystemUiPanel = packageName == "com.android.systemui" && (
                    className.contains("shade") ||
                    className.contains("panel") ||
                    className.contains("quick") ||
                    className.contains("qs") ||
                    className.contains("expanded") ||
                    className.contains("controlcenter") ||
                    className.contains("notification") ||
                    className.contains("statusbarservice")
            )

            var hasPowerOffText = false
            var hasQuickSettingsText = false
            try {
                val rootNode = rootInActiveWindow
                if (rootNode != null) {
                    hasPowerOffText = scanNodeForShutdownKeywords(rootNode)
                    if (!hasPowerOffText && packageName == "com.android.systemui") {
                        hasQuickSettingsText = scanNodeForQuickSettingsKeywords(rootNode)
                    }
                    rootNode.recycle()
                }
            } catch (_: Exception) {}

            if (isGlobalActions || hasPowerOffText) {
                Log.w(TAG, "⚠️ Pencuri mencoba mematikan HP (Power Menu terdeteksi)! Memblokir...")
                performGlobalAction(GLOBAL_ACTION_BACK)
                dismissNotificationShadeInternal()
                bringLockScreenToFront()
            } else if (isSettingsOrInstaller) {
                Log.w(TAG, "⚠️ Pencuri mencoba membuka Pengaturan / Settings ($packageName)! Memblokir...")
                performGlobalAction(GLOBAL_ACTION_BACK)
                performGlobalAction(GLOBAL_ACTION_HOME)
                dismissNotificationShadeInternal()
                bringLockScreenToFront()
            } else if (isSystemUiPanel || hasQuickSettingsText) {
                Log.w(TAG, "⚠️ Pencuri mencoba menarik status bar / quick settings! Menutup paksa...")
                dismissNotificationShadeInternal()
                performGlobalAction(GLOBAL_ACTION_BACK)
                bringLockScreenToFront()
            }
        }
    }

    fun dismissNotificationShadeInternal() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                performGlobalAction(GLOBAL_ACTION_DISMISS_NOTIFICATION_SHADE)
            } else {
                performGlobalAction(GLOBAL_ACTION_BACK)
            }
        } catch (_: Exception) {}

        try {
            @Suppress("DEPRECATION")
            val closeDialogIntent = Intent(Intent.ACTION_CLOSE_SYSTEM_DIALOGS)
            sendBroadcast(closeDialogIntent)
        } catch (_: Exception) {}
    }

    private fun scanNodeForShutdownKeywords(node: AccessibilityNodeInfo): Boolean {
        val text = node.text?.toString().orEmpty().lowercase()
        val desc = node.contentDescription?.toString().orEmpty().lowercase()

        val keywords = listOf(
            "daya mati", "matikan daya", "power off", "turn off",
            "mulai ulang", "restart", "reboot", "muat ulang"
        )

        for (k in keywords) {
            if (text.contains(k) || desc.contains(k)) {
                return true
            }
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val found = scanNodeForShutdownKeywords(child)
            child.recycle()
            if (found) return true
        }

        return false
    }

    private fun scanNodeForQuickSettingsKeywords(node: AccessibilityNodeInfo): Boolean {
        val text = node.text?.toString().orEmpty().lowercase()
        val desc = node.contentDescription?.toString().orEmpty().lowercase()

        val keywords = listOf(
            "airplane mode", "mode pesawat", "wi-fi", "wifi", "bluetooth",
            "mobile data", "data seluler", "settings", "pengaturan",
            "senter", "flashlight", "hotspot", "no notifications",
            "tidak ada notifikasi", "clear all", "hapus semua"
        )

        for (k in keywords) {
            if (text.contains(k) || desc.contains(k)) {
                return true
            }
        }

        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val found = scanNodeForQuickSettingsKeywords(child)
            child.recycle()
            if (found) return true
        }

        return false
    }

    private fun isProtectionActive(): Boolean {
        // Cek Direct Boot SharedPreferences jika Android N+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                val directContext = createDeviceProtectedStorageContext()
                val directPrefs = directContext.getSharedPreferences("lingkaraman_direct_boot_prefs", Context.MODE_PRIVATE)
                if (directPrefs.getBoolean("lost_mode_active", false) ||
                    directPrefs.getBoolean("fake_shutdown_active", false)) {
                    return true
                }
            } catch (_: Exception) {}
        }

        // Cek FlutterSharedPreferences biasa
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val lostMode = prefs.getBoolean("flutter.lost_mode_active", false)
            val fakeShutdown = prefs.getBoolean("flutter.lost_mode_fake_shutdown", false)
            return lostMode || fakeShutdown
        } catch (_: Exception) {
            return false
        }
    }

    private fun bringLockScreenToFront() {
        try {
            val intent = Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP)
                putExtra("lost_mode_locked", true)
            }
            InternalIntentGuard.signIntent(this, intent)
            startActivity(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Gagal mengembalikan lock screen ke depan: ${e.message}")
        }
    }
}
