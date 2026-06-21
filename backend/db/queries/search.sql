-- name: SearchNotesFTS :many
SELECT n.id, regexp_replace(split_part(n.content, E'\n', 1), '^(#+\s*|[-*]\s*(\[[ xX]\]\s*)?|\d+\.\s*)', '') AS title, n.content, n.excerpt, n.updated_at, n.context_id, n.favorite, n.archived,
       ts_rank(n.search_vector, plainto_tsquery('simple', sqlc.arg('query')::text)) AS score
FROM notes n
WHERE n.user_id = sqlc.arg('user_id')
  AND n.deleted_at IS NULL 
  AND NOT n.is_inbox
  AND n.archived = false
  AND n.search_vector @@ plainto_tsquery('simple', sqlc.arg('query')::text)
ORDER BY score DESC
LIMIT sqlc.arg('limit');

-- name: SearchNotesSemantic :many
SELECT n.id, regexp_replace(split_part(n.content, E'\n', 1), '^(#+\s*|[-*]\s*(\[[ xX]\]\s*)?|\d+\.\s*)', '') AS title, n.content, n.excerpt, n.updated_at, n.context_id, n.favorite, n.archived,
       (1.0 - (ne.embedding <=> sqlc.arg('embedding')::vector))::float8 AS score
FROM notes n
JOIN note_embeddings ne ON n.id = ne.note_id
WHERE n.user_id = sqlc.arg('user_id')
  AND n.deleted_at IS NULL 
  AND NOT n.is_inbox
  AND n.archived = false
ORDER BY ne.embedding <=> sqlc.arg('embedding')::vector
LIMIT sqlc.arg('limit');

-- name: SearchNotesHybrid :many
WITH fts AS (
  SELECT n.id, regexp_replace(split_part(n.content, E'\n', 1), '^(#+\s*|[-*]\s*(\[[ xX]\]\s*)?|\d+\.\s*)', '') AS title, n.content, n.excerpt, n.updated_at, n.context_id, n.favorite, n.archived,
         row_number() OVER (ORDER BY ts_rank(n.search_vector, to_tsquery('simple', sqlc.arg('query')::text)) DESC) as rank
  FROM notes n
  WHERE n.user_id = sqlc.arg('user_id')
    AND n.deleted_at IS NULL 
    AND NOT n.is_inbox
    AND n.archived = false
    AND n.search_vector @@ to_tsquery('simple', sqlc.arg('query')::text)
  LIMIT sqlc.arg('fts_limit')::int
),
semantic AS (
  SELECT n.id, regexp_replace(split_part(n.content, E'\n', 1), '^(#+\s*|[-*]\s*(\[[ xX]\]\s*)?|\d+\.\s*)', '') AS title, n.content, n.excerpt, n.updated_at, n.context_id, n.favorite, n.archived,
         row_number() OVER (ORDER BY ne.embedding <=> sqlc.arg('embedding')::vector) as rank
  FROM notes n
  JOIN note_embeddings ne ON n.id = ne.note_id
  WHERE n.user_id = sqlc.arg('user_id')
    AND n.deleted_at IS NULL 
    AND NOT n.is_inbox
    AND n.archived = false
  LIMIT sqlc.arg('semantic_limit')::int
)
SELECT 
  COALESCE(fts.id, semantic.id) as id,
  COALESCE(fts.title, semantic.title) as title,
  COALESCE(fts.content, semantic.content) as content,
  COALESCE(fts.excerpt, semantic.excerpt) as excerpt,
  COALESCE(fts.updated_at, semantic.updated_at) as updated_at,
  COALESCE(fts.context_id, semantic.context_id) as context_id,
  COALESCE(fts.favorite, semantic.favorite) as favorite,
  COALESCE(fts.archived, semantic.archived) as archived,
  (COALESCE(1.0 / (60.0 + fts.rank), 0.0) + COALESCE(1.0 / (60.0 + semantic.rank), 0.0))::float8 AS score
FROM fts
FULL OUTER JOIN semantic ON fts.id = semantic.id
ORDER BY score DESC
LIMIT sqlc.arg('limit')::int;
