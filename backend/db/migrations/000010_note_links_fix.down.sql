DROP INDEX IF EXISTS idx_note_links_target;

ALTER TABLE note_links DROP COLUMN IF EXISTS relation;

ALTER TABLE notes DROP CONSTRAINT IF EXISTS chk_inbox_not_archived;

DROP TRIGGER IF EXISTS trg_notes_excerpt_update ON notes;
DROP FUNCTION IF EXISTS notes_excerpt_update();

-- Restore old excerpt function and trigger (140 char, no markdown stripping)
CREATE OR REPLACE FUNCTION generate_note_excerpt() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.excerpt IS NULL OR NEW.excerpt = '' THEN
        NEW.excerpt := substring(NEW.content from 1 for 140);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_generate_note_excerpt
  BEFORE INSERT OR UPDATE OF content ON notes
  FOR EACH ROW
  EXECUTE FUNCTION generate_note_excerpt();
