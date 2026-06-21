-- name: InsertAttachment :one
INSERT INTO attachments (note_id, filename, url, mime_type, size_bytes)
VALUES ($1, $2, $3, $4, $5)
RETURNING *;

-- name: ListAttachmentsByNote :many
SELECT * FROM attachments
WHERE note_id = $1
ORDER BY created_at ASC;

-- name: DeleteAttachment :exec
DELETE FROM attachments WHERE id = $1;
