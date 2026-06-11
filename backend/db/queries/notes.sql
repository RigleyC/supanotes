-- name: CreateContext :one
INSERT INTO contexts (user_id, slug, name)
VALUES ($1, $2, $3)
RETURNING *;

-- name: GetContexts :many
SELECT * FROM contexts
WHERE user_id = $1
ORDER BY created_at DESC;

-- name: DeleteContext :exec
DELETE FROM contexts
WHERE id = $1 AND user_id = $2;

-- name: CreateNote :one
INSERT INTO notes (user_id, context_id, title, content, is_inbox, favorite, archived, embedding_status)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
RETURNING *;

-- name: GetNoteByID :one
SELECT * FROM notes
WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL;

-- name: UpdateNote :one
UPDATE notes
SET title = COALESCE(sqlc.narg('title'), title),
    content = COALESCE(sqlc.narg('content'), content),
    context_id = COALESCE(sqlc.narg('context_id'), context_id),
    favorite = COALESCE(sqlc.narg('favorite'), favorite),
    archived = COALESCE(sqlc.narg('archived'), archived),
    embedding_status = COALESCE(sqlc.narg('embedding_status'), embedding_status),
    updated_at = NOW()
WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL
RETURNING *;

-- name: DeleteNote :exec
UPDATE notes
SET deleted_at = NOW()
WHERE id = $1 AND user_id = $2;

-- name: GetNotes :many
SELECT * FROM notes
WHERE user_id = $1
  AND is_inbox = false
  AND deleted_at IS NULL
  AND (sqlc.narg('context_id')::uuid IS NULL OR context_id = sqlc.narg('context_id'))
  AND (sqlc.narg('favorite')::boolean IS NULL OR favorite = sqlc.narg('favorite'))
  AND (sqlc.narg('cursor_updated_at')::timestamptz IS NULL OR updated_at < sqlc.narg('cursor_updated_at') OR (updated_at = sqlc.narg('cursor_updated_at') AND id < sqlc.narg('cursor_id')))
ORDER BY updated_at DESC, id DESC
LIMIT sqlc.arg('limit');

-- name: GetInboxNote :one
SELECT * FROM notes
WHERE user_id = $1 AND is_inbox = true AND deleted_at IS NULL;

-- name: AppendToInbox :one
UPDATE notes
SET content = content || E'\n\n' || $3,
    updated_at = NOW()
WHERE id = $1 AND user_id = $2 AND is_inbox = true AND deleted_at IS NULL
RETURNING *;

-- name: DeleteTag :exec
DELETE FROM tags
WHERE id = $1 AND user_id = $2;

-- name: CreateTag :one
INSERT INTO tags (user_id, name)
VALUES ($1, $2)
RETURNING *;

-- name: GetTags :many
SELECT * FROM tags
WHERE user_id = $1
ORDER BY name ASC;

-- name: GetTagsForNote :many
SELECT t.* FROM tags t
JOIN note_tags nt ON t.id = nt.tag_id
WHERE nt.note_id = $1;

-- name: AddTagToNote :exec
INSERT INTO note_tags (note_id, tag_id)
VALUES ($1, $2)
ON CONFLICT DO NOTHING;

-- name: RemoveTagFromNote :exec
DELETE FROM note_tags
WHERE note_id = $1 AND tag_id = $2;

-- name: GetRecentNotes :many
SELECT * FROM notes
WHERE user_id = $1
  AND is_inbox = false
  AND deleted_at IS NULL
  AND updated_at >= NOW() - INTERVAL '48 hours'
ORDER BY updated_at DESC
LIMIT 10;

-- name: GetLinkedNotes :many
SELECT DISTINCT n.* FROM notes n
JOIN note_links nl ON (n.id = nl.source_id OR n.id = nl.target_id)
WHERE (nl.source_id = ANY($1::uuid[]) OR nl.target_id = ANY($1::uuid[]))
  AND n.id != ALL($1::uuid[])
  AND n.user_id = $2
  AND n.deleted_at IS NULL
LIMIT 5;

-- name: SetInboxContent :one
UPDATE notes
SET content = $3, updated_at = NOW()
WHERE id = $1 AND user_id = $2 AND is_inbox = true AND deleted_at IS NULL
RETURNING *;

-- name: AppendToNoteContent :one
UPDATE notes
SET content = content || E'\n\n' || $3, updated_at = NOW()
WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL AND is_inbox = false
RETURNING *;

-- name: CreateNoteLink :exec
INSERT INTO note_links (source_id, target_id)
VALUES ($1, $2)
ON CONFLICT DO NOTHING;
