-- name: GetRetryableEmbeddings :many
SELECT n.id, n.content, n.user_id 
FROM notes n
WHERE (n.embedding_status = 'pending'
   OR (n.embedding_status = 'failed' AND n.updated_at < NOW() - INTERVAL '5 minutes'))
  AND n.deleted_at IS NULL
  AND NOT n.is_inbox
LIMIT $1;

-- name: UpdateNoteEmbeddingStatus :exec
UPDATE notes
SET embedding_status = $2,
    updated_at = NOW()
WHERE id = $1;

-- name: UpsertNoteEmbedding :exec
INSERT INTO note_embeddings (note_id, embedding)
VALUES ($1, $2)
ON CONFLICT (note_id) DO UPDATE SET 
    embedding = EXCLUDED.embedding,
    updated_at = NOW();

-- name: GetSoul :one
SELECT * FROM souls
WHERE user_id = $1;

-- name: UpsertSoul :one
INSERT INTO souls (user_id, personality)
VALUES ($1, $2)
ON CONFLICT (user_id) DO UPDATE SET 
    personality = EXCLUDED.personality,
    updated_at = NOW()
RETURNING *;

-- name: GetMemories :many
SELECT * FROM memories
WHERE user_id = $1
ORDER BY created_at DESC
LIMIT $2 OFFSET $3;

-- name: CreateMemory :one
INSERT INTO memories (user_id, content, embedding)
VALUES ($1, $2, $3)
RETURNING *;

-- name: DeleteMemory :exec
DELETE FROM memories
WHERE id = $1 AND user_id = $2;

-- name: SearchNotesByEmbedding :many
SELECT n.id, regexp_replace(split_part(n.content, E'\n', 1), '^(#+\s+|[-*]\s+(\[[ xX]\]\s+)?|\d+\.\s+)', '') AS title, n.content, n.updated_at, (1 - (ne.embedding <=> $2::vector))::real AS similarity
FROM notes n
JOIN note_embeddings ne ON n.id = ne.note_id
WHERE n.user_id = $1 AND n.deleted_at IS NULL AND NOT n.is_inbox
ORDER BY ne.embedding <=> $2::vector
LIMIT $3;

-- name: SearchMemoriesByEmbedding :many
SELECT m.id, m.content, m.created_at, (1 - (m.embedding <=> $2::vector))::real AS similarity
FROM memories m
WHERE m.user_id = $1
ORDER BY m.embedding <=> $2::vector
LIMIT $3;
