ALTER TABLE task_completions
    ADD COLUMN scheduled_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- Backfill: existing completions use completed_at as their scheduled occurrence
UPDATE task_completions SET scheduled_at = completed_at;

-- Legacy rows did not carry an occurrence key. Preserve every completion
-- while making coincident completion timestamps distinct for the new key.
WITH duplicates AS (
    SELECT
        id,
        ROW_NUMBER() OVER (
            PARTITION BY task_id, scheduled_at
            ORDER BY id
        ) - 1 AS offset_microseconds
    FROM task_completions
)
UPDATE task_completions AS completions
SET scheduled_at = completions.scheduled_at +
    (duplicates.offset_microseconds * INTERVAL '1 microsecond')
FROM duplicates
WHERE completions.id = duplicates.id
  AND duplicates.offset_microseconds > 0;

-- Add unique constraint on (task_id, scheduled_at) for idempotent upserts
DROP INDEX IF EXISTS idx_task_completions_task_id;
CREATE UNIQUE INDEX IF NOT EXISTS idx_task_completions_task_scheduled
    ON task_completions(task_id, scheduled_at);
