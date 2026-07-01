-- name: GetSyncNotes :many
SELECT n.*,
  COALESCE(unp.favorite, FALSE)::boolean AS favorite,
  COALESCE(unp.archived, FALSE)::boolean AS archived,
  COALESCE(ns.permission, '')::text AS shared_permission,
  CASE WHEN ns.id IS NOT NULL THEN COALESCE(u.email, '') ELSE '' END AS shared_by_email,
  CASE WHEN ns.id IS NOT NULL THEN COALESCE(u.name, '') ELSE '' END AS shared_by_name
FROM notes n
LEFT JOIN user_note_preferences unp ON unp.note_id = n.id AND unp.user_id = sqlc.arg('user_id')::uuid
LEFT JOIN note_shares ns ON ns.note_id = n.id AND ns.user_id = sqlc.arg('user_id')::uuid
LEFT JOIN users u ON u.id = n.user_id
WHERE (n.user_id = sqlc.arg('user_id')::uuid OR ns.user_id = sqlc.arg('user_id')::uuid)
  AND n.updated_at > sqlc.arg('last_synced_at')
ORDER BY n.updated_at ASC
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
INSERT INTO notes (id, user_id, context_id, content, is_inbox, embedding_status, collapse_images, created_at, updated_at, deleted_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW(), $9)
ON CONFLICT (id) DO UPDATE
SET context_id = EXCLUDED.context_id,
    content = EXCLUDED.content,
    is_inbox = EXCLUDED.is_inbox,
    embedding_status = EXCLUDED.embedding_status,
    collapse_images = EXCLUDED.collapse_images,
    updated_at = NOW(),
    deleted_at = EXCLUDED.deleted_at
WHERE notes.user_id = EXCLUDED.user_id
RETURNING *;

-- name: GetSyncTasks :many
SELECT t.*
FROM tasks t
JOIN notes n ON n.id = t.note_id
LEFT JOIN note_shares ns ON ns.note_id = n.id AND ns.user_id = sqlc.arg('user_id')::uuid
WHERE (n.user_id = sqlc.arg('user_id')::uuid OR ns.user_id = sqlc.arg('user_id')::uuid)
  AND t.updated_at > sqlc.arg('last_synced_at')
ORDER BY t.updated_at ASC
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
INSERT INTO task_completions (id, task_id, completed_at)
SELECT sqlc.arg('id')::uuid,
       sqlc.arg('task_id')::uuid,
       sqlc.arg('completed_at')::timestamptz
FROM tasks
WHERE tasks.id = sqlc.arg('task_id')::uuid
  AND (tasks.user_id = sqlc.arg('user_id')::uuid
       OR EXISTS (SELECT 1 FROM note_shares ns
                  WHERE ns.note_id = tasks.note_id
                    AND ns.user_id = sqlc.arg('user_id')::uuid
                    AND ns.permission = 'edit'))
ON CONFLICT (id) DO NOTHING;

-- name: GetSyncTaskCompletions :many
SELECT tc.id, tc.task_id, tc.completed_at, tc.due_date
FROM task_completions tc
JOIN tasks t ON t.id = tc.task_id
JOIN notes n ON n.id = t.note_id
LEFT JOIN note_shares ns ON ns.note_id = n.id AND ns.user_id = sqlc.arg('user_id')::uuid
WHERE (n.user_id = sqlc.arg('user_id')::uuid OR ns.user_id = sqlc.arg('user_id')::uuid)
  AND tc.completed_at > sqlc.arg('last_synced_at')
ORDER BY tc.completed_at ASC
LIMIT sqlc.arg('limit');

-- name: GetSyncNoteTags :many
SELECT nt.note_id, nt.tag_id
FROM note_tags nt
JOIN notes n ON n.id = nt.note_id
LEFT JOIN note_shares ns ON ns.note_id = n.id AND ns.user_id = sqlc.arg('user_id')::uuid
WHERE (n.user_id = sqlc.arg('user_id')::uuid OR ns.user_id = sqlc.arg('user_id')::uuid);

