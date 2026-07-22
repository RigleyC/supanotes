-- name: CreateNote :one
INSERT INTO notes (user_id, content, collapse_images)
VALUES ($1, $2, $3)
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
    collapse_images = COALESCE(sqlc.narg('collapse_images'), collapse_images),
    updated_at = NOW()
WHERE notes.id = $1 AND notes.deleted_at IS NULL
  AND (notes.user_id = $2 OR EXISTS (SELECT 1 FROM note_shares WHERE note_shares.note_id = $1 AND note_shares.user_id = $2 AND note_shares.permission = 'edit'))
RETURNING *;

-- name: DeleteNote :exec
UPDATE notes
SET deleted_at = NOW()
WHERE id = $1 AND user_id = $2;

-- name: HardDeleteOldNotes :exec
DELETE FROM notes
WHERE deleted_at < NOW() - INTERVAL '30 days';

-- name: TryAcquireGCLock :one
SELECT pg_try_advisory_xact_lock(hashtext('gc_notes_lock')) AS acquired;

-- name: GetNotes :many
SELECT
  n.id, n.user_id,
  n.excerpt,
  n.created_at, n.updated_at, n.deleted_at,
  n.collapse_images,
  COALESCE(NULLIF(regexp_replace(split_part(n.content, E'\n', 1), '^#+\s*', ''), ''), '')::text AS title,
  COALESCE(unp.favorite, FALSE)::boolean AS favorite,
  COALESCE(unp.archived, FALSE)::boolean AS archived
FROM notes n
LEFT JOIN user_note_preferences unp ON unp.note_id = n.id AND unp.user_id = $1
WHERE n.deleted_at IS NULL
  AND (n.user_id = $1 OR EXISTS (SELECT 1 FROM note_shares WHERE note_shares.note_id = n.id AND note_shares.user_id = $1))
  AND (sqlc.narg('favorite')::boolean IS NULL OR COALESCE(unp.favorite, FALSE) = sqlc.narg('favorite'))
  AND (sqlc.narg('cursor_updated_at')::timestamptz IS NULL OR n.updated_at < sqlc.narg('cursor_updated_at') OR (n.updated_at = sqlc.narg('cursor_updated_at') AND n.id < sqlc.narg('cursor_id')))
ORDER BY n.updated_at DESC, n.id DESC
LIMIT sqlc.arg('limit');

-- name: GetRecentNotes :many
SELECT
  n.id, n.user_id,
  n.excerpt,
  n.created_at, n.updated_at, n.deleted_at,
  n.collapse_images,
  COALESCE(NULLIF(regexp_replace(split_part(n.content, E'\n', 1), '^#+\s*', ''), '')::text AS title,
  COALESCE(unp.favorite, FALSE)::boolean AS favorite,
  COALESCE(unp.archived, FALSE)::boolean AS archived
FROM notes n
LEFT JOIN user_note_preferences unp ON unp.note_id = n.id AND unp.user_id = $1
WHERE n.user_id = $1
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
LIMIT 5;

-- name: CreateNoteLink :exec
INSERT INTO note_links (source_id, target_id)
VALUES ($1, $2)
ON CONFLICT DO NOTHING;

-- name: GetAllNotesForMigration :many
SELECT id, content FROM notes WHERE content IS NOT NULL AND content != '';

-- name: CountNotes :one
SELECT COUNT(*) FROM notes WHERE user_id = $1 AND deleted_at IS NULL;

-- name: UpdateNoteContent :exec
UPDATE notes SET content = $2, excerpt = COALESCE(substring($2 FROM 1 FOR 200), ''), updated_at = NOW() WHERE id = $1 AND deleted_at IS NULL;
