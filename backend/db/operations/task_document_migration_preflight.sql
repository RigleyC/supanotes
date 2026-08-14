-- Read-only production preflight for the document-native task migration.
-- Run this script against a backup or a read-only connection first.
-- It does not update or delete any row.

-- 1. Canonical document envelope and block shape. The strict REST/OT reader
-- rejects these rows; review them before releasing the strict decoder.
SELECT
    n.id AS note_id,
    jsonb_typeof(n.document) AS document_type,
    n.document->>'schemaVersion' AS schema_version,
    jsonb_typeof(n.document->'blocks') AS blocks_type,
    jsonb_array_length(
        CASE
            WHEN jsonb_typeof(n.document->'blocks') = 'array'
                THEN n.document->'blocks'
            ELSE '[]'::jsonb
        END
    ) AS block_count
FROM notes AS n
WHERE n.deleted_at IS NULL
  AND (
      jsonb_typeof(n.document) IS DISTINCT FROM 'object'
      OR n.document->>'schemaVersion' <> '1'
      OR jsonb_typeof(n.document->'blocks') IS DISTINCT FROM 'array'
      OR jsonb_array_length(
          CASE
              WHEN jsonb_typeof(n.document->'blocks') = 'array'
                  THEN n.document->'blocks'
              ELSE '[]'::jsonb
          END
      ) = 0
  )
ORDER BY n.id;

WITH document_blocks AS (
    SELECT
        n.id AS note_id,
        block_index,
        block
    FROM notes AS n
    CROSS JOIN LATERAL jsonb_array_elements(
        CASE
            WHEN jsonb_typeof(n.document->'blocks') = 'array'
                THEN n.document->'blocks'
            ELSE '[]'::jsonb
        END
    ) WITH ORDINALITY AS item(block, block_index)
    WHERE n.deleted_at IS NULL
)
SELECT
    note_id,
    block_index,
    block->>'id' AS block_id,
    block->>'type' AS block_type,
    jsonb_typeof(block->'delta') AS delta_type,
    jsonb_typeof(block->'metadata') AS metadata_type
FROM document_blocks
WHERE jsonb_typeof(block) IS DISTINCT FROM 'object'
   OR jsonb_typeof(block->'id') <> 'string'
   OR COALESCE(block->>'id', '') = ''
   OR block->>'type' NOT IN (
       'paragraph', 'header1', 'header2', 'header3', 'quote',
       'bulletList', 'orderedList', 'task', 'divider', 'attachment',
       'rich_link'
   )
   OR jsonb_typeof(block->'delta') IS DISTINCT FROM 'array'
   OR (block ? 'metadata'
       AND jsonb_typeof(block->'metadata') NOT IN ('object', 'null'))
ORDER BY note_id, block_index;

WITH document_blocks AS (
    SELECT
        n.id AS note_id,
        block_index,
        block
    FROM notes AS n
    CROSS JOIN LATERAL jsonb_array_elements(
        CASE
            WHEN jsonb_typeof(n.document->'blocks') = 'array'
                THEN n.document->'blocks'
            ELSE '[]'::jsonb
        END
    ) WITH ORDINALITY AS item(block, block_index)
    WHERE n.deleted_at IS NULL
), block_ids AS (
    SELECT note_id, block->>'id' AS block_id, COUNT(*) AS occurrences
    FROM document_blocks
    GROUP BY note_id, block->>'id'
)
SELECT note_id, block_id, occurrences
FROM block_ids
WHERE block_id IS NOT NULL
  AND occurrences > 1
ORDER BY note_id, block_id;

WITH document_blocks AS (
    SELECT
        n.id AS note_id,
        block_index,
        block
    FROM notes AS n
    CROSS JOIN LATERAL jsonb_array_elements(
        CASE
            WHEN jsonb_typeof(n.document->'blocks') = 'array'
                THEN n.document->'blocks'
            ELSE '[]'::jsonb
        END
    ) WITH ORDINALITY AS item(block, block_index)
    WHERE n.deleted_at IS NULL
), delta_operations AS (
    SELECT
        note_id,
        block_index,
        block->>'id' AS block_id,
        operation_index,
        operation
    FROM document_blocks
    CROSS JOIN LATERAL jsonb_array_elements(
        CASE
            WHEN jsonb_typeof(block->'delta') = 'array'
                THEN block->'delta'
            ELSE '[]'::jsonb
        END
    ) WITH ORDINALITY AS item(operation, operation_index)
)
SELECT
    note_id,
    block_id,
    block_index,
    operation_index,
    operation
FROM delta_operations
WHERE jsonb_typeof(operation) IS DISTINCT FROM 'object'
   OR jsonb_typeof(operation->'insert') IS DISTINCT FROM 'string'
   OR (operation ? 'attributes'
       AND jsonb_typeof(operation->'attributes') NOT IN ('object', 'null'))
