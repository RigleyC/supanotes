BEGIN;

ALTER TABLE user_note_preferences
ADD COLUMN favorite BOOLEAN NOT NULL DEFAULT FALSE,
ADD COLUMN archived BOOLEAN NOT NULL DEFAULT FALSE;

-- Seed existing favorites and archived records from notes into user_note_preferences
INSERT INTO user_note_preferences (user_id, note_id, favorite, archived)
SELECT user_id, id, favorite, archived FROM notes
ON CONFLICT (user_id, note_id) DO UPDATE
SET favorite = EXCLUDED.favorite,
    archived = EXCLUDED.archived;

ALTER TABLE notes DROP COLUMN IF EXISTS favorite;
ALTER TABLE notes DROP COLUMN IF EXISTS archived;

COMMIT;
