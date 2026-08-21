package com.example.supanotes.share

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.time.Duration
import org.json.JSONObject

/**
 * Drains the share inbox to `POST /notes/:noteId/shared-links` using the same
 * contract as the Flutter client. The backend deduplicates by
 * (userId, shareId), so any overlap between native and Flutter delivery is
 * idempotent.
 */
class ShareUploadWorker(
    context: Context,
    parameters: WorkerParameters,
) : CoroutineWorker(context, parameters) {

    override suspend fun doWork(): Result {
        val context = applicationContext
        val item = ShareBridgeStore.readInboxItem(context) ?: return Result.success()
        val session = ShareBridgeStore.loadSession(context) ?: return Result.retry()
        if (item.optString("ownerUserId") != session.optString("ownerUserId")) {
            // Never deliver account A's pending share under account B.
            ShareBridgeStore.clearInbox(context)
            return Result.failure()
        }
        val status = postSharedLink(session, item)
        if (status == UNAUTHORIZED) {
            val unauthorized = ShareUploadPolicy.classifyUnauthorized(runAttemptCount)
            // WAIT_FOR_REFRESHED_CREDENTIALS keeps the inbox item queued;
            // app resume publishes fresh credentials and re-enqueues.
            return when (unauthorized) {
                ShareUploadAction.RETRY_WITH_BACKOFF -> Result.retry()
                else -> Result.failure()
            }
        }
        return when (ShareUploadPolicy.classify(status)) {
            ShareUploadAction.CONFIRM_DELIVERED, ShareUploadAction.DROP_AS_TERMINAL -> {
                ShareBridgeStore.clearInbox(context)
                Result.success()
            }
            ShareUploadAction.RETRY_WITH_BACKOFF,
            ShareUploadAction.WAIT_FOR_REFRESHED_CREDENTIALS,
            -> Result.retry()
        }
    }

    private fun postSharedLink(session: JSONObject, item: JSONObject): Int {
        val base = session.optString("apiBaseUrl").trimEnd('/')
        val connection =
            URL("$base/notes/${item.optString("noteId")}/shared-links")
                .openConnection() as HttpURLConnection
        return try {
            connection.requestMethod = "POST"
            connection.connectTimeout = TIMEOUT_MS
            connection.readTimeout = TIMEOUT_MS
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty(
                "Authorization",
                "Bearer ${session.optString("accessToken")}",
            )
            val body = JSONObject().apply {
                put("shareId", item.optString("shareId"))
                put("url", item.optString("url"))
                put("createdAt", item.optString("createdAt"))
            }.toString().toByteArray()
            connection.setFixedLengthStreamingMode(body.size)
            connection.outputStream.use { it.write(body) }
            connection.responseCode
        } catch (_: IOException) {
            NETWORK_ERROR
        } finally {
            connection.disconnect()
        }
    }

    companion object {
        private const val UNIQUE_NAME = "share_upload"
        private const val TIMEOUT_MS = 30_000
        private const val UNAUTHORIZED = 401
        private const val NETWORK_ERROR = -1

        /** Re-enqueues delivery; REPLACE so a fresh run always sees new state. */
        fun enqueue(context: Context) {
            val request = OneTimeWorkRequestBuilder<ShareUploadWorker>()
                .setConstraints(
                    Constraints.Builder()
                        .setRequiredNetworkType(NetworkType.CONNECTED)
                        .build(),
                )
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, Duration.ofSeconds(30))
                .build()
            WorkManager.getInstance(context)
                .enqueueUniqueWork(UNIQUE_NAME, ExistingWorkPolicy.REPLACE, request)
        }
    }
}
