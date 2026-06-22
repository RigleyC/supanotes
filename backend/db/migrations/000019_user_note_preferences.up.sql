BEGIN;

CREATE TABLE IF NOT EXISTS user_note_preferences (
    user_id          UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    note_id          UUID NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
    hide_completed   BOOLEAN NOT NULL DEFAULT FALSE,
    filters          JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, note_id)
);

CREATE INDEX IF NOT EXISTS idx_user_note_prefs_user_id ON user_note_preferences(user_id);

-- Seed existing hide_completed values into per-user preferences
INSERT INTO user_note_preferences (user_id, note_id, hide_completed, created_at, updated_at)
SELECT user_id, id, hide_completed, created_at, updated_at FROM notes
WHERE deleted_at IS NULL
ON CONFLICT (user_id, note_id) DO NOTHING;

COMMIT;