ORDER BY note_id, block_index, operation_index;

WITH document_blocks AS (
    SELECT
        n.id AS note_id,
        block->>'id' AS block_id,
        block
    FROM notes AS n
    CROSS JOIN LATERAL jsonb_array_elements(
        CASE
            WHEN jsonb_typeof(n.document->'blocks') = 'array'
                THEN n.document->'blocks'
            ELSE '[]'::jsonb
        END
    ) AS item(block)
    WHERE n.deleted_at IS NULL
), delta_attributes AS (
    SELECT
        note_id,
        block_id,
        operation_index,
        attribute_key,
        attribute_value
    FROM document_blocks
    CROSS JOIN LATERAL jsonb_array_elements(
        CASE
            WHEN jsonb_typeof(block->'delta') = 'array'
                THEN block->'delta'
            ELSE '[]'::jsonb
        END
    ) WITH ORDINALITY AS operations(operation, operation_index)
    CROSS JOIN LATERAL jsonb_each(
        CASE
            WHEN jsonb_typeof(operation->'attributes') = 'object'
                THEN operation->'attributes'
            ELSE '{}'::jsonb
        END
    ) AS attributes(attribute_key, attribute_value)
)
SELECT
    note_id,
    block_id,
    operation_index,
    attribute_key,
    attribute_value
FROM delta_attributes
WHERE (attribute_key = 'link'
       AND jsonb_typeof(attribute_value) IS DISTINCT FROM 'string')
   OR (attribute_key LIKE 'link:%'
       AND attribute_value IS DISTINCT FROM 'true'::jsonb)
   OR attribute_key LIKE 'link:https://%60%'
   OR attribute_key LIKE 'link:https://(%60%'
ORDER BY note_id, block_id, operation_index, attribute_key;

-- 2. Relational inventory.
SELECT
    COUNT(*) AS task_rows,
    COUNT(*) FILTER (WHERE deleted_at IS NULL) AS active_task_rows,
    COUNT(*) FILTER (WHERE deleted_at IS NOT NULL) AS deleted_task_rows
FROM tasks;

SELECT COUNT(*) AS completion_rows
FROM task_completions;

