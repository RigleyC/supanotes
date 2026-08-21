package com.example.supanotes.share

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ShareLinkTextTest {

    @Test
    fun `extracts first url and trims trailing punctuation`() {
        assertEquals(
            "https://exemplo.com/post",
            ShareLinkText.extractUrl("olha isso https://exemplo.com/post."),
        )
        // Trailing unbalanced closers are trimmed one by one, matching the
        // Dart-side extraction exactly.
        assertEquals(
            "https://exemplo.com/a(b",
            ShareLinkText.extractUrl("https://exemplo.com/a(b))"),
        )
    }

    @Test
    fun `prefers the first url in the text`() {
        assertEquals(
            "https://primeira.com",
            ShareLinkText.extractUrl("veja https://primeira.com e https://segunda.com"),
        )
    }

    @Test
    fun `rejects text without http urls`() {
        assertNull(ShareLinkText.extractUrl(null))
        assertNull(ShareLinkText.extractUrl(""))
        assertNull(ShareLinkText.extractUrl("sem link aqui"))
        assertNull(ShareLinkText.extractUrl("ftp://exemplo.com/arquivo"))
    }
}
