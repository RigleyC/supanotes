package com.example.supanotes.share

import android.content.Context
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import org.json.JSONException
import org.json.JSONObject

/**
 * Single owner of the `share_bridge` storage contract shared between the
 * Flutter engine (MainActivity) and the fully-native share flow
 * ([ShareActivity] / [ShareUploadWorker]).
 *
 * Two delivery paths live here:
 * - pending share: text queued for the Flutter picker when no native session
 *   exists yet (login-later case);
 * - inbox: durable per-share record written BEFORE user confirmation, drained
 *   by [ShareUploadWorker].
 *
 * Session credentials are AES-GCM encrypted with an AndroidKeyStore key and
 * never appear in plaintext prefs.
 */
object ShareBridgeStore {
    private const val PREFS = "share_bridge"
    private const val KEY_NOTES_INDEX = "notes_index"
    private const val KEY_SESSION = "session_encrypted"
    private const val KEY_PENDING_TEXT = "pending_shared_text"
    private const val KEY_PENDING_SHARE_ID = "pending_shared_id"
    private const val KEY_PENDING_NOTE_ID = "pending_shared_note_id"
    private const val KEY_PENDING_OWNER_USER_ID = "pending_shared_owner_user_id"
    private const val KEY_INBOX = "pending_inbox"

    private const val KEYSTORE_ALIAS = "supanotes.share.session"
    private const val GCM_IV_BYTES = 12
    private const val GCM_TAG_BITS = 128

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    // --- notes index ---

    fun writeNotesIndex(context: Context, json: String?) {
        prefs(context).edit().putString(KEY_NOTES_INDEX, json).apply()
    }

    fun readNotesIndex(context: Context): String? =
        prefs(context).getString(KEY_NOTES_INDEX, null)

    // --- pending share (Flutter fallback path) ---

    fun writePendingText(
        context: Context,
        text: String,
        noteId: String? = null,
        ownerUserId: String? = null,
    ) {
        prefs(context).edit()
            .putString(KEY_PENDING_TEXT, text)
            .putString(KEY_PENDING_NOTE_ID, noteId)
            .putString(KEY_PENDING_OWNER_USER_ID, ownerUserId)
            .apply()
    }

    data class PendingShareRecord(
        val text: String,
        val shareId: String,
        val noteId: String?,
        val ownerUserId: String?,
    )

    /** Returns PendingShareRecord; lazily mints a stable share id on first read. */
    fun readPendingShare(context: Context): PendingShareRecord? {
        val text = prefs(context).getString(KEY_PENDING_TEXT, null) ?: return null
        val shareId = prefs(context).getString(KEY_PENDING_SHARE_ID, null)
            ?: java.util.UUID.randomUUID().toString().also {
                prefs(context).edit().putString(KEY_PENDING_SHARE_ID, it).apply()
            }
        val noteId = prefs(context).getString(KEY_PENDING_NOTE_ID, null)
        val ownerUserId = prefs(context).getString(KEY_PENDING_OWNER_USER_ID, null)
        return PendingShareRecord(text, shareId, noteId, ownerUserId)
    }

    fun clearPendingShare(context: Context) {
        prefs(context).edit()
            .remove(KEY_PENDING_TEXT)
            .remove(KEY_PENDING_SHARE_ID)
            .remove(KEY_PENDING_NOTE_ID)
            .remove(KEY_PENDING_OWNER_USER_ID)
            .apply()
    }

    // --- inbox (native durable delivery path) ---

    fun writeInboxItem(
        context: Context,
        shareId: String,
        url: String,
        createdAtIso: String,
        noteId: String,
        ownerUserId: String,
    ) {
        val item = JSONObject().apply {
            put("shareId", shareId)
            put("url", url)
            put("createdAt", createdAtIso)
            put("noteId", noteId)
            put("ownerUserId", ownerUserId)
        }
        prefs(context).edit().putString(KEY_INBOX, item.toString()).apply()
    }

    fun readInboxItem(context: Context): JSONObject? {
        val raw = prefs(context).getString(KEY_INBOX, null) ?: return null
        return try {
            val item = JSONObject(raw)
            val required = listOf("shareId", "url", "noteId", "ownerUserId")
            if (required.any { item.optString(it).isBlank() }) null else item
        } catch (_: JSONException) {
            null
        }
    }

    fun clearInbox(context: Context) {
        prefs(context).edit().remove(KEY_INBOX).apply()
    }

    // --- session credentials ---

    fun saveSession(context: Context, json: String?) {
        if (json == null) {
            clearSessionCredentials(context)
            return
        }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            .apply { init(Cipher.ENCRYPT_MODE, secretKey()) }
        val payload = cipher.iv + cipher.doFinal(json.toByteArray())
        prefs(context).edit()
            .putString(KEY_SESSION, Base64.encodeToString(payload, Base64.NO_WRAP))
            .apply()
    }

    fun loadSession(context: Context): JSONObject? {
        val encoded = prefs(context).getString(KEY_SESSION, null) ?: return null
        return try {
            val payload = Base64.decode(encoded, Base64.NO_WRAP)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(
                Cipher.DECRYPT_MODE,
                secretKey(),
                GCMParameterSpec(GCM_TAG_BITS, payload, 0, GCM_IV_BYTES),
            )
            JSONObject(String(cipher.doFinal(payload, GCM_IV_BYTES, payload.size - GCM_IV_BYTES)))
        } catch (_: Exception) {
            null
        }
    }

    /** Clears everything tied to the current account: index, inbox, pending, credentials. */
    fun clearSessionData(context: Context) {
        prefs(context).edit()
            .remove(KEY_NOTES_INDEX)
            .remove(KEY_INBOX)
            .remove(KEY_PENDING_TEXT)
            .remove(KEY_PENDING_SHARE_ID)
            .apply()
        clearSessionCredentials(context)
    }

    private fun clearSessionCredentials(context: Context) {
        prefs(context).edit().remove(KEY_SESSION).apply()
    }

    private fun secretKey(): SecretKey {
        val keys = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (!keys.containsAlias(KEYSTORE_ALIAS)) {
            KeyGenerator.getInstance("AES", "AndroidKeyStore").apply {
                init(
                    android.security.keystore.KeyGenParameterSpec.Builder(
                        KEYSTORE_ALIAS,
                        android.security.keystore.KeyProperties.PURPOSE_ENCRYPT or
                            android.security.keystore.KeyProperties.PURPOSE_DECRYPT,
                    )
                        .setBlockModes(android.security.keystore.KeyProperties.BLOCK_MODE_GCM)
                        .setEncryptionPaddings(android.security.keystore.KeyProperties.ENCRYPTION_PADDING_NONE)
                        .build(),
                )
            }.generateKey()
        }
        return keys.getKey(KEYSTORE_ALIAS, null) as SecretKey
    }
}
