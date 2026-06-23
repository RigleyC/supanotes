-- Fix contexts missing deleted_at for HardDeleteExpiredContexts
ALTER TABLE contexts ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

-- Fix note_links missing unique constraint, which implicitly creates an index
ALTER TABLE note_links ADD CONSTRAINT note_links_source_id_target_id_key UNIQUE (source_id, target_id);

-- Drop redundant indexes
DROP INDEX IF EXISTS notes_active_idx;
DROP INDEX IF EXISTS tasks_user_due_idx;
