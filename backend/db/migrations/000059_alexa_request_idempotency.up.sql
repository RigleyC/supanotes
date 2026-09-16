CREATE TABLE alexa_request_idempotency (
    application_id TEXT NOT NULL,
    request_id TEXT NOT NULL,
    fingerprint TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('pending', 'completed')),
    response_json JSONB,
    owner_token TEXT NOT NULL,
    lease_until TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (application_id, request_id),
    CHECK (
        (status = 'pending' AND response_json IS NULL AND expires_at IS NULL)
        OR (status = 'completed' AND response_json IS NOT NULL AND expires_at IS NOT NULL)
    )
);

CREATE INDEX alexa_request_idempotency_completed_expiry_idx
    ON alexa_request_idempotency (expires_at)
    WHERE status = 'completed';
