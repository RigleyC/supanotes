package com.example.supanotes.share

/**
 * URL extraction shared by the native share flow. Mirrors the Dart-side
 * extraction in `shared_link_delivery.dart` so both paths accept the same
 * text; the server re-validates the result either way.
 */
object ShareLinkText {
    private val URL_PATTERN = Regex("(?i)https?://[^\\s<>\"“”]+")
    private val TRAILING_PUNCTUATION = ".,;:!?)]}"

    fun extractUrl(text: String?): String? {
        if (text.isNullOrBlank()) return null
        var value = URL_PATTERN.find(text)?.value ?: return null
        while (value.isNotEmpty() && value.last() in TRAILING_PUNCTUATION) {
            value = value.dropLast(1)
        }
        return value.ifEmpty { null }
    }
}
