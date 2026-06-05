-- name: GetSyncNotes :many
SELECT * FROM notes
WHERE user_id = $1 AND updated_at > sqlc.arg('last_synced_at')
ORDER BY updated_at ASC
LIMIT sqlc.arg('limit');

-- name: UpsertNote :one
INSERT INTO notes (id, user_id, context_id, title, content, is_inbox, favorite, archived, embedding_status, created_at, updated_at, deleted_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, NOW(), $11)
ON CONFLICT (id) DO UPDATE
SET context_id = EXCLUDED.context_id,
    title = EXCLUDED.title,
    content = EXCLUDED.content,
    is_inbox = EXCLUDED.is_inbox,
    favorite = EXCLUDED.favorite,
    archived = EXCLUDED.archived,
    embedding_status = EXCLUDED.embedding_status,
    updated_at = NOW(),
    deleted_at = EXCLUDED.deleted_at
WHERE notes.user_id = EXCLUDED.user_id
RETURNING *;

-- name: GetSyncTasks :many
SELECT * FROM tasks
WHERE user_id = $1 AND updated_at > sqlc.arg('last_synced_at')
ORDER BY updated_at ASC
LIMIT sqlc.arg('limit');

-- name: UpsertTask :one
INSERT INTO tasks (id, user_id, note_id, title, status, position, recurrence, due_date, created_at, updated_at, deleted_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW(), $10)
ON CONFLICT (id) DO UPDATE
SET note_id = EXCLUDED.note_id,
    title = EXCLUDED.title,
    status = EXCLUDED.status,
    position = EXCLUDED.position,
    recurrence = EXCLUDED.recurrence,
    due_date = EXCLUDED.due_date,
    updated_at = NOW(),
    deleted_at = EXCLUDED.deleted_at
WHERE tasks.user_id = EXCLUDED.user_id
RETURNING *;

-- name: GetSyncContexts :many
SELECT * FROM contexts
WHERE user_id = $1 AND updated_at > sqlc.arg('last_synced_at')
ORDER BY updated_at ASC
LIMIT sqlc.arg('limit');

-- name: UpsertContext :one
INSERT INTO contexts (id, user_id, slug, name, created_at, updated_at)
VALUES ($1, $2, $3, $4, $5, NOW())
ON CONFLICT (id) DO UPDATE
SET slug = EXCLUDED.slug,
    name = EXCLUDED.name,
    updated_at = NOW()
WHERE contexts.user_id = EXCLUDED.user_id
RETURNING *;
