-- Re-add is_inbox column
ALTER TABLE notes ADD COLUMN is_inbox BOOLEAN NOT NULL DEFAULT false;

-- Re-create unique single inbox index
CREATE UNIQUE INDEX idx_notes_single_inbox ON notes (user_id) WHERE is_inbox = true AND deleted_at IS NULL;

-- Re-add constraint
ALTER TABLE notes ADD CONSTRAINT chk_inbox_not_archived CHECK (is_inbox = false OR archived = false);
