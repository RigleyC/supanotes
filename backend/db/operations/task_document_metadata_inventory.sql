-- Read-only aggregate inventory for the task document cutover.
-- It does not expose note text, user data, or task titles.

BEGIN;
SET TRANSACTION READ ONLY;

WITH task_blocks AS (
    SELECT
        n.id AS note_id,
        block
    FROM notes AS n
    CROSS JOIN LATERAL jsonb_array_elements(
        CASE
            WHEN jsonb_typeof(n.document -> 'blocks') = 'array'
                THEN n.document -> 'blocks'
            ELSE '[]'::jsonb
        END
    ) AS blocks(block)
    WHERE block ->> 'type' = 'task'
),
task_metadata AS (
    SELECT
        note_id,
        block,
        CASE
            WHEN jsonb_typeof(block -> 'metadata') = 'object'
                THEN block -> 'metadata'
            ELSE '{}'::jsonb
        END AS metadata
    FROM task_blocks
)
SELECT
    'task_blocks' AS metric,
    count(*)::text AS value
FROM task_metadata
UNION ALL
SELECT
    'tasks_with_legacy_recurrence',
    count(*)::text
FROM task_metadata
WHERE metadata ? 'recurrence'
UNION ALL
SELECT
    'tasks_with_legacy_checked',
    count(*)::text
FROM task_metadata
WHERE metadata ? 'checked'
UNION ALL
SELECT
    'tasks_with_completions',
    count(*)::text
FROM task_metadata
WHERE jsonb_typeof(metadata -> 'completions') = 'object'
UNION ALL
SELECT
    'tasks_with_last_completed_at',
    count(*)::text
FROM task_metadata
WHERE metadata ? 'lastCompletedAt'
ORDER BY metric;

WITH task_metadata AS (
    SELECT
        CASE
            WHEN jsonb_typeof(block -> 'metadata') = 'object'
                THEN block -> 'metadata'
            ELSE '{}'::jsonb
        END AS metadata
    FROM notes AS n
    CROSS JOIN LATERAL jsonb_array_elements(
        CASE
            WHEN jsonb_typeof(n.document -> 'blocks') = 'array'
                THEN n.document -> 'blocks'
            ELSE '[]'::jsonb
        END
    ) AS blocks(block)
    WHERE block ->> 'type' = 'task'
)
SELECT key, count(*)::text AS occurrences
FROM task_metadata
CROSS JOIN LATERAL jsonb_object_keys(metadata) AS keys(key)
GROUP BY key
ORDER BY key;

WITH task_metadata AS (
    SELECT
        CASE
            WHEN jsonb_typeof(block -> 'metadata') = 'object'
                THEN block -> 'metadata'
            ELSE '{}'::jsonb
        END AS metadata
    FROM notes AS n
    CROSS JOIN LATERAL jsonb_array_elements(
        CASE
            WHEN jsonb_typeof(n.document -> 'blocks') = 'array'
                THEN n.document -> 'blocks'
            ELSE '[]'::jsonb
        END
    ) AS blocks(block)
    WHERE block ->> 'type' = 'task'
)
SELECT 'legacy_recurrence_value' AS metric,
       coalesce(metadata ->> 'recurrence', '<null>') AS value,
       count(*)::text AS occurrences
FROM task_metadata
WHERE metadata ? 'recurrence'
GROUP BY value
ORDER BY value;

WITH task_metadata AS (
    SELECT
        CASE
            WHEN jsonb_typeof(block -> 'metadata') = 'object'
                THEN block -> 'metadata'
            ELSE '{}'::jsonb
        END AS metadata
    FROM notes AS n
    CROSS JOIN LATERAL jsonb_array_elements(
        CASE
            WHEN jsonb_typeof(n.document -> 'blocks') = 'array'
                THEN n.document -> 'blocks'
            ELSE '[]'::jsonb
        END
    ) AS blocks(block)
    WHERE block ->> 'type' = 'task'
), completion_entries AS (
    SELECT
        key AS scheduled_at,
        value AS completed_at
    FROM task_metadata
    CROSS JOIN LATERAL jsonb_each_text(
        CASE
            WHEN jsonb_typeof(metadata -> 'completions') = 'object'
                THEN metadata -> 'completions'
            ELSE '{}'::jsonb
        END
    ) AS entries(key, value)
)
SELECT
    'completion_schedule_keys' AS metric,
    count(*)::text AS total,
    count(*) FILTER (WHERE right(scheduled_at, 1) = 'Z')::text AS utc_suffix,
    count(*) FILTER (WHERE scheduled_at ~ '[+-][0-9]{2}:[0-9]{2}$')::text AS offset_suffix,
    count(*) FILTER (
        WHERE right(scheduled_at, 1) <> 'Z'
          AND scheduled_at !~ '[+-][0-9]{2}:[0-9]{2}$'
          AND scheduled_at LIKE '%T%'
    )::text AS wall_clock_shape,
    count(*) FILTER (
        WHERE scheduled_at NOT LIKE '%T%'
    )::text AS invalid_shape
