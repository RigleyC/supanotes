CREATE TABLE IF NOT EXISTS agent_working_memory (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    session_id UUID NOT NULL,
    key VARCHAR(255) NOT NULL,
    value TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, session_id, key)
);

ALTER TABLE souls ADD COLUMN profile JSONB NOT NULL DEFAULT '{}'::jsonb;
