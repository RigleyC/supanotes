-- Drop old excerpt trigger and function
DROP TRIGGER IF EXISTS trg_generate_note_excerpt ON notes;
DROP FUNCTION IF EXISTS generate_note_excerpt();

-- Replace notes_excerpt_update with fixed regex
CREATE OR REPLACE FUNCTION notes_excerpt_update() RETURNS trigger AS $$
BEGIN
  NEW.excerpt := substring(
    regexp_replace(NEW.content, '[#*_>`\[\]]+', '', 'g')
    FROM 1 FOR 200
  );
  RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_notes_excerpt_update
  BEFORE INSERT OR UPDATE OF content ON notes
  FOR EACH ROW
  EXECUTE FUNCTION notes_excerpt_update();

-- Constraint: inbox notes cannot be archived
ALTER TABLE notes
  ADD CONSTRAINT chk_inbox_not_archived
  CHECK (is_inbox = false OR archived = false);

-- Add relation column to note_links (was missing)
ALTER TABLE note_links
  ADD COLUMN relation TEXT NOT NULL DEFAULT 'related'
  CHECK (relation IN ('related', 'part_of', 'references'));

CREATE INDEX IF NOT EXISTS idx_note_links_target ON note_links (target_id);
