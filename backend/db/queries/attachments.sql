-- name: InsertAttachment :one
WITH storage_key_lock AS (
    SELECT pg_advisory_xact_lock(hashtextextended($3, 0))
), available_key AS (
    SELECT $1 AS note_id, $2 AS filename, $3 AS storage_key,
           $4 AS mime_type, $5 AS size_bytes
    FROM storage_key_lock
    WHERE NOT EXISTS (
        SELECT 1
        FROM attachment_deletion_outbox
        WHERE storage_key = $3
          AND status IN ('pending', 'processing')
    )
)
INSERT INTO attachments (note_id, filename, storage_key, mime_type, size_bytes)
SELECT note_id, filename, storage_key, mime_type, size_bytes
FROM available_key
RETURNING *;

-- name: ListAttachmentsByNote :many
SELECT * FROM attachments
WHERE note_id = $1
ORDER BY created_at ASC;

-- name: GetAttachmentByID :one
SELECT * FROM attachments
WHERE id = $1;

-- name: DeleteAttachment :exec
DELETE FROM attachments WHERE id = $1;

-- name: EnqueueAttachmentDeletion :exec
WITH storage_key_lock AS (
    SELECT pg_advisory_xact_lock(hashtextextended($1, 0))
)
INSERT INTO attachment_deletion_outbox (storage_key)
SELECT $1
FROM storage_key_lock
WHERE NOT EXISTS (
    SELECT 1 FROM attachments WHERE storage_key = $1
)
ON CONFLICT DO NOTHING;

-- name: ClaimAttachmentDeletion :one
SELECT id, storage_key, referenced
FROM claim_attachment_storage_deletion(sqlc.narg('storage_key')::text);

-- name: CompleteAttachmentDeletion :exec
DELETE FROM attachment_deletion_outbox
WHERE id = $1;

-- name: RetryAttachmentDeletion :exec
UPDATE attachment_deletion_outbox
SET status = 'pending',
    available_at = NOW() + INTERVAL '1 minute',
    last_error = $2,
    updated_at = NOW()
WHERE id = $1;
