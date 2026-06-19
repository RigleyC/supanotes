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

-- name: CreatePendingToolConfirmation :one
INSERT INTO pending_tool_confirmations (user_id, session_id, tool_name, args_json, status)
VALUES ($1, $2, $3, $4, 'pending')
RETURNING *;

-- name: GetPendingToolConfirmation :one
SELECT *
FROM pending_tool_confirmations
WHERE id = $1 AND user_id = $2;

-- name: ResolvePendingToolConfirmation :one
UPDATE pending_tool_confirmations
SET status = $3, resolved_at = NOW()
WHERE id = $1 AND user_id = $2 AND status = 'pending'
RETURNING *;
