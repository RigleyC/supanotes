package com.example.supanotes

import android.content.Context
import com.example.supanotes.share.ShareBridgeStore
import com.example.supanotes.share.ShareUploadWorker
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

private fun methodArgumentJson(arguments: Any?): String? {
    return when (arguments) {
        null -> null
        is Map<*, *> -> JSONObject(arguments).toString()
        is String -> arguments
        else -> throw IllegalArgumentException("Unsupported share bridge payload")
    }
}

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.supanotes/share")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "publishNotesIndex" -> {
                        ShareBridgeStore.writeNotesIndex(
                            this,
                            methodArgumentJson(call.arguments),
                        )
                        result.success(null)
                    }
                    "publishSessionCredentials" -> {
                        ShareBridgeStore.saveSession(this, methodArgumentJson(call.arguments))
                        result.success(null)
                    }
                    "clearShareSession" -> {
                        ShareBridgeStore.clearSessionData(this)
                        result.success(null)
                    }
                    "readPendingShare" -> {
                        val pending = ShareBridgeStore.readPendingShare(this)
                        result.success(
                            if (pending == null) {
                                null
                            } else {
                                mapOf(
                                    "text" to pending.text,
                                    "shareId" to pending.shareId,
                                    "noteId" to pending.noteId,
                                    "ownerUserId" to pending.ownerUserId,
                                )
                            },
                        )
                    }
                    "clearPendingShare" -> {
                        ShareBridgeStore.clearPendingShare(this)
                        result.success(null)
                    }
                    "retryPendingShares" -> {
                        ShareUploadWorker.enqueue(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
