CREATE TABLE note_yjs_states (
    note_id UUID PRIMARY KEY REFERENCES notes(id) ON DELETE CASCADE,
    state BYTEA NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE note_yjs_updates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    note_id UUID NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
    update_data BYTEA NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for compaction lookup and room initialization
CREATE INDEX idx_note_yjs_updates_note_created ON note_yjs_updates(note_id, created_at ASC);

CREATE TABLE note_ws_leases (
    note_id UUID PRIMARY KEY REFERENCES notes(id) ON DELETE CASCADE,
    machine_id VARCHAR(100) NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL
);