-- 3. Active relational tasks that have no matching task block in the
-- canonical note document. These rows require manual review.
WITH active_tasks AS (
    SELECT t.id, t.note_id
    FROM tasks AS t
    WHERE t.deleted_at IS NULL
), document_tasks AS (
    SELECT
        n.id AS note_id,
        block->>'id' AS task_id
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

-- 4. Task blocks that have no matching active relational row. These are
-- expected for new document-native data after the cutover, but existing
-- rows should be reviewed before deleting the legacy tables.
WITH document_tasks AS (
    SELECT
        n.id AS note_id,
        block->>'id' AS task_id
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

-- 5. Completion rows whose task is missing or whose note no longer exists.
SELECT c.id, c.task_id, c.completed_at
FROM task_completions AS c
LEFT JOIN tasks AS t ON t.id = c.task_id
LEFT JOIN notes AS n ON n.id = t.note_id
WHERE t.id IS NULL OR n.id IS NULL
ORDER BY c.task_id, c.completed_at;

-- 6. Review metadata aliases before removing legacy readers. The current
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
SELECT
    note_id,
    task_id,
    (metadata ? 'recurrence') AS has_legacy_recurrence,
    (metadata ? 'checked') AS has_legacy_checked
FROM document_tasks
WHERE metadata ? 'recurrence'
   OR metadata ? 'checked'
ORDER BY note_id, task_id;

-- 7. Canonical metadata shape. These rows cannot enter the new runtime until
-- the value is repaired by an approved document backfill.
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
SELECT
    note_id,
    task_id,
    jsonb_typeof(metadata->'isCompleted') AS is_completed_type,
    jsonb_typeof(metadata->'dueDate') AS due_date_type,
    jsonb_typeof(metadata->'hasTime') AS has_time_type,
    jsonb_typeof(metadata->'indent') AS indent_type,
    jsonb_typeof(metadata->'recurrenceRule') AS recurrence_type,
    jsonb_typeof(metadata->'reminder') AS reminder_type,
    jsonb_typeof(metadata->'completions') AS completions_type,
    jsonb_typeof(metadata->'lastCompletedAt') AS last_completed_at_type
FROM document_tasks
WHERE (metadata ? 'isCompleted'
       AND jsonb_typeof(metadata->'isCompleted') <> 'boolean')
   OR (metadata ? 'dueDate' AND jsonb_typeof(metadata->'dueDate') <> 'string')
   OR (metadata ? 'hasTime' AND jsonb_typeof(metadata->'hasTime') <> 'boolean')
   OR (metadata ? 'indent'
       AND (jsonb_typeof(metadata->'indent') <> 'number'
            OR metadata->>'indent' !~ '^[0-9]+$'))
   OR (metadata ? 'recurrenceRule'
       AND jsonb_typeof(metadata->'recurrenceRule') <> 'string')
   OR (metadata ? 'reminder'
       AND jsonb_typeof(metadata->'reminder') <> 'string')
   OR (metadata ? 'completions'
       AND jsonb_typeof(metadata->'completions') <> 'object')
   OR (metadata ? 'lastCompletedAt'
       AND jsonb_typeof(metadata->'lastCompletedAt') <> 'string')
ORDER BY note_id, task_id;

-- 7. Canonical task values. These checks are separate from the type check
-- because a string can still contain an offset, an old enum, or an invalid
-- timestamp.
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
SELECT
    note_id,
    task_id,
    metadata->>'dueDate' AS due_date,
    metadata->>'recurrenceRule' AS recurrence_rule,
    metadata->>'reminder' AS reminder,
    metadata->>'lastCompletedAt' AS last_completed_at
FROM document_tasks
WHERE (metadata ? 'dueDate'
       AND metadata->>'dueDate' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}(\d{3})?$')
   OR (metadata ? 'recurrenceRule'
       AND metadata->>'recurrenceRule' NOT IN ('daily', 'weekdays', 'weekly', 'monthly'))
   OR (metadata ? 'reminder'
       AND metadata->>'reminder' NOT IN (
           'at_time', '5m_before', '1h_before', '1d_before',
           '9am', '12pm', '6pm', '1d_before_9am'
       ))
   OR (metadata ? 'lastCompletedAt'
       AND metadata->>'lastCompletedAt' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}(\d{3})?Z$')
ORDER BY note_id, task_id;

-- 8. Completion values and schedule keys that are not canonical. In
-- particular, timed keys with an offset cannot be converted safely without
-- the timezone used by the client that created the old value.
WITH completion_entries AS (
    SELECT
        n.id AS note_id,
        block->>'id' AS task_id,
        COALESCE(block->'metadata'->>'hasTime', 'false') AS has_time,
        completion.key AS scheduled_at,
        completion.value #>> '{}' AS completed_at,
        jsonb_typeof(completion.value) AS completed_at_type
    FROM notes AS n
    CROSS JOIN LATERAL jsonb_array_elements(
        CASE
            WHEN jsonb_typeof(n.document->'blocks') = 'array'
                THEN n.document->'blocks'
            ELSE '[]'::jsonb
        END
    ) AS block
    CROSS JOIN LATERAL jsonb_each(
        CASE
            WHEN jsonb_typeof(block->'metadata'->'completions') = 'object'
                THEN block->'metadata'->'completions'
            ELSE '{}'::jsonb
        END
    ) AS completion
    WHERE n.deleted_at IS NULL
      AND block->>'type' = 'task'
)
SELECT
    note_id,
    task_id,
    has_time,
    scheduled_at,
    completed_at,
    completed_at_type
FROM completion_entries
WHERE scheduled_at !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}(\d{3})?$'
   OR completed_at_type <> 'string'
   OR completed_at !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}(\d{3})?Z$'
ORDER BY note_id, task_id, scheduled_at;

-- 9. Duplicate all-day identities after removing the time component. This
-- catches two old representations of one calendar day before normalization.
WITH completion_entries AS (
    SELECT
        n.id AS note_id,
        block->>'id' AS task_id,
        COALESCE(block->'metadata'->>'hasTime', 'false') AS has_time,
        completion.key AS scheduled_at
    FROM notes AS n
    CROSS JOIN LATERAL jsonb_array_elements(
        CASE
            WHEN jsonb_typeof(n.document->'blocks') = 'array'
                THEN n.document->'blocks'
            ELSE '[]'::jsonb
        END
    ) AS block
    CROSS JOIN LATERAL jsonb_each(
        CASE
            WHEN jsonb_typeof(block->'metadata'->'completions') = 'object'
                THEN block->'metadata'->'completions'
            ELSE '{}'::jsonb
        END
    ) AS completion
    WHERE n.deleted_at IS NULL
      AND block->>'type' = 'task'
)
SELECT
    note_id,
    task_id,
    LEFT(scheduled_at, 10) AS scheduled_day,
    COUNT(*) AS representation_count,
    ARRAY_AGG(scheduled_at ORDER BY scheduled_at) AS representations
FROM completion_entries
WHERE has_time = 'false'
GROUP BY note_id, task_id, LEFT(scheduled_at, 10)
HAVING COUNT(*) > 1
ORDER BY note_id, task_id, scheduled_day;
