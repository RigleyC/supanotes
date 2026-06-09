-- name: CreateRoutine :one
INSERT INTO routines (user_id, type, cron_expr, enabled, name, brief_type)
VALUES ($1, $2, $3, $4, $5, $6)
RETURNING *;

-- name: UpdateRoutine :one
UPDATE routines
SET cron_expr = COALESCE(sqlc.narg('cron_expr'), cron_expr),
    enabled = COALESCE(sqlc.narg('enabled'), enabled),
    updated_at = NOW()
WHERE id = $1 AND user_id = $2
RETURNING *;

-- name: GetRoutinesByUser :many
SELECT * FROM routines
WHERE user_id = $1
ORDER BY created_at ASC;

-- name: GetEnabledRoutines :many
SELECT r.id, r.user_id, r.type, r.cron_expr, r.enabled, s.timezone
FROM routines r
JOIN user_settings s ON r.user_id = s.user_id
WHERE r.enabled = true;

-- name: CreateRoutineLog :one
INSERT INTO routine_logs (routine_id, user_id, status, content, error_msg)
VALUES ($1, $2, $3, $4, $5)
RETURNING *;

-- name: GetRoutineLogsByUser :many
SELECT * FROM routine_logs
WHERE user_id = $1
ORDER BY created_at DESC
LIMIT $2 OFFSET $3;

-- name: CleanupOldMessages :exec
DELETE FROM messages
WHERE created_at < NOW() - INTERVAL '90 days';
