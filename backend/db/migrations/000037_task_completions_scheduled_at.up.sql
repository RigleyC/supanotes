ALTER TABLE task_completions
    ADD COLUMN scheduled_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- Backfill: existing completions use completed_at as their scheduled occurrence
UPDATE task_completions SET scheduled_at = completed_at;

-- Add unique constraint on (task_id, scheduled_at) for idempotent upserts
DROP INDEX IF EXISTS idx_task_completions_task_id;
CREATE UNIQUE INDEX IF NOT EXISTS idx_task_completions_task_scheduled
    ON task_completions(task_id, scheduled_at);
