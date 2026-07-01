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
INSERT INTO notes (user_id, context_id, content, is_inbox, embedding_status, collapse_images)
VALUES ($1, $2, $3, $4, $5, $6)
RETURNING *;

-- name: GetNoteByID :one
SELECT n.*,
  COALESCE(unp.favorite, FALSE)::boolean AS favorite,
  COALESCE(unp.archived, FALSE)::boolean AS archived
FROM notes n
LEFT JOIN user_note_preferences unp ON unp.note_id = n.id AND unp.user_id = $2
WHERE n.id = $1 AND n.deleted_at IS NULL
  AND (n.user_id = $2 OR EXISTS (SELECT 1 FROM note_shares WHERE note_shares.note_id = $1 AND note_shares.user_id = $2));

-- name: UpdateNote :one
UPDATE notes
SET content = COALESCE(sqlc.narg('content'), content),
    context_id = COALESCE(sqlc.narg('context_id'), context_id),
    embedding_status = COALESCE(sqlc.narg('embedding_status'), embedding_status),
    collapse_images = COALESCE(sqlc.narg('collapse_images'), collapse_images),
    updated_at = NOW()
WHERE notes.id = $1 AND notes.deleted_at IS NULL
  AND (notes.user_id = $2 OR EXISTS (SELECT 1 FROM note_shares WHERE note_shares.note_id = $1 AND note_shares.user_id = $2 AND note_shares.permission = 'edit'))
RETURNING *;

-- name: DeleteNote :exec
UPDATE notes
SET deleted_at = NOW()
WHERE id = $1 AND user_id = $2;

-- name: GetNotes :many
SELECT n.*,
  COALESCE(unp.favorite, FALSE)::boolean AS favorite,
  COALESCE(unp.archived, FALSE)::boolean AS archived
FROM notes n
LEFT JOIN user_note_preferences unp ON unp.note_id = n.id AND unp.user_id = $1
WHERE n.is_inbox = false
  AND n.deleted_at IS NULL
  AND (n.user_id = $1 OR EXISTS (SELECT 1 FROM note_shares WHERE note_shares.note_id = n.id AND note_shares.user_id = $1))
  AND (sqlc.narg('context_id')::uuid IS NULL OR n.context_id = sqlc.narg('context_id'))
  AND (sqlc.narg('favorite')::boolean IS NULL OR COALESCE(unp.favorite, FALSE) = sqlc.narg('favorite'))
  AND (sqlc.narg('cursor_updated_at')::timestamptz IS NULL OR n.updated_at < sqlc.narg('cursor_updated_at') OR (n.updated_at = sqlc.narg('cursor_updated_at') AND n.id < sqlc.narg('cursor_id')))
ORDER BY n.updated_at DESC, n.id DESC
LIMIT sqlc.arg('limit');

-- name: GetInboxNote :one
SELECT n.*,
  COALESCE(unp.favorite, FALSE)::boolean AS favorite,
  COALESCE(unp.archived, FALSE)::boolean AS archived
FROM notes n
LEFT JOIN user_note_preferences unp ON unp.note_id = n.id AND unp.user_id = $1
WHERE n.user_id = $1 AND n.is_inbox = true AND n.deleted_at IS NULL;

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
SELECT n.*,
  COALESCE(unp.favorite, FALSE)::boolean AS favorite,
  COALESCE(unp.archived, FALSE)::boolean AS archived
FROM notes n
LEFT JOIN user_note_preferences unp ON unp.note_id = n.id AND unp.user_id = $1
WHERE n.user_id = $1
  AND n.is_inbox = false
  AND n.deleted_at IS NULL
  AND n.updated_at >= NOW() - INTERVAL '48 hours'
ORDER BY n.updated_at DESC
LIMIT 10;

-- name: GetLinkedNotes :many
SELECT DISTINCT n.* FROM notes n
JOIN note_links nl ON (n.id = nl.source_id OR n.id = nl.target_id)
WHERE (nl.source_id = ANY($1::uuid[]) OR nl.target_id = ANY($1::uuid[]))
  AND n.id != ALL($1::uuid[])
  AND n.user_id = $2
  AND n.deleted_at IS NULL
  AND n.is_inbox = false
LIMIT 5;

-- name: SetInboxContent :one
UPDATE notes
SET content = $3, updated_at = NOW()
WHERE id = $1 AND user_id = $2 AND is_inbox = true AND deleted_at IS NULL
RETURNING *;

-- name: AppendToNoteContent :one
UPDATE notes
SET content = content || E'\n\n' || $3, updated_at = NOW()
WHERE notes.id = $1 AND notes.deleted_at IS NULL AND notes.is_inbox = false
  AND (notes.user_id = $2 OR EXISTS (SELECT 1 FROM note_shares WHERE note_shares.note_id = $1 AND note_shares.user_id = $2 AND note_shares.permission = 'edit'))
RETURNING *;

-- name: CreateNoteLink :exec
INSERT INTO note_links (source_id, target_id)
VALUES ($1, $2)
ON CONFLICT DO NOTHING;

-- name: UpdateNoteSearchVector :exec
UPDATE notes SET search_vector = $2 WHERE id = $1;

-- name: GetAllNotesForMigration :many
SELECT id, content FROM notes WHERE content IS NOT NULL AND content != '';

-- name: CountNotes :one
SELECT COUNT(*) FROM notes WHERE user_id = $1 AND deleted_at IS NULL AND NOT is_inbox;
