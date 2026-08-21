package com.example.supanotes.share

import org.json.JSONArray
import org.json.JSONObject

/** One editable note as exposed by the Flutter-published notes index. */
data class ShareableNote(
    val noteId: String,
    val title: String,
    val preview: String,
    val updatedAtIso: String,
)

/**
 * Pure parsing/filtering for the `notes_index` envelope. The Dart side always
 * emits UTC RFC3339 timestamps, so ISO strings sort lexicographically.
 */
object ShareNoteIndexJson {
    private const val SCHEMA_VERSION = 1

    /**
     * Returns the editable notes owned by [ownerUserId], sorted updatedAt DESC,
     * or null when the payload is malformed, from another schema/account.
     */
    fun parseForAccount(payload: String?, ownerUserId: String?): List<ShareableNote>? {
        if (payload.isNullOrBlank() || ownerUserId.isNullOrBlank()) return null
        return try {
            val root = JSONObject(payload)
            if (root.optInt("schemaVersion", -1) != SCHEMA_VERSION) return null
            if (root.optString("ownerUserId") != ownerUserId) return null
            val notes = root.optJSONArray("notes") ?: JSONArray()
            (0 until notes.length())
                .map { notes.getJSONObject(it) }
                .filter { it.optBoolean("canEdit", false) }
                .map {
                    ShareableNote(
                        noteId = it.optString("noteId"),
                        title = it.optString("title"),
                        preview = it.optString("preview"),
                        updatedAtIso = it.optString("updatedAt"),
                    )
                }
                .filter { it.noteId.isNotBlank() }
                .sortedByDescending { it.updatedAtIso }
        } catch (_: Exception) {
            null
        }
    }

    fun matchesQuery(note: ShareableNote, rawQuery: String): Boolean {
        val query = rawQuery.trim().lowercase()
        if (query.isEmpty()) return true
        return note.title.lowercase().contains(query) ||
            note.preview.lowercase().contains(query)
    }
}
