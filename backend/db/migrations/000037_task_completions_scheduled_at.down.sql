DROP INDEX IF EXISTS idx_task_completions_task_scheduled;
CREATE INDEX IF NOT EXISTS idx_task_completions_task_id ON task_completions(task_id);
ALTER TABLE task_completions DROP COLUMN IF EXISTS scheduled_at;
