CREATE TABLE shared_link_ingestions (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    share_id UUID NOT NULL,
    note_id UUID NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
    operation_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, share_id)
);

CREATE INDEX shared_link_ingestions_note_id_idx
    ON shared_link_ingestions (note_id);
