ALTER TABLE notes
    ADD COLUMN revision BIGINT NOT NULL DEFAULT 0,
    ADD COLUMN document JSONB NOT NULL DEFAULT '{"schemaVersion":1,"blocks":[]}'::jsonb,
    ADD COLUMN snapshot_revision BIGINT NOT NULL DEFAULT 0;

CREATE TABLE note_operations (
    note_id UUID NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
    revision BIGINT NOT NULL,
    operation_id UUID NOT NULL,
    actor_id UUID NOT NULL REFERENCES users(id),
    base_revision BIGINT NOT NULL,
    kind TEXT NOT NULL,
    block_id TEXT,
    payload JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (note_id, revision),
    UNIQUE (note_id, operation_id),
    CHECK (revision > 0),
    CHECK (base_revision >= 0)
);

CREATE INDEX idx_note_operations_since_revision
    ON note_operations(note_id, revision);
