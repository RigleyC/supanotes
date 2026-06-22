BEGIN;

ALTER TABLE notes
ADD COLUMN favorite BOOLEAN NOT NULL DEFAULT FALSE,
ADD COLUMN archived BOOLEAN NOT NULL DEFAULT FALSE;

-- Restore data from user_note_preferences back to notes for the note owner
UPDATE notes n
SET favorite = COALESCE((SELECT favorite FROM user_note_preferences WHERE note_id = n.id AND user_id = n.user_id), FALSE),
    archived = COALESCE((SELECT archived FROM user_note_preferences WHERE note_id = n.id AND user_id = n.user_id), FALSE);

ALTER TABLE user_note_preferences DROP COLUMN IF EXISTS favorite;
ALTER TABLE user_note_preferences DROP COLUMN IF EXISTS archived;

COMMIT;
