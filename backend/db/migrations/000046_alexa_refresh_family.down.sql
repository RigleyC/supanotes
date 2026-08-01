ALTER TABLE alexa_authorization_codes
    DROP COLUMN IF EXISTS previous_refresh_token_hash,
    DROP COLUMN IF EXISTS refresh_revoked_at;
