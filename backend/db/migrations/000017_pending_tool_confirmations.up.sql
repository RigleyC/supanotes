CREATE TABLE IF NOT EXISTS pending_tool_confirmations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    session_id UUID NOT NULL,
    tool_name TEXT NOT NULL,
    args_json JSONB NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('pending', 'approved', 'cancelled', 'expired')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_pending_tool_confirmations_user_session
    ON pending_tool_confirmations(user_id, session_id);

CREATE INDEX IF NOT EXISTS idx_pending_tool_confirmations_pending
    ON pending_tool_confirmations(user_id, status)
    WHERE status = 'pending';
