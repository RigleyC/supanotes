BEGIN;

ALTER TABLE user_note_preferences
ADD COLUMN collapse_images BOOLEAN NOT NULL DEFAULT FALSE;

-- Seed existing collapse_images from notes into the owner's preference row
INSERT INTO user_note_preferences (user_id, note_id, collapse_images)
SELECT user_id, id, collapse_images FROM notes
WHERE deleted_at IS NULL
ON CONFLICT (user_id, note_id) DO UPDATE
SET collapse_images = EXCLUDED.collapse_images;

ALTER TABLE notes DROP COLUMN IF EXISTS collapse_images;

COMMIT;