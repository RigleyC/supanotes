-- Normalize task status: completed → done
UPDATE tasks SET status = 'done' WHERE status = 'completed';

-- Add missing columns to routines
ALTER TABLE routines
  ADD COLUMN IF NOT EXISTS name TEXT,
  ADD COLUMN IF NOT EXISTS last_run_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS brief_type TEXT CHECK (brief_type IN ('daily', 'weekly'));

-- Backfill name and brief_type from type
UPDATE routines SET name = 'Daily Brief', brief_type = 'daily' WHERE type = 'daily' AND name IS NULL;
UPDATE routines SET name = 'Weekly Brief', brief_type = 'weekly' WHERE type = 'weekly' AND name IS NULL;

-- Make NOT NULL after backfill
ALTER TABLE routines
  ALTER COLUMN name SET NOT NULL,
  ALTER COLUMN brief_type SET NOT NULL;

-- Add triggers for routines updated_at
CREATE TRIGGER update_routines_updated_at
    BEFORE UPDATE ON routines
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
