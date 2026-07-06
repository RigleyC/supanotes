-- name: SearchNotesFTS :many
SELECT n.id, COALESCE((SELECT (nn.data->>'text')::text FROM note_nodes nn WHERE nn.note_id = n.id AND nn.deleted_at IS NULL AND nn.data->>'text' IS NOT NULL AND nn.data->>'text' <> '' ORDER BY nn.position ASC LIMIT 1), 'Untitled')::text AS title, n.content, n.excerpt, n.updated_at, n.context_id,
       COALESCE(unp.favorite, FALSE) AS favorite,
       COALESCE(unp.archived, FALSE) AS archived,
       ts_rank(n.search_vector, plainto_tsquery('simple', sqlc.arg('query')::text)) AS score
FROM notes n
LEFT JOIN user_note_preferences unp ON unp.note_id = n.id AND unp.user_id = sqlc.arg('user_id')
WHERE n.user_id = sqlc.arg('user_id')
  AND n.deleted_at IS NULL 
  AND COALESCE(unp.archived, FALSE) = false
  AND n.search_vector @@ plainto_tsquery('simple', sqlc.arg('query')::text)
ORDER BY score DESC
LIMIT sqlc.arg('limit');

-- name: SearchNotesSemantic :many
SELECT n.id, COALESCE((SELECT (nn.data->>'text')::text FROM note_nodes nn WHERE nn.note_id = n.id AND nn.deleted_at IS NULL AND nn.data->>'text' IS NOT NULL AND nn.data->>'text' <> '' ORDER BY nn.position ASC LIMIT 1), 'Untitled')::text AS title, n.content, n.excerpt, n.updated_at, n.context_id,
       COALESCE(unp.favorite, FALSE) AS favorite,
       COALESCE(unp.archived, FALSE) AS archived,
       (1.0 - (ne.embedding <=> sqlc.arg('embedding')::vector))::float8 AS score
FROM notes n
JOIN note_embeddings ne ON n.id = ne.note_id
LEFT JOIN user_note_preferences unp ON unp.note_id = n.id AND unp.user_id = sqlc.arg('user_id')
WHERE n.user_id = sqlc.arg('user_id')
  AND n.deleted_at IS NULL 
  AND COALESCE(unp.archived, FALSE) = false
ORDER BY ne.embedding <=> sqlc.arg('embedding')::vector
LIMIT sqlc.arg('limit');

-- name: SearchNotesHybrid :many
WITH fts AS (
  SELECT n.id, COALESCE((SELECT (nn.data->>'text')::text FROM note_nodes nn WHERE nn.note_id = n.id AND nn.deleted_at IS NULL AND nn.data->>'text' IS NOT NULL AND nn.data->>'text' <> '' ORDER BY nn.position ASC LIMIT 1), 'Untitled')::text AS title, n.content, n.excerpt, n.updated_at, n.context_id,
         COALESCE(unp.favorite, FALSE) AS favorite,
         COALESCE(unp.archived, FALSE) AS archived,
         row_number() OVER (ORDER BY ts_rank(n.search_vector, to_tsquery('simple', sqlc.arg('query')::text)) DESC) as rank
  FROM notes n
  LEFT JOIN user_note_preferences unp ON unp.note_id = n.id AND unp.user_id = sqlc.arg('user_id')
  WHERE n.user_id = sqlc.arg('user_id')
    AND n.deleted_at IS NULL 
    AND COALESCE(unp.archived, FALSE) = false
    AND n.search_vector @@ to_tsquery('simple', sqlc.arg('query')::text)
  LIMIT sqlc.arg('fts_limit')::int
),
semantic AS (
  SELECT n.id, COALESCE((SELECT (nn.data->>'text')::text FROM note_nodes nn WHERE nn.note_id = n.id AND nn.deleted_at IS NULL AND nn.data->>'text' IS NOT NULL AND nn.data->>'text' <> '' ORDER BY nn.position ASC LIMIT 1), 'Untitled')::text AS title, n.content, n.excerpt, n.updated_at, n.context_id,
         COALESCE(unp.favorite, FALSE) AS favorite,
         COALESCE(unp.archived, FALSE) AS archived,
         row_number() OVER (ORDER BY ne.embedding <=> sqlc.arg('embedding')::vector) as rank
  FROM notes n
  JOIN note_embeddings ne ON n.id = ne.note_id
  LEFT JOIN user_note_preferences unp ON unp.note_id = n.id AND unp.user_id = sqlc.arg('user_id')
  WHERE n.user_id = sqlc.arg('user_id')
    AND n.deleted_at IS NULL 
    AND COALESCE(unp.archived, FALSE) = false
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
