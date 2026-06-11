-- name: CreateTask :one
INSERT INTO tasks (note_id, user_id, title, due_date, recurrence, position)
VALUES ($1, $2, $3, $4, $5, $6)
RETURNING *;

-- name: GetTaskByID :one
SELECT * FROM tasks
WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL;

-- name: UpdateTask :one
UPDATE tasks
SET title = COALESCE(sqlc.narg('title'), title),
    status = COALESCE(sqlc.narg('status'), status),
    due_date = COALESCE(sqlc.narg('due_date'), due_date),
    recurrence = COALESCE(sqlc.narg('recurrence'), recurrence),
    position = COALESCE(sqlc.narg('position'), position),
    updated_at = NOW()
WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL
RETURNING *;

-- name: DeleteTask :exec
UPDATE tasks
SET deleted_at = NOW()
WHERE id = $1 AND user_id = $2;

-- name: GetTasks :many
SELECT * FROM tasks
WHERE user_id = $1
  AND deleted_at IS NULL
  AND (sqlc.narg('note_id')::uuid IS NULL OR note_id = sqlc.narg('note_id'))
  AND (sqlc.narg('status')::varchar IS NULL OR status = sqlc.narg('status'))
  AND (sqlc.narg('due_after')::timestamptz IS NULL OR due_date >= sqlc.narg('due_after'))
  AND (sqlc.narg('due_before')::timestamptz IS NULL OR due_date <= sqlc.narg('due_before'))
ORDER BY due_date ASC NULLS LAST, position ASC, created_at ASC
LIMIT $2 OFFSET $3;

-- name: GetTodayTasks :many
SELECT * FROM tasks
WHERE user_id = $1
  AND deleted_at IS NULL
  AND status = 'open'
  AND due_date IS NOT NULL
  AND due_date <= $2::timestamptz
ORDER BY due_date ASC, position ASC, created_at ASC;

-- name: GetTasksByNoteID :many
SELECT * FROM tasks
WHERE user_id = $1 AND note_id = $2 AND deleted_at IS NULL
ORDER BY position ASC, created_at ASC;

-- name: CreateTaskCompletion :one
INSERT INTO task_completions (task_id, status)
VALUES ($1, $2)
RETURNING *;

-- name: CountTasks :one
SELECT COUNT(*) FROM tasks WHERE user_id = $1 AND deleted_at IS NULL;

-- name: CountOpenTasks :one
SELECT COUNT(*) FROM tasks WHERE user_id = $1 AND deleted_at IS NULL AND status = 'open';

-- name: CountCompletedTasks :one
SELECT COUNT(*) FROM tasks WHERE user_id = $1 AND deleted_at IS NULL AND status = 'completed';
