-- name: GetSyncNotes :many
SELECT * FROM notes
WHERE user_id = $1 AND updated_at > sqlc.arg('last_synced_at')
ORDER BY updated_at ASC
LIMIT sqlc.arg('limit');

-- name: HardDeleteExpiredNotes :exec
DELETE FROM notes
WHERE deleted_at IS NOT NULL
  AND deleted_at < NOW() - INTERVAL '30 days';

-- name: HardDeleteExpiredTasks :exec
DELETE FROM tasks
WHERE deleted_at IS NOT NULL
  AND deleted_at < NOW() - INTERVAL '30 days';

-- name: HardDeleteExpiredContexts :exec
DELETE FROM contexts
WHERE deleted_at IS NOT NULL
  AND deleted_at < NOW() - INTERVAL '30 days';

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

-- name: GetSyncTags :many
SELECT * FROM tags
WHERE user_id = $1
  AND (created_at > sqlc.arg('last_synced_at') OR sqlc.arg('last_synced_at')::timestamptz IS NULL)
ORDER BY created_at ASC
LIMIT sqlc.arg('limit');

-- name: UpsertTag :one
INSERT INTO tags (id, user_id, name, created_at)
VALUES ($1, $2, $3, $4)
ON CONFLICT (id) DO UPDATE
SET name = EXCLUDED.name
WHERE tags.user_id = EXCLUDED.user_id
RETURNING *;

-- name: UpsertTaskCompletion :exec
-- Inserts a completion row only if the parent task belongs to the user
-- (the SELECT returns 0 rows otherwise, making the INSERT a no-op).
-- Completions are append-only history; existing rows are never updated.
INSERT INTO task_completions (id, task_id, completed_at, status)
SELECT sqlc.arg('id')::uuid,
       sqlc.arg('task_id')::uuid,
       sqlc.arg('completed_at')::timestamptz,
       'completed'
FROM tasks
WHERE tasks.id = sqlc.arg('task_id')::uuid
  AND tasks.user_id = sqlc.arg('user_id')::uuid
ON CONFLICT (id) DO NOTHING;

-- name: GetSyncTaskCompletions :many
-- Returns completion rows belonging to a user's tasks whose
-- `completed_at` is newer than the cursor. The table has no
-- `updated_at`, so we use `completed_at` as the pull cursor —
-- completions are append-only, so any new completion is guaranteed
-- to have a fresh timestamp. The join through `tasks` enforces the
-- per-user scope since `task_completions` itself has no `user_id`.
SELECT tc.id, tc.task_id, tc.completed_at, tc.due_date
FROM task_completions tc
JOIN tasks t ON t.id = tc.task_id
WHERE t.user_id = $1
  AND tc.completed_at > sqlc.arg('last_synced_at')
ORDER BY tc.completed_at ASC
LIMIT sqlc.arg('limit');

-- name: GetSyncNoteTags :many
SELECT nt.note_id, nt.tag_id
FROM note_tags nt
JOIN notes n ON n.id = nt.note_id
WHERE n.user_id = $1;

-- name: UpsertNoteTag :exec
INSERT INTO note_tags (note_id, tag_id)
SELECT sqlc.arg('note_id')::uuid, sqlc.arg('tag_id')::uuid
WHERE EXISTS (
  SELECT 1 FROM notes WHERE id = sqlc.arg('note_id')::uuid AND user_id = sqlc.arg('user_id')::uuid
)
ON CONFLICT (note_id, tag_id) DO NOTHING;

-- name: GetSyncNoteLinks :many
SELECT nl.*
FROM note_links nl
JOIN notes n ON n.id = nl.source_id
WHERE n.user_id = $1;

-- name: UpsertNoteLink :exec
INSERT INTO note_links (id, source_id, target_id, relation, created_at, updated_at)
SELECT sqlc.arg('id')::uuid,
       sqlc.arg('source_id')::uuid,
       sqlc.arg('target_id')::uuid,
       sqlc.arg('relation')::varchar,
       sqlc.arg('created_at')::timestamptz,
       NOW()
WHERE EXISTS (
  SELECT 1 FROM notes WHERE id = sqlc.arg('source_id')::uuid AND user_id = sqlc.arg('user_id')::uuid
)
ON CONFLICT (id) DO UPDATE
SET relation = EXCLUDED.relation,
    updated_at = NOW();
