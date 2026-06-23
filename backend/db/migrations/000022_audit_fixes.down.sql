ALTER TABLE contexts DROP COLUMN IF EXISTS deleted_at;

ALTER TABLE note_links DROP CONSTRAINT IF EXISTS note_links_source_id_target_id_key;

CREATE INDEX IF NOT EXISTS notes_active_idx ON notes (user_id, updated_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS tasks_user_due_idx ON tasks (user_id, due_date) WHERE status = 'open' AND deleted_at IS NULL AND due_date IS NOT NULL;
