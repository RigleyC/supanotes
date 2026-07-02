BEGIN;
ALTER TABLE user_settings ADD COLUMN preferences JSONB NOT NULL DEFAULT '{}'::jsonb;
COMMIT;
