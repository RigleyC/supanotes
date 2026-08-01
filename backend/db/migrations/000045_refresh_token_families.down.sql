DROP INDEX IF EXISTS idx_refresh_tokens_family_id;

ALTER TABLE refresh_tokens
    DROP COLUMN IF EXISTS reuse_detected_at,
    DROP COLUMN IF EXISTS consumed_at,
    DROP COLUMN IF EXISTS parent_id,
    DROP COLUMN IF EXISTS family_id;
