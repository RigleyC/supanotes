ALTER TABLE refresh_tokens
    ADD COLUMN family_id UUID NOT NULL DEFAULT gen_random_uuid(),
    ADD COLUMN parent_id UUID REFERENCES refresh_tokens(id) ON DELETE SET NULL,
    ADD COLUMN consumed_at TIMESTAMPTZ,
    ADD COLUMN reuse_detected_at TIMESTAMPTZ;

CREATE INDEX idx_refresh_tokens_family_id ON refresh_tokens(family_id);
