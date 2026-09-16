DROP INDEX IF EXISTS idx_mcp_confirmations_pending;

ALTER TABLE mcp_confirmations
    DROP CONSTRAINT IF EXISTS mcp_confirmations_execution_status_check,
    DROP COLUMN IF EXISTS execution_lease_until,
    DROP COLUMN IF EXISTS execution_owner_token,
    DROP COLUMN IF EXISTS result,
    DROP COLUMN IF EXISTS execution_status;
