ALTER TABLE alexa_authorization_codes
    ADD COLUMN previous_refresh_token_hash text,
    ADD COLUMN refresh_revoked_at timestamptz;
