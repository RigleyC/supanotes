-- name: ReserveSharedLinkIngestion :one
INSERT INTO shared_link_ingestions (user_id, share_id, note_id, operation_id)
VALUES ($1, $2, $3, $4)
ON CONFLICT (user_id, share_id) DO UPDATE
SET note_id = shared_link_ingestions.note_id
RETURNING user_id, share_id, note_id, operation_id, created_at;

-- name: GetSharedLinkIngestion :one
SELECT user_id, share_id, note_id, operation_id, created_at
FROM shared_link_ingestions
WHERE user_id = $1 AND share_id = $2;
