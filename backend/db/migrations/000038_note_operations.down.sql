DROP TABLE IF EXISTS note_operations;

ALTER TABLE notes
    DROP COLUMN IF EXISTS snapshot_revision,
    DROP COLUMN IF EXISTS document,
    DROP COLUMN IF EXISTS revision;
