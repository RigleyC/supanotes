BEGIN;

DROP TRIGGER IF EXISTS update_note_links_updated_at ON note_links;

ALTER TABLE note_links
  DROP COLUMN IF EXISTS created_at,
  DROP COLUMN IF EXISTS updated_at;

COMMIT;
