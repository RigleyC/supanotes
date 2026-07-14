CREATE TABLE note_nodes (
    id UUID PRIMARY KEY,
    note_id UUID NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
    parent_id UUID REFERENCES note_nodes(id) ON DELETE CASCADE,
    position VARCHAR(255) NOT NULL DEFAULT 'a0',
    type TEXT NOT NULL,
    data JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX idx_note_nodes_note_id ON note_nodes(note_id);
