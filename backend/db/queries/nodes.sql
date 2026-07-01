-- name: InsertNode :one
INSERT INTO note_nodes (id, note_id, parent_id, position, type, data)
VALUES ($1, $2, $3, $4, $5, $6)
RETURNING *;

-- name: UpdateNode :one
UPDATE note_nodes
SET position = $2, data = $3, updated_at = NOW()
WHERE id = $1
RETURNING *;

-- name: DeleteNode :exec
DELETE FROM note_nodes WHERE id = $1;

-- name: DeleteNodesByNoteID :exec
DELETE FROM note_nodes WHERE note_id = $1;

-- name: GetNodesByNoteId :many
SELECT * FROM note_nodes WHERE note_id = $1 ORDER BY position ASC;
