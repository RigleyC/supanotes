BEGIN;

ALTER TABLE notes ADD COLUMN collapse_images BOOLEAN NOT NULL DEFAULT FALSE;

-- Restore the owner's last collapse setting onto the note
UPDATE notes n
SET collapse_images = unp.collapse_images
FROM user_note_preferences unp
WHERE unp.note_id = n.id AND unp.user_id = n.user_id;

ALTER TABLE user_note_preferences DROP COLUMN IF EXISTS collapse_images;

COMMIT;