package com.example.supanotes

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.supanotes/share")
            .setMethodCallHandler { call, result ->
                val prefs = getSharedPreferences("share_bridge", Context.MODE_PRIVATE)
                when (call.method) {
                    "publishNotesIndex" -> {
                        prefs.edit().putString("notes_index", call.arguments as? String).apply()
                        result.success(null)
                    }
                    "publishSessionCredentials" -> {
                        prefs.edit().putString("session", call.arguments as? String).apply()
                        result.success(null)
                    }
                    "clearShareSession" -> {
                        prefs.edit().clear().apply()
                        result.success(null)
                    }
                    "retryPendingShares" -> result.success(null)
                    else -> result.notImplemented()
                }
            }
    }
}
