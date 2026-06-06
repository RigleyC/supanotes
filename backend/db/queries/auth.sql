-- name: CreateUser :one
INSERT INTO users (email, password_hash, name)
VALUES ($1, $2, $3)
RETURNING *;

-- name: GetUserByEmail :one
SELECT * FROM users
WHERE email = $1;

-- name: GetUserByID :one
SELECT * FROM users
WHERE id = $1;

-- name: CreateUserSettings :one
INSERT INTO user_settings (user_id, timezone)
VALUES ($1, $2)
RETURNING *;

-- name: GetUserSettings :one
SELECT * FROM user_settings
WHERE user_id = $1;

-- name: UpdateUserSettings :one
UPDATE user_settings
SET timezone = $2,
    updated_at = NOW()
WHERE user_id = $1
RETURNING *;

-- name: CreateRefreshToken :one
INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
VALUES ($1, $2, $3)
RETURNING *;

-- name: GetRefreshToken :one
SELECT * FROM refresh_tokens
WHERE token_hash = $1
  AND revoked_at IS NULL
  AND expires_at > NOW();

-- name: RevokeRefreshToken :exec
UPDATE refresh_tokens
SET revoked_at = NOW()
WHERE id = $1;

-- name: RevokeAllUserRefreshTokens :exec
UPDATE refresh_tokens
SET revoked_at = NOW()
WHERE user_id = $1
  AND revoked_at IS NULL;

-- name: CreateDeviceToken :one
INSERT INTO device_tokens (user_id, token, platform)
VALUES ($1, $2, $3)
ON CONFLICT (user_id, token) DO UPDATE
   SET token = EXCLUDED.token
RETURNING *;

-- name: DeleteDeviceToken :exec
DELETE FROM device_tokens
WHERE id = $1 AND user_id = $2;

-- name: ListDeviceTokensByUser :many
SELECT id, user_id, token, platform, created_at FROM device_tokens
WHERE user_id = $1;