-- name: UpsertNoteTag :exec
INSERT INTO note_tags (note_id, tag_id)
SELECT sqlc.arg('note_id')::uuid, sqlc.arg('tag_id')::uuid
WHERE EXISTS (
  SELECT 1 FROM notes WHERE id = sqlc.arg('note_id')::uuid
    AND (user_id = sqlc.arg('user_id')::uuid
         OR EXISTS (SELECT 1 FROM note_shares
                    WHERE note_id = sqlc.arg('note_id')::uuid
                      AND user_id = sqlc.arg('user_id')::uuid
                      AND permission = 'edit'))
)
ON CONFLICT (note_id, tag_id) DO NOTHING;

-- name: GetSyncNoteLinks :many
SELECT nl.*
FROM note_links nl
JOIN notes n ON n.id = nl.source_id
LEFT JOIN note_shares ns ON ns.note_id = n.id AND ns.user_id = sqlc.arg('user_id')::uuid
WHERE (n.user_id = sqlc.arg('user_id')::uuid OR ns.user_id = sqlc.arg('user_id')::uuid);

-- name: UpsertNoteLink :exec
INSERT INTO note_links (id, source_id, target_id, relation, created_at, updated_at)
SELECT sqlc.arg('id')::uuid,
       sqlc.arg('source_id')::uuid,
       sqlc.arg('target_id')::uuid,
       sqlc.arg('relation')::varchar,
       sqlc.arg('created_at')::timestamptz,
       NOW()
WHERE EXISTS (
  SELECT 1 FROM notes WHERE id = sqlc.arg('source_id')::uuid
    AND (user_id = sqlc.arg('user_id')::uuid
         OR EXISTS (SELECT 1 FROM note_shares
                    WHERE note_id = sqlc.arg('source_id')::uuid
                      AND user_id = sqlc.arg('user_id')::uuid
                      AND permission = 'edit'))
)
ON CONFLICT (id) DO UPDATE
SET relation = EXCLUDED.relation,
    updated_at = NOW();

-- name: GetSyncUserNotePreferences :many
SELECT * FROM user_note_preferences
WHERE user_id = $1 AND updated_at > sqlc.arg('last_synced_at')
ORDER BY updated_at ASC
LIMIT sqlc.arg('limit');

-- name: GetNoteOwnerID :one
SELECT user_id FROM notes WHERE id = $1;

-- name: UpsertUserNotePreference :one
INSERT INTO user_note_preferences (user_id, note_id, hide_completed, filters, favorite, archived, created_at, updated_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, NOW())
ON CONFLICT (user_id, note_id) DO UPDATE
SET hide_completed = EXCLUDED.hide_completed,
    filters = EXCLUDED.filters,
    favorite = EXCLUDED.favorite,
    archived = EXCLUDED.archived,
    updated_at = NOW()
RETURNING *;

-- name: GetSyncNoteNodes :many
SELECT nn.*
FROM note_nodes nn
JOIN notes n ON n.id = nn.note_id
LEFT JOIN note_shares ns ON ns.note_id = n.id AND ns.user_id = sqlc.arg('user_id')::uuid
WHERE (n.user_id = sqlc.arg('user_id')::uuid OR ns.user_id = sqlc.arg('user_id')::uuid)
  AND nn.updated_at > sqlc.arg('last_synced_at')
ORDER BY nn.updated_at ASC
LIMIT sqlc.arg('limit');

-- name: UpsertNoteNode :one
INSERT INTO note_nodes (id, note_id, parent_id, position, type, data, created_at, updated_at, deleted_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, NOW(), $8)
ON CONFLICT (id) DO UPDATE
SET note_id = EXCLUDED.note_id,
    parent_id = EXCLUDED.parent_id,
    position = EXCLUDED.position,
    type = EXCLUDED.type,
    data = EXCLUDED.data,
    updated_at = NOW(),
    deleted_at = EXCLUDED.deleted_at
RETURNING *;
