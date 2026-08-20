package com.example.supanotes.share

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.widget.TextView

/** Receives shared text before the Flutter activity starts. */
class ShareActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val sharedText = intent.getStringExtra("android.intent.extra.TEXT").orEmpty()
        getSharedPreferences("share_bridge", MODE_PRIVATE).edit()
            .putString("pending_shared_text", sharedText)
            .apply()
        val message = if (sharedText.isBlank()) "Nenhum link recebido" else "Link recebido. Abra o SupaNotes para escolher a nota."
        setContentView(TextView(this).apply {
            text = message
            textSize = 18f
            setPadding(32, 64, 32, 32)
            setOnClickListener {
                startActivity(Intent(this@ShareActivity, com.example.supanotes.MainActivity::class.java))
                finish()
            }
        })
    }
}