FROM completion_entries
UNION ALL
SELECT
    'completion_values',
    count(*)::text,
    count(*) FILTER (WHERE right(completed_at, 1) = 'Z')::text,
    count(*) FILTER (WHERE completed_at ~ '[+-][0-9]{2}:[0-9]{2}$')::text,
    count(*) FILTER (
        WHERE right(completed_at, 1) <> 'Z'
          AND completed_at !~ '[+-][0-9]{2}:[0-9]{2}$'
          AND completed_at LIKE '%T%'
    )::text,
    count(*) FILTER (WHERE completed_at NOT LIKE '%T%')::text
FROM completion_entries;

WITH task_metadata AS (
    SELECT
        CASE
            WHEN jsonb_typeof(block -> 'metadata') = 'object'
                THEN block -> 'metadata'
            ELSE '{}'::jsonb
        END AS metadata
    FROM notes AS n
    CROSS JOIN LATERAL jsonb_array_elements(
        CASE
            WHEN jsonb_typeof(n.document -> 'blocks') = 'array'
                THEN n.document -> 'blocks'
            ELSE '[]'::jsonb
        END
    ) AS blocks(block)
    WHERE block ->> 'type' = 'task'
), completion_entries AS (
    SELECT
        metadata ->> 'hasTime' AS has_time,
        key AS scheduled_at
    FROM task_metadata
    CROSS JOIN LATERAL jsonb_each_text(
        CASE
            WHEN jsonb_typeof(metadata -> 'completions') = 'object'
                THEN metadata -> 'completions'
            ELSE '{}'::jsonb
        END
    ) AS entries(key, value)
)
SELECT
    'completion_schedule_time' AS metric,
    coalesce(has_time, '<null>') AS has_time,
    substring(scheduled_at from 12 for 8) AS time_component,
    count(*)::text AS occurrences
FROM completion_entries
GROUP BY has_time, time_component
ORDER BY has_time, time_component;

WITH task_metadata AS (
    SELECT
        CASE
            WHEN jsonb_typeof(block -> 'metadata') = 'object'
                THEN block -> 'metadata'
            ELSE '{}'::jsonb
        END AS metadata
    FROM notes AS n
    CROSS JOIN LATERAL jsonb_array_elements(
        CASE
            WHEN jsonb_typeof(n.document -> 'blocks') = 'array'
                THEN n.document -> 'blocks'
            ELSE '[]'::jsonb
        END
    ) AS blocks(block)
    WHERE block ->> 'type' = 'task'
)
SELECT
    'due_date_shape' AS metric,
    count(*) FILTER (WHERE NOT metadata ? 'dueDate')::text AS missing,
    count(*) FILTER (
        WHERE metadata ? 'dueDate'
          AND metadata ->> 'dueDate' ~ '[+-][0-9]{2}:[0-9]{2}$'
    )::text AS offset_suffix,
    count(*) FILTER (
        WHERE metadata ? 'dueDate'
          AND right(metadata ->> 'dueDate', 1) = 'Z'
    )::text AS utc_suffix,
    count(*) FILTER (
        WHERE metadata ? 'dueDate'
          AND right(metadata ->> 'dueDate', 1) <> 'Z'
          AND metadata ->> 'dueDate' !~ '[+-][0-9]{2}:[0-9]{2}$'
          AND metadata ->> 'dueDate' LIKE '%T%'
    )::text AS wall_clock_shape,
    count(*) FILTER (
        WHERE metadata ? 'dueDate'
          AND metadata ->> 'dueDate' NOT LIKE '%T%'
    )::text AS invalid_shape
