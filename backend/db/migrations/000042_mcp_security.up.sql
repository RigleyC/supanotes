CREATE TABLE mcp_audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    token_id UUID REFERENCES mcp_tokens(id) ON DELETE SET NULL,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    agent TEXT NOT NULL,
    tool_name TEXT NOT NULL,
    resource TEXT NOT NULL DEFAULT '',
    result TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_mcp_audit_log_user_created_at
    ON mcp_audit_log(user_id, created_at DESC);

CREATE TABLE mcp_confirmations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tool_name TEXT NOT NULL,
    resource TEXT NOT NULL DEFAULT '',
    arguments JSONB NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_mcp_confirmations_user_active
    ON mcp_confirmations(user_id, expires_at)
    WHERE consumed_at IS NULL;
