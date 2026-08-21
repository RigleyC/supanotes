package com.example.supanotes.share

import android.app.Activity
import android.content.Intent
import android.graphics.Typeface
import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.view.View
import android.view.ViewGroup
import android.widget.BaseAdapter
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ListView
import android.widget.TextView
import android.widget.Toast
import java.time.Instant
import java.util.UUID

/**
 * Native share target with the same picker semantics as the iOS Share
 * Extension: search field on top, updatedAt DESC list showing title +
 * preview, editable notes only.
 *
 * Selection persists to the durable inbox BEFORE any confirmation is shown,
 * then hands delivery to [ShareUploadWorker]. Without a native session the
 * text is queued for the Flutter picker instead of being discarded.
 */
class ShareActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT).orEmpty()
        val url = ShareLinkText.extractUrl(sharedText)
        if (url == null) {
            toast("O texto compartilhado não contém uma URL.")
            finish()
            return
        }

        val session = ShareBridgeStore.loadSession(this)
        val notes = ShareNoteIndexJson.parseForAccount(
            ShareBridgeStore.readNotesIndex(this),
            session?.optString("ownerUserId"),
        )
        if (session == null || notes == null) {
            // No usable session/index yet: queue for the in-app picker so the
            // link survives until login, per spec — never silently discard.
            ShareBridgeStore.writePendingText(this, sharedText)
            toast("Abra o SupaNotes para escolher a nota.")
            finish()
            return
        }

        setContentView(buildPickerUi(url, notes))
    }

    private fun buildPickerUi(url: String, notes: List<ShareableNote>): View {
        val density = resources.displayMetrics.density
        val padding = (16 * density).toInt()
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(padding, padding, padding, padding)
        }
        val search = EditText(this).apply {
            hint = "Buscar nota"
            setSingleLine()
        }
        val adapter = NotesAdapter(notes, url)
        search.addTextChangedListener(
            object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) = Unit
                override fun onTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) = Unit
                override fun afterTextChanged(s: Editable?) = adapter.updateQuery(s.toString())
            },
        )
        root.addView(search)
        val listView = ListView(this)
        listView.adapter = adapter
        root.addView(
            listView,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f,
            ),
        )
        return root
    }

    private fun toast(message: String) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
    }

    /** Two-line rows (title + preview), built in code — no Compose needed. */
    private inner class NotesAdapter(
        private val notes: List<ShareableNote>,
        private val url: String,
    ) : BaseAdapter() {
        private var visible: List<ShareableNote> = notes

        fun updateQuery(rawQuery: String) {
            visible = notes.filter { ShareNoteIndexJson.matchesQuery(it, rawQuery) }
            notifyDataSetChanged()
        }

        override fun getCount(): Int = visible.size
        override fun getItem(position: Int): ShareableNote = visible[position]
        override fun getItemId(position: Int): Long = position.toLong()

        override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
            val note = getItem(position)
            val row = (convertView as? LinearLayout) ?: buildRow(parent)
            (row.getChildAt(0) as TextView).text = note.title.ifEmpty { "Sem título" }
            (row.getChildAt(1) as TextView).text = note.preview
            row.setOnClickListener { deliverTo(note) }
            return row
        }

        private fun buildRow(parent: ViewGroup): LinearLayout {
            val density = parent.resources.displayMetrics.density
            val pad = (12 * density).toInt()
            val titleView = TextView(parent.context).apply {
                textSize = 16f
                setTypeface(typeface, Typeface.BOLD)
            }
            val previewView = TextView(parent.context).apply {
                textSize = 13f
                maxLines = 2
                ellipsize = android.text.TextUtils.TruncateAt.END
            }
            return LinearLayout(parent.context).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(pad, pad, pad, pad)
                addView(titleView)
                addView(previewView)
                isClickable = true
            }
        }

        private fun deliverTo(note: ShareableNote) {
            val session = ShareBridgeStore.loadSession(this@ShareActivity)
            if (session == null) {
                toast("Sessão expirada. Abra o SupaNotes.")
                finish()
                return
            }
            // Durable persistence first; confirmation only afterwards.
            ShareBridgeStore.writeInboxItem(
                this@ShareActivity,
                shareId = UUID.randomUUID().toString(),
                url = url,
                createdAtIso = Instant.now().toString(),
                noteId = note.noteId,
                ownerUserId = session.optString("ownerUserId"),
            )
            ShareUploadWorker.enqueue(this@ShareActivity)
            toast("Salvo em ${note.title.ifEmpty { "Sem título" }}")
            finish()
        }
    }
}
