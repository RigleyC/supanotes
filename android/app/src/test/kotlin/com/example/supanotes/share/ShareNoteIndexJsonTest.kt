package com.example.supanotes.share

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ShareNoteIndexJsonTest {

    private fun envelope(ownerUserId: String = "user-1", notes: JSONArray) =
        JSONObject().apply {
            put("schemaVersion", 1)
            put("ownerUserId", ownerUserId)
            put("notes", notes)
        }.toString()

    private fun jsonArray(vararg items: JSONObject) =
        JSONArray().apply { items.forEach { put(it) } }

    private fun note(
        noteId: String,
        updatedAt: String,
        title: String = "T",
        canEdit: Boolean = true,
    ) = JSONObject().apply {
        put("noteId", noteId)
        put("title", title)
        put("preview", "P-$noteId")
        put("updatedAt", updatedAt)
        put("canEdit", canEdit)
    }

    @Test
    fun `parses editable notes sorted by updatedAt descending`() {
        val payload = envelope(
            notes = jsonArray(
                note("a", "2026-08-01T10:00:00Z"),
                note("b", "2026-08-03T10:00:00Z"),
                note("c", "2026-08-02T10:00:00Z"),
            ),
        )
        val result = ShareNoteIndexJson.parseForAccount(payload, "user-1")!!
        assertEquals(listOf("b", "c", "a"), result.map { it.noteId })
    }

    @Test
    fun `filters read-only notes`() {
        val payload = envelope(
            notes = jsonArray(
                note("a", "2026-08-01T10:00:00Z"),
                note("b", "2026-08-02T10:00:00Z", canEdit = false),
            ),
        )
        val result = ShareNoteIndexJson.parseForAccount(payload, "user-1")!!
        assertEquals(listOf("a"), result.map { it.noteId })
    }

    @Test
    fun `rejects another account index`() {
        val payload = envelope(ownerUserId = "user-2", notes = jsonArray(note("a", "2026-08-01T10:00:00Z")))
        assertNull(ShareNoteIndexJson.parseForAccount(payload, "user-1"))
    }

    @Test
    fun `rejects malformed payloads`() {
        assertNull(ShareNoteIndexJson.parseForAccount(null, "user-1"))
        assertNull(ShareNoteIndexJson.parseForAccount("", "user-1"))
        assertNull(ShareNoteIndexJson.parseForAccount("{broken", "user-1"))
        assertNull(ShareNoteIndexJson.parseForAccount(envelope(notes = JSONArray()), null))
        val wrongSchema = JSONObject(envelope(notes = JSONArray())).put("schemaVersion", 2).toString()
        assertNull(ShareNoteIndexJson.parseForAccount(wrongSchema, "user-1"))
    }

    @Test
    fun `query matches title or preview case-insensitively`() {
        val note = ShareableNote("a", "Receitas", "bolo de cenoura", "2026-08-01T10:00:00Z")
        assertTrue(ShareNoteIndexJson.matchesQuery(note, ""))
        assertTrue(ShareNoteIndexJson.matchesQuery(note, "  RECEITAS "))
        assertTrue(ShareNoteIndexJson.matchesQuery(note, "cenoura"))
        assertTrue(!ShareNoteIndexJson.matchesQuery(note, "pizza"))
    }
}
