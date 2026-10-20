package com.lingkaraman.lingkar_aman

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings

object OemWhitelistHelper {

    fun getManufacturer(): String {
        return Build.MANUFACTURER.orEmpty().trim().lowercase()
    }

    fun getBrandDisplayName(): String {
        val m = getManufacturer()
        return when {
            m.contains("xiaomi") || m.contains("redmi") || m.contains("poco") -> "Xiaomi (HyperOS / MIUI)"
            m.contains("samsung") -> "Samsung (OneUI)"
            m.contains("oppo") -> "Oppo (ColorOS)"
            m.contains("realme") -> "Realme (Realme UI)"
            m.contains("vivo") || m.contains("iqoo") -> "Vivo (FuntouchOS / OriginOS)"
            m.contains("huawei") || m.contains("honor") -> "Huawei / Honor"
            m.contains("transsion") || m.contains("infinix") || m.contains("tecno") || m.contains("itel") -> "Infinix / Tecno"
            m.contains("asus") -> "Asus"
            m.contains("oneplus") -> "OnePlus (OxygenOS)"
            else -> Build.MANUFACTURER.replaceFirstChar { it.uppercase() }
        }
    }

    fun openAutostartSettings(context: Context): Boolean {
        val m = getManufacturer()
        val intents = mutableListOf<Intent>()

        when {
            // Xiaomi / Redmi / POCO
            m.contains("xiaomi") || m.contains("redmi") || m.contains("poco") -> {
                intents.add(Intent().setComponent(ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity")))
                intents.add(Intent().setComponent(ComponentName("com.miui.securitycenter", "com.miui.powercenter.PowerSettings")))
            }

            // Samsung OneUI
            m.contains("samsung") -> {
                intents.add(Intent().setComponent(ComponentName("com.samsung.android.lool", "com.samsung.android.sm.ui.battery.BatteryActivity")))
                intents.add(Intent().setComponent(ComponentName("com.samsung.android.sm", "com.samsung.android.sm.ui.battery.BatteryActivity")))
                intents.add(Intent().setComponent(ComponentName("com.samsung.android.lool", "com.samsung.android.sm.battery.ui.BatteryActivity")))
            }

            // Oppo / Realme ColorOS
            m.contains("oppo") || m.contains("realme") -> {
                intents.add(Intent().setComponent(ComponentName("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity")))
                intents.add(Intent().setComponent(ComponentName("com.coloros.safecenter", "com.coloros.safecenter.startupapp.StartupAppListActivity")))
                intents.add(Intent().setComponent(ComponentName("com.oppo.safe", "com.oppo.safe.permission.startup.StartupAppListActivity")))
                intents.add(Intent().setComponent(ComponentName("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.FakeActivity")))
            }

            // Vivo / iQOO FuntouchOS
            m.contains("vivo") || m.contains("iqoo") -> {
                intents.add(Intent().setComponent(ComponentName("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.PurviewTabActivity")))
                intents.add(Intent().setComponent(ComponentName("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity")))
                intents.add(Intent().setComponent(ComponentName("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager")))
                intents.add(Intent().setComponent(ComponentName("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity")))
            }

            // Huawei / Honor
            m.contains("huawei") || m.contains("honor") -> {
                intents.add(Intent().setComponent(ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity")))
                intents.add(Intent().setComponent(ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.optimize.process.ProtectActivity")))
                intents.add(Intent().setComponent(ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.appcontrol.activity.StartupAppControlActivity")))
            }

            // Transsion / Infinix / Tecno
            m.contains("transsion") || m.contains("infinix") || m.contains("tecno") || m.contains("itel") -> {
                intents.add(Intent().setComponent(ComponentName("com.transsion.phonemanager", "com.transsion.phonemanager.settings.AutoRunListActivity")))
                intents.add(Intent().setComponent(ComponentName("com.transsion.phonemanager", "com.transsion.phonemanager.manage.AutoRunManageActivity")))
            }

            // Asus
            m.contains("asus") -> {
                intents.add(Intent().setComponent(ComponentName("com.asus.mobilemanager", "com.asus.mobilemanager.entry.FunctionActivity")))
                intents.add(Intent().setComponent(ComponentName("com.asus.mobilemanager", "com.asus.mobilemanager.autostart.AutoStartActivity")))
            }

            // OnePlus
            m.contains("oneplus") -> {
                intents.add(Intent().setComponent(ComponentName("com.oneplus.security", "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity")))
            }
        }

        // Coba intent OEM satu per satu
        for (intent in intents) {
            try {
                intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                context.startActivity(intent)
                return true
            } catch (_: Exception) {
                // Lanjut ke intent berikutnya jika versi OS berbeda
            }
        }

        // Fallback: Buka pengaturan info aplikasi atau optimasi baterai umum
        return try {
            val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(intent)
            true
        } catch (_: Exception) {
            try {
                val appDetailIntent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:${context.packageName}")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                context.startActivity(appDetailIntent)
                true
            } catch (_: Exception) {
                false
            }
        }
    }
}
