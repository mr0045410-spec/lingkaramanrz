package com.lingkaraman.lingkar_aman

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

object SosDirectSender {
    private const val TAG = "SosDirectSender"
    private const val PREFS_NAME = "FlutterSharedPreferences"

    fun triggerSos(context: Context, sourceDescription: String) {
        // 1. Cek apakah Flutter aktif dan channel terdaftar
        if (MainActivity.activeSosChannel != null) {
            Log.d(TAG, "FlutterEngine active, forwarding via MethodChannel")
            MainActivity.notifySosTriggered()
            return
        }

        // 2. Flutter tidak aktif / killed -> Eksekusi mandiri langsung ke Supabase REST
        Log.d(TAG, "FlutterEngine null/inactive, executing direct standalone SOS HTTP POST")
        thread {
            sendDirectSosAlert(context, sourceDescription)
        }
    }

    private fun sendDirectSosAlert(context: Context, sourceDescription: String) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val supabaseUrl = getPrefString(prefs, "supabase_url") ?: "https://uwxecnbeqeysnlzwdcha.supabase.co"
        val anonKey = getPrefString(prefs, "supabase_anon_key") ?: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InV3eGVjbmJlcWV5c25sendkY2hhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTIwMDc3NTIsImV4cCI6MjEwNzU4Mzc1Mn0.QmoEmp4OBRHyhsHWYNCftnbdF19Z0Oi-hF2n8HJoJ8U"
        val rawAccessToken = getPrefString(prefs, "access_token")
        val accessToken = decodeSecureToken(rawAccessToken)
        val userId = getPrefString(prefs, "user_id")
        val circleId = getPrefString(prefs, "active_circle_id")
        val lat = getPrefDouble(prefs, "last_lat")
        val lng = getPrefDouble(prefs, "last_lng")

        if (userId.isNullOrEmpty()) {
            Log.e(TAG, "User ID not found in SharedPreferences, cannot send direct SOS")
            showSosNotification(context, "Gagal Mengirim SOS", "Akun belum login pada perangkat ini.")
            return
        }

        try {
            val url = URL("$supabaseUrl/rest/v1/sos_alerts")
            val conn = url.openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.setRequestProperty("apikey", anonKey)
            val authBearer = if (!accessToken.isNullOrEmpty()) accessToken else anonKey
            conn.setRequestProperty("Authorization", "Bearer $authBearer")
            conn.setRequestProperty("Content-Type", "application/json")
            conn.setRequestProperty("Prefer", "return=minimal")
            conn.doOutput = true
            conn.connectTimeout = 10000
            conn.readTimeout = 10000

            val jsonBody = JSONObject().apply {
                put("user_id", userId)
                if (!circleId.isNullOrEmpty()) {
                    put("circle_id", circleId)
                }
                put("latitude", lat)
                put("longitude", lng)
                put("message", "DARURAT! (Dipicu via $sourceDescription)")
                put("status", "active")
            }

            OutputStreamWriter(conn.outputStream).use { writer ->
                writer.write(jsonBody.toString())
                writer.flush()
            }

            val responseCode = conn.responseCode
            Log.d(TAG, "SOS REST Response Code: $responseCode")
            if (responseCode in 200..299) {
                showSosNotification(context, "Sinyal SOS Terkirim!", "Sinyal darurat berhasil dipancarkan ke keluarga.")
            } else {
                val errorStream = conn.errorStream?.bufferedReader()?.use { it.readText() }
                Log.e(TAG, "Failed to send SOS: $responseCode - $errorStream")
                showSosNotification(context, "Peringatan SOS", "Sinyal SOS dikirim (Kode respon: $responseCode)")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Exception during direct SOS dispatch", e)
            showSosNotification(context, "Peringatan SOS", "Gagal memancarkan SOS: ${e.localizedMessage}")
        }
    }

    private fun decodeSecureToken(raw: String?): String? {
        if (raw == null) return null
        if (raw.startsWith("sec_v1:")) {
            try {
                val payload = raw.removePrefix("sec_v1:")
                val decoded = android.util.Base64.decode(payload, android.util.Base64.URL_SAFE)
                return String(decoded.reversedArray(), Charsets.UTF_8)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to decode obfuscated token: ${e.message}")
            }
        }
        return raw
    }

    private fun getPrefString(prefs: SharedPreferences, key: String): String? {
        return prefs.getString("flutter.$key", null) ?: prefs.getString(key, null)
    }

    private fun getPrefDouble(prefs: SharedPreferences, key: String): Double {
        val str = getPrefString(prefs, "${key}_str")
        if (!str.isNullOrEmpty()) {
            return str.toDoubleOrNull() ?: 0.0
        }
        return try {
            prefs.getFloat("flutter.$key", 0f).toDouble()
        } catch (_: Exception) {
            0.0
        }
    }

    private fun showSosNotification(context: Context, title: String, content: String) {
        val channelId = "sos_alert_feedback_channel"
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Notifikasi Darurat SOS",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Umpan balik pengiriman sinyal darurat SOS"
                enableVibration(true)
            }
            manager.createNotificationChannel(channel)
        }

        val notification = NotificationCompat.Builder(context, channelId)
            .setContentTitle(title)
            .setContentText(content)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .build()

        manager.notify(7788, notification)
    }
}
