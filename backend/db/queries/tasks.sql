-- name: CreateTask :one
INSERT INTO tasks (note_id, user_id, title, due_date, recurrence, position)
VALUES ($1, $2, $3, $4, $5, $6)
RETURNING *;

-- name: GetTasksByNodeID :many
SELECT * FROM tasks
WHERE id = $1 AND deleted_at IS NULL
ORDER BY position ASC, created_at ASC;

-- name: GetTaskByID :one
SELECT * FROM tasks
WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL;

-- name: UpdateTask :one
UPDATE tasks
SET title        = CASE WHEN sqlc.narg('set_title')::bool        THEN sqlc.narg('title')        ELSE title        END,
    status       = CASE WHEN sqlc.narg('set_status')::bool       THEN sqlc.narg('status')       ELSE status       END,
    due_date     = CASE WHEN sqlc.narg('set_due_date')::bool     THEN sqlc.narg('due_date')     ELSE due_date     END,
    recurrence   = CASE WHEN sqlc.narg('set_recurrence')::bool   THEN sqlc.narg('recurrence')   ELSE recurrence   END,
    position     = CASE WHEN sqlc.narg('set_position')::bool     THEN sqlc.narg('position')     ELSE position     END,
    completed_at = CASE WHEN sqlc.narg('set_completed_at')::bool THEN sqlc.narg('completed_at') ELSE completed_at END,
    updated_at   = NOW()
WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL
RETURNING *;

-- name: DeleteTask :exec
UPDATE tasks
SET deleted_at = NOW()
WHERE id = $1 AND user_id = $2;

-- name: DeleteTaskByNodeID :exec
UPDATE tasks
SET deleted_at = NOW()
WHERE id = $1 AND user_id = $2;

-- name: GetTasks :many
SELECT * FROM tasks
WHERE user_id = $1
  AND deleted_at IS NULL
  AND (sqlc.narg('note_id')::uuid IS NULL OR note_id = sqlc.narg('note_id'))
  AND (sqlc.narg('status')::varchar IS NULL OR status = sqlc.narg('status'))
  AND (sqlc.narg('due_after')::date IS NULL OR due_date >= sqlc.narg('due_after')::date)
  AND (sqlc.narg('due_before')::date IS NULL OR due_date <= sqlc.narg('due_before')::date)
ORDER BY due_date ASC NULLS LAST, position ASC, created_at ASC
LIMIT $2 OFFSET $3;

-- name: GetTodayTasks :many
SELECT * FROM tasks
WHERE user_id = $1
  AND deleted_at IS NULL
  AND status = 'open'
  AND due_date IS NOT NULL
  AND due_date <= $2::date
ORDER BY due_date ASC, position ASC, created_at ASC;

-- name: GetTasksByNoteID :many
SELECT * FROM tasks
WHERE user_id = $1 AND note_id = $2 AND deleted_at IS NULL
ORDER BY position ASC, created_at ASC;

-- name: CreateTaskCompletion :one
INSERT INTO task_completions (task_id, completed_at, scheduled_at, due_date)
VALUES ($1, NOW(), NOW(), $2)
RETURNING *;

-- name: CountTasks :one
SELECT COUNT(*) FROM tasks WHERE user_id = $1 AND deleted_at IS NULL;

-- name: CountOpenTasks :one
SELECT COUNT(*) FROM tasks WHERE user_id = $1 AND deleted_at IS NULL AND status = 'open';


-- name: CountCompletedTasks :one
SELECT COUNT(*) FROM tasks WHERE user_id = $1 AND deleted_at IS NULL AND status = 'done';

-- name: SearchTasks :many
SELECT * FROM tasks
WHERE user_id = $1
  AND deleted_at IS NULL
  AND title ILIKE '%' || sqlc.arg('query')::text || '%'
  AND (sqlc.narg('status')::varchar IS NULL OR status = sqlc.narg('status'))
ORDER BY created_at DESC
LIMIT $2 OFFSET $3;

-- name: DeleteTasksByNoteID :exec
UPDATE tasks
SET deleted_at = NOW()
WHERE note_id = $1 AND deleted_at IS NULL AND id <> ALL(sqlc.arg('keep_ids')::uuid[]);

-- name: GetRecentlyCompletedTasks :many
SELECT * FROM tasks
WHERE user_id = $1
  AND deleted_at IS NULL
  AND status = 'done'
  AND completed_at >= NOW() - (sqlc.arg('days')::int || ' days')::interval
ORDER BY completed_at DESC;

-- name: UpsertTasksBatch :exec
INSERT INTO tasks (id, note_id, user_id, title, status, due_date, recurrence, position, completed_at, created_at, deleted_at)
SELECT
  unnest($1::uuid[]),
  unnest($2::uuid[]),
  unnest($3::uuid[]),
  unnest($4::text[]),
  unnest($5::text[]),
  unnest($6::date[]),
  unnest($7::text[]),
  unnest($8::text[]),
  unnest($9::timestamptz[]),
  unnest($10::timestamptz[]),
  unnest($11::timestamptz[])
ON CONFLICT (id) DO UPDATE SET
  title        = EXCLUDED.title,
  status       = EXCLUDED.status,
  due_date     = EXCLUDED.due_date,
  recurrence   = EXCLUDED.recurrence,
  position     = EXCLUDED.position,
  completed_at = EXCLUDED.completed_at,
  deleted_at   = EXCLUDED.deleted_at,
  updated_at   = NOW();
