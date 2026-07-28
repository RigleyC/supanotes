CREATE TABLE alexa_authorization_codes (
    code_hash text PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    client_id text NOT NULL,
    redirect_uri text NOT NULL,
    expires_at timestamptz NOT NULL,
    refresh_token_hash text,
    refresh_expires_at timestamptz,
    used_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX alexa_authorization_codes_expiry_idx ON alexa_authorization_codes (expires_at);
