-- Remove constraint
ALTER TABLE notes DROP CONSTRAINT IF EXISTS chk_inbox_not_archived;

-- Delete all inbox notes and cascade tasks/nodes
DELETE FROM notes WHERE is_inbox = true;

-- Drop single inbox index
DROP INDEX IF EXISTS idx_notes_single_inbox;

-- Drop is_inbox column
ALTER TABLE notes DROP COLUMN IF EXISTS is_inbox;