FROM task_metadata;

WITH task_metadata AS (
    SELECT
        CASE
            WHEN jsonb_typeof(block -> 'metadata') = 'object'
                THEN block -> 'metadata'
            ELSE '{}'::jsonb
        END AS metadata
    FROM notes AS n
    CROSS JOIN LATERAL jsonb_array_elements(
        CASE
            WHEN jsonb_typeof(n.document -> 'blocks') = 'array'
                THEN n.document -> 'blocks'
            ELSE '[]'::jsonb
        END
    ) AS blocks(block)
    WHERE block ->> 'type' = 'task'
)
SELECT
    'last_completed_at_shape' AS metric,
    count(*) FILTER (WHERE NOT metadata ? 'lastCompletedAt')::text AS missing,
    count(*) FILTER (
        WHERE metadata ? 'lastCompletedAt'
          AND right(metadata ->> 'lastCompletedAt', 1) = 'Z'
    )::text AS utc_suffix,
    count(*) FILTER (
        WHERE metadata ? 'lastCompletedAt'
          AND metadata ->> 'lastCompletedAt' ~ '[+-][0-9]{2}:[0-9]{2}$'
    )::text AS offset_suffix,
    count(*) FILTER (
        WHERE metadata ? 'lastCompletedAt'
          AND metadata ->> 'lastCompletedAt' NOT LIKE '%T%'
    )::text AS invalid_shape
FROM task_metadata;

WITH task_metadata AS (
    SELECT
        CASE
            WHEN jsonb_typeof(block -> 'metadata') = 'object'
                THEN block -> 'metadata'
            ELSE '{}'::jsonb
        END AS metadata
    FROM notes AS n
    CROSS JOIN LATERAL jsonb_array_elements(
        CASE
            WHEN jsonb_typeof(n.document -> 'blocks') = 'array'
                THEN n.document -> 'blocks'
            ELSE '[]'::jsonb
        END
    ) AS blocks(block)
    WHERE block ->> 'type' = 'task'
)
SELECT 'recurrence_rule_value' AS metric,
       coalesce(metadata ->> 'recurrenceRule', '<null>') AS value,
       count(*)::text AS occurrences
FROM task_metadata
WHERE metadata ? 'recurrenceRule'
GROUP BY value
ORDER BY value;

WITH task_metadata AS (
    SELECT
        CASE
            WHEN jsonb_typeof(block -> 'metadata') = 'object'
                THEN block -> 'metadata'
            ELSE '{}'::jsonb
        END AS metadata
    FROM notes AS n
    CROSS JOIN LATERAL jsonb_array_elements(
        CASE
            WHEN jsonb_typeof(n.document -> 'blocks') = 'array'
                THEN n.document -> 'blocks'
            ELSE '[]'::jsonb
        END
    ) AS blocks(block)
    WHERE block ->> 'type' = 'task'
)
SELECT 'reminder_value' AS metric,
       coalesce(metadata ->> 'reminder', '<null>') AS value,
       count(*)::text AS occurrences
FROM task_metadata
WHERE metadata ? 'reminder'
GROUP BY value
ORDER BY value;

-- Historical operations are immutable audit/rebase records. They are not
-- replayed as the canonical document; the current document snapshot is the
-- source of truth. Keep this inventory to prove that legacy values remain
-- only in history after the snapshot backfill.
SELECT
    kind,
    count(*)::text AS operations,
    count(*) FILTER (
        WHERE payload::text LIKE '%' || chr(34) || 'recurrence' || chr(34) || ':%'
    )::text AS legacy_recurrence,
    count(*) FILTER (
        WHERE payload::text LIKE '%' || chr(34) || 'checked' || chr(34) || ':%'
    )::text AS legacy_checked,
    count(*) FILTER (
        WHERE payload::text LIKE '%03:00:00.000Z%'
    )::text AS legacy_utc_all_day,
    count(*) FILTER (
        WHERE payload::text LIKE '%' || chr(34) || 'completedAt' || chr(34) || ':%'
    )::text AS completion_operations
FROM note_operations
GROUP BY kind
ORDER BY kind;

COMMIT;
