-- name: CreateNoteShare :one
INSERT INTO note_shares (note_id, user_id, permission)
VALUES ($1, $2, $3)
ON CONFLICT (note_id, user_id) DO UPDATE
SET permission = EXCLUDED.permission, updated_at = NOW()
RETURNING *;

-- name: GetNoteShares :many
SELECT ns.*, u.email, u.name
FROM note_shares ns
JOIN users u ON u.id = ns.user_id
WHERE ns.note_id = $1;

-- name: DeleteNoteShare :exec
DELETE FROM note_shares
WHERE note_id = $1 AND user_id = $2;

-- name: GetNoteShareForUser :one
SELECT * FROM note_shares
WHERE note_id = $1 AND user_id = $2;

-- name: GetNoteOwner :one
SELECT user_id FROM notes
WHERE id = $1 AND deleted_at IS NULL;
