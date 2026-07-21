-- name: GetNoteDocument :one
SELECT revision, document FROM notes WHERE id = $1 AND deleted_at IS NULL;

-- name: InsertOperation :one
INSERT INTO note_operations (note_id, revision, operation_id, actor_id, base_revision, kind, block_id, payload)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
RETURNING *;

-- name: GetOperationsSince :many
SELECT * FROM note_operations
WHERE note_id = $1 AND revision > $2
ORDER BY revision;

-- name: GetLastOperation :one
SELECT * FROM note_operations
WHERE note_id = $1
ORDER BY revision DESC
LIMIT 1;

-- name: UpdateNoteDocument :exec
UPDATE notes
SET document = $2, revision = $3, content = $4, excerpt = $5, snapshot_revision = $6, updated_at = NOW()
WHERE id = $1 AND deleted_at IS NULL;

-- name: LockNote :one
SELECT id, revision, document, snapshot_revision
FROM notes
WHERE id = $1 AND deleted_at IS NULL
FOR UPDATE;

-- name: GetNoteOperationByOpID :one
SELECT * FROM note_operations
WHERE note_id = $1 AND operation_id = $2;

-- name: CheckNotePermission :one
SELECT COALESCE(
  (SELECT 'owner'::text FROM notes WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL),
  (SELECT permission::text FROM note_shares WHERE note_id = $1 AND user_id = $2),
  'none'::text
) AS permission;
