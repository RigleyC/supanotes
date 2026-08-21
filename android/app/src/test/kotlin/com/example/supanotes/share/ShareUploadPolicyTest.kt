package com.example.supanotes.share

import org.junit.Assert.assertEquals
import org.junit.Test

class ShareUploadPolicyTest {

    @Test
    fun `2xx confirms delivery`() {
        assertEquals(
            ShareUploadAction.CONFIRM_DELIVERED,
            ShareUploadPolicy.classify(200),
        )
        assertEquals(
            ShareUploadAction.CONFIRM_DELIVERED,
            ShareUploadPolicy.classify(204),
        )
    }

    @Test
    fun `terminal errors drop the item`() {
        for (status in listOf(400, 403, 404)) {
            assertEquals(
                ShareUploadAction.DROP_AS_TERMINAL,
                ShareUploadPolicy.classify(status),
            )
        }
    }

    @Test
    fun `transient failures retry with backoff`() {
        for (status in listOf(-1, 408, 409, 429, 500, 503)) {
            assertEquals(
                ShareUploadAction.RETRY_WITH_BACKOFF,
                ShareUploadPolicy.classify(status),
            )
        }
    }

    @Test
    fun `unauthorized retries within budget then waits for refreshed credentials`() {
        assertEquals(
            ShareUploadAction.RETRY_WITH_BACKOFF,
            ShareUploadPolicy.classifyUnauthorized(0),
        )
        assertEquals(
            ShareUploadAction.RETRY_WITH_BACKOFF,
            ShareUploadPolicy.classifyUnauthorized(ShareUploadPolicy.MAX_ATTEMPTS_BEFORE_REFRESH_WAIT - 1),
        )
        assertEquals(
            ShareUploadAction.WAIT_FOR_REFRESHED_CREDENTIALS,
            ShareUploadPolicy.classifyUnauthorized(ShareUploadPolicy.MAX_ATTEMPTS_BEFORE_REFRESH_WAIT),
        )
    }
}
