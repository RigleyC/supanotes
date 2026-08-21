package com.example.supanotes.share

/**
 * Durable-delivery policy for share upload HTTP outcomes:
 * - success confirms and drains the inbox;
 * - 400/403/404 are terminal (invalid url / permission gone / note gone) —
 *   retrying can never succeed, so the item is dropped to avoid loops;
 * - anything else (network, timeout, 409/429/5xx) retries with backoff;
 * - 401 retries within a bounded budget; once exhausted the worker stops but
 *   KEEPS the inbox item — app resume publishes fresh credentials and
 *   re-enqueues, which resumes delivery.
 */
enum class ShareUploadAction {
    CONFIRM_DELIVERED,
    DROP_AS_TERMINAL,
    RETRY_WITH_BACKOFF,
    WAIT_FOR_REFRESHED_CREDENTIALS,
}

object ShareUploadPolicy {
    const val MAX_ATTEMPTS_BEFORE_REFRESH_WAIT = 10

    fun classify(httpStatus: Int): ShareUploadAction = when {
        httpStatus in 200..299 -> ShareUploadAction.CONFIRM_DELIVERED
        httpStatus == 400 || httpStatus == 403 || httpStatus == 404 ->
            ShareUploadAction.DROP_AS_TERMINAL
        else -> ShareUploadAction.RETRY_WITH_BACKOFF
    }

    fun classifyUnauthorized(runAttemptCount: Int): ShareUploadAction =
        if (runAttemptCount < MAX_ATTEMPTS_BEFORE_REFRESH_WAIT) {
            ShareUploadAction.RETRY_WITH_BACKOFF
        } else {
            ShareUploadAction.WAIT_FOR_REFRESHED_CREDENTIALS
        }
}
