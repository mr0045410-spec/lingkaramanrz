package com.lingkaraman.lingkar_aman

import android.content.Context
import android.content.Intent
import java.util.UUID

/**
 * Pengaman token internal untuk mencegah Intent Spoofing (SEC-09 / B1).
 * Menggunakan token rahasia yang disimpan dalam penyimpanan privat internal (MODE_PRIVATE)
 * yang hanya dapat diakses oleh UID aplikasi LingkarAman di sandbox Android OS.
 * Mencegah aplikasi pihak ketiga atau shell eksternal memicu SOS / Lost Mode palsu.
 */
object InternalIntentGuard {
    private const val PREF_NAME = "lingkaraman_internal_security"
    private const val KEY_INTERNAL_TOKEN = "internal_secret_token"
    private const val EXTRA_INTERNAL_AUTH_TOKEN = "com.lingkaraman.INTERNAL_AUTH_TOKEN"

    @Volatile
    private var cachedToken: String? = null

    fun getInternalToken(context: Context): String {
        cachedToken?.let { return it }
        synchronized(this) {
            cachedToken?.let { return it }
            val prefs = context.applicationContext.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            var token = prefs.getString(KEY_INTERNAL_TOKEN, null)
            if (token.isNullOrEmpty()) {
                token = UUID.randomUUID().toString()
                prefs.edit().putString(KEY_INTERNAL_TOKEN, token).apply()
            }
            cachedToken = token
            return token
        }
    }

    /**
     * Menandatangani Intent internal dengan token sesi aman.
     */
    fun signIntent(context: Context, intent: Intent): Intent {
        return intent.apply {
            putExtra(EXTRA_INTERNAL_AUTH_TOKEN, getInternalToken(context))
        }
    }

    /**
     * Memverifikasi apakah Intent berasal dari komponen internal aplikasi yang sah.
     */
    fun isIntentAuthentic(context: Context, intent: Intent?): Boolean {
        if (intent == null) return false
        val token = intent.getStringExtra(EXTRA_INTERNAL_AUTH_TOKEN) ?: return false
        return token == getInternalToken(context)
    }
}
