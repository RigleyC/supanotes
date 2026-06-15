-- name: GetMessages :many
SELECT * FROM (
  SELECT * FROM messages
  WHERE user_id = $1 AND session_id = $2
  ORDER BY created_at DESC
  LIMIT $3 OFFSET $4
) sub
ORDER BY created_at ASC;

-- name: CreateMessage :one
INSERT INTO messages (user_id, session_id, role, content, tool_calls, tool_call_id)
VALUES ($1, $2, $3, $4, $5, $6)
RETURNING *;

-- name: DeleteSessionMessages :exec
DELETE FROM messages
WHERE user_id = $1 AND session_id = $2;
