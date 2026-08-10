-- name: GetNoteShareLink :one
SELECT note_id, token_id, enabled, created_at, updated_at
FROM note_share_links
WHERE note_id = $1;

-- name: UpsertNoteShareLink :one
INSERT INTO note_share_links (note_id, token_id, enabled)
VALUES ($1, $2, TRUE)
ON CONFLICT (note_id) DO UPDATE
SET token_id = EXCLUDED.token_id,
    enabled = TRUE,
    updated_at = NOW()
RETURNING note_id, token_id, enabled, created_at, updated_at;

-- name: DisableNoteShareLink :exec
UPDATE note_share_links
SET enabled = FALSE, updated_at = NOW()
WHERE note_id = $1;

-- name: GetPublicNoteByShareToken :one
SELECT n.id, n.document, n.updated_at
FROM notes n
JOIN note_share_links sl ON sl.note_id = n.id
WHERE sl.token_id = $1
  AND sl.enabled = TRUE
  AND n.deleted_at IS NULL;
