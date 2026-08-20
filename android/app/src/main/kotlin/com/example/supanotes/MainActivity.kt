package com.example.supanotes

import android.content.Context
import android.util.Base64
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.util.UUID
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

private fun methodArgumentJson(arguments: Any?): String? {
    return when (arguments) {
        null -> null
        is Map<*, *> -> JSONObject(arguments).toString()
        is String -> arguments
        else -> throw IllegalArgumentException("Unsupported share bridge payload")
    }
}

private object ShareCredentialStore {
    private const val alias = "supanotes.share.session"
    private const val store = "share_bridge"
    private const val key = "session_encrypted"

    private fun secretKey(): SecretKey {
        val keys = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (!keys.containsAlias(alias)) {
            KeyGenerator.getInstance("AES", "AndroidKeyStore").apply {
                init(android.security.keystore.KeyGenParameterSpec.Builder(
                    alias,
                    android.security.keystore.KeyProperties.PURPOSE_ENCRYPT or android.security.keystore.KeyProperties.PURPOSE_DECRYPT,
                ).setBlockModes(android.security.keystore.KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(android.security.keystore.KeyProperties.ENCRYPTION_PADDING_NONE)
                    .build())
            }.generateKey()
        }
        return keys.getKey(alias, null) as SecretKey
    }

    fun save(context: Context, value: String?) {
        if (value == null) return
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, secretKey()) }
        val payload = cipher.iv + cipher.doFinal(value.toByteArray())
        context.getSharedPreferences(store, Context.MODE_PRIVATE).edit()
            .putString(key, Base64.encodeToString(payload, Base64.NO_WRAP)).apply()
    }

    fun clear(context: Context) {
        context.getSharedPreferences(store, Context.MODE_PRIVATE).edit().remove(key).apply()
    }
}

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.supanotes/share")
            .setMethodCallHandler { call, result ->
                val prefs = getSharedPreferences("share_bridge", Context.MODE_PRIVATE)
                when (call.method) {
                    "publishNotesIndex" -> {
                        prefs.edit().putString("notes_index", methodArgumentJson(call.arguments)).apply()
                        result.success(null)
                    }
                    "publishSessionCredentials" -> {
                        ShareCredentialStore.save(this, methodArgumentJson(call.arguments))
                        result.success(null)
                    }
                    "clearShareSession" -> {
                        prefs.edit().remove("notes_index").remove("pending_shared_text").apply()
                        ShareCredentialStore.clear(this)
                        result.success(null)
                    }
                    "readPendingShare" -> {
                        val shareId = prefs.getString("pending_shared_id", null)
                            ?: UUID.randomUUID().toString().also {
                                prefs.edit().putString("pending_shared_id", it).apply()
                            }
                        result.success(mapOf(
                            "text" to prefs.getString("pending_shared_text", null),
                            "shareId" to shareId,
                        ))
                    }
                    "clearPendingShare" -> {
                        prefs.edit().remove("pending_shared_text").remove("pending_shared_id").apply()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
