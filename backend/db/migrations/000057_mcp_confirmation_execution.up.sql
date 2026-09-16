ALTER TABLE mcp_confirmations
    ADD COLUMN execution_status TEXT NOT NULL DEFAULT 'available',
    ADD COLUMN result JSONB,
    ADD COLUMN execution_owner_token TEXT,
    ADD COLUMN execution_lease_until TIMESTAMPTZ;

UPDATE mcp_confirmations
SET execution_status = CASE
        WHEN consumed_at IS NOT NULL THEN 'committed'
        WHEN reserved_at IS NOT NULL THEN 'pending'
        ELSE 'available'
    END,
    execution_owner_token = CASE
        WHEN consumed_at IS NULL AND reserved_at IS NOT NULL
            THEN 'legacy:' || id::TEXT
        ELSE NULL
    END,
    execution_lease_until = CASE
        WHEN consumed_at IS NULL AND reserved_at IS NOT NULL THEN reserved_at
        ELSE NULL
    END;

ALTER TABLE mcp_confirmations
    ADD CONSTRAINT mcp_confirmations_execution_status_check
    CHECK (execution_status IN ('available', 'pending', 'committed'));

CREATE INDEX idx_mcp_confirmations_pending
    ON mcp_confirmations(user_id, execution_lease_until)
    WHERE execution_status = 'pending';
