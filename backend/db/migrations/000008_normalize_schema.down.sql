-- Revert: remove trigger and columns
DROP TRIGGER IF EXISTS update_routines_updated_at ON routines;
ALTER TABLE routines
  DROP COLUMN IF EXISTS brief_type,
  DROP COLUMN IF EXISTS last_run_at,
  DROP COLUMN IF EXISTS name;
-- Revert status change (approximate — notes that were already 'done' before migration stay 'done')
UPDATE tasks SET status = 'completed' WHERE status = 'done';
