package com.example.supanotes.share

import android.app.Activity
import android.os.Bundle
import android.widget.TextView

/** Receives shared text before the Flutter activity starts. */
class ShareActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val sharedText = intent.getStringExtra("android.intent.extra.TEXT").orEmpty()
        val message = if (sharedText.isBlank()) "Nenhum link recebido" else "Link recebido. Abra o SupaNotes para escolher a nota."
        setContentView(TextView(this).apply { text = message; textSize = 18f; setPadding(32, 64, 32, 32) })
    }
}
