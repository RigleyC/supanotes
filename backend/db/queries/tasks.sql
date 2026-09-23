-- name: ListTasksForBootstrap :many
SELECT id, owner_user_id, title, due_date, has_time, recurrence_rule, reminder,
       completions, completion_history, is_completed, last_completed_at, revision, schedule_generation,
       created_at, updated_at, deleted_at
FROM tasks
WHERE owner_user_id = $1
ORDER BY due_date NULLS LAST, id;

-- name: GetTaskForOwner :one
SELECT id, owner_user_id, title, due_date, has_time, recurrence_rule, reminder,
       completions, completion_history, is_completed, last_completed_at, revision, schedule_generation,
       created_at, updated_at, deleted_at
FROM tasks
WHERE id = $1 AND owner_user_id = $2;

-- name: LockTaskForOwner :one
SELECT id, owner_user_id, title, due_date, has_time, recurrence_rule, reminder,
       completions, completion_history, is_completed, last_completed_at, revision, schedule_generation,
       created_at, updated_at, deleted_at
FROM tasks
WHERE id = $1 AND owner_user_id = $2
FOR UPDATE;

-- name: GetTaskOperation :one
SELECT task_id, operation_id, payload_hash, response_json, created_at
FROM task_operations
WHERE task_id = $1 AND operation_id = $2;

-- name: InsertTask :one
INSERT INTO tasks (id, owner_user_id, title, due_date, has_time, recurrence_rule, reminder,
                   completions, completion_history, is_completed, last_completed_at, revision, schedule_generation)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, 1, $12)
ON CONFLICT (id) DO NOTHING
RETURNING id, owner_user_id, title, due_date, has_time, recurrence_rule, reminder,
          completions, completion_history, is_completed, last_completed_at, revision, schedule_generation,
          created_at, updated_at, deleted_at;

-- name: UpdateTask :one
UPDATE tasks
SET title = $3, due_date = $4, has_time = $5, recurrence_rule = $6, reminder = $7,
    completions = $8, completion_history = $9, is_completed = $10, last_completed_at = $11,
    revision = revision + 1, schedule_generation = $12,
    deleted_at = $13
WHERE id = $1 AND owner_user_id = $2
RETURNING id, owner_user_id, title, due_date, has_time, recurrence_rule, reminder,
          completions, completion_history, is_completed, last_completed_at, revision, schedule_generation,
          created_at, updated_at, deleted_at;

-- name: InsertTaskOperation :exec
INSERT INTO task_operations (task_id, operation_id, payload_hash, response_json)
VALUES ($1, $2, $3, $4);

-- name: InsertTaskSyncChange :exec
INSERT INTO sync_changes (target_user_id, kind, task_id, revision)
VALUES ($1, $2, $3, $4);

-- name: GetTaskWatermark :one
SELECT COALESCE(MAX(sequence), 0)::bigint
FROM sync_changes
WHERE target_user_id = $1;
