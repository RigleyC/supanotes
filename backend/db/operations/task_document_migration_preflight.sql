-- Read-only production preflight for the document-native task migration.
-- Run this script against a backup or a read-only connection first.
-- It does not update or delete any row.

-- 1. Relational inventory.
SELECT
    COUNT(*) AS task_rows,
    COUNT(*) FILTER (WHERE deleted_at IS NULL) AS active_task_rows,
    COUNT(*) FILTER (WHERE deleted_at IS NOT NULL) AS deleted_task_rows
FROM tasks;

SELECT COUNT(*) AS completion_rows
FROM task_completions;

-- 2. Active relational tasks that have no matching task block in the
-- canonical note document. These rows require manual review.
WITH active_tasks AS (
    SELECT t.id, t.note_id, t.title, t.due_date, t.recurrence
    FROM tasks AS t
    WHERE t.deleted_at IS NULL
), document_tasks AS (
    SELECT
        n.id AS note_id,
        block->>'id' AS task_id,
        block->>'delta' AS task_delta,
        block->'metadata' AS metadata
    FROM notes AS n
    CROSS JOIN LATERAL jsonb_array_elements(
        CASE
            WHEN jsonb_typeof(n.document->'blocks') = 'array'
                THEN n.document->'blocks'
            ELSE '[]'::jsonb
        END
    ) AS block
    WHERE n.deleted_at IS NULL
      AND block->>'type' = 'task'
)
SELECT a.*
FROM active_tasks AS a
LEFT JOIN document_tasks AS d
  ON d.note_id = a.note_id
 AND d.task_id = a.id::text
WHERE d.task_id IS NULL
ORDER BY a.note_id, a.id;

-- 3. Task blocks that have no matching active relational row. These are
-- expected for new document-native data after the cutover, but existing
-- rows should be reviewed before deleting the legacy tables.
WITH document_tasks AS (
    SELECT
        n.id AS note_id,
        block->>'id' AS task_id,
        block->'metadata' AS metadata
    FROM notes AS n
    CROSS JOIN LATERAL jsonb_array_elements(
        CASE
            WHEN jsonb_typeof(n.document->'blocks') = 'array'
                THEN n.document->'blocks'
            ELSE '[]'::jsonb
        END
    ) AS block
    WHERE n.deleted_at IS NULL
      AND block->>'type' = 'task'
)
SELECT d.*
FROM document_tasks AS d
LEFT JOIN tasks AS t
  ON t.note_id = d.note_id
 AND t.id::text = d.task_id
 AND t.deleted_at IS NULL
WHERE t.id IS NULL
ORDER BY d.note_id, d.task_id;

-- 4. Completion rows whose task is missing or whose note no longer exists.
SELECT c.id, c.task_id, c.completed_at
FROM task_completions AS c
LEFT JOIN tasks AS t ON t.id = c.task_id
LEFT JOIN notes AS n ON n.id = t.note_id
WHERE t.id IS NULL OR n.id IS NULL
ORDER BY c.task_id, c.completed_at;

-- 5. Review metadata aliases before removing legacy readers. The current
-- canonical contract uses recurrenceRule and isCompleted.
WITH document_tasks AS (
    SELECT
        n.id AS note_id,
        block->>'id' AS task_id,
        block->'metadata' AS metadata
    FROM notes AS n
    CROSS JOIN LATERAL jsonb_array_elements(
        CASE
            WHEN jsonb_typeof(n.document->'blocks') = 'array'
                THEN n.document->'blocks'
            ELSE '[]'::jsonb
        END
    ) AS block
    WHERE n.deleted_at IS NULL
      AND block->>'type' = 'task'
)
SELECT note_id, task_id, metadata
FROM document_tasks
WHERE metadata ? 'recurrence'
   OR metadata ? 'checked'
ORDER BY note_id, task_id;
