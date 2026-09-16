-- name: InsertAlexaRequestIdempotency :one
INSERT INTO alexa_request_idempotency
    (application_id, request_id, fingerprint, status, owner_token, lease_until)
VALUES ($1, $2, $3, 'pending', $4, $5)
ON CONFLICT (application_id, request_id) DO NOTHING
RETURNING application_id, request_id, fingerprint, status, response_json,
          owner_token, lease_until, expires_at, created_at, updated_at;

-- name: GetAlexaRequestIdempotencyForUpdate :one
SELECT application_id, request_id, fingerprint, status, response_json,
       owner_token, lease_until, expires_at, created_at, updated_at
FROM alexa_request_idempotency
WHERE application_id = $1 AND request_id = $2
FOR UPDATE;

-- name: TakeOverAlexaRequestIdempotency :one
UPDATE alexa_request_idempotency
SET owner_token = $3,
    lease_until = $4,
    updated_at = NOW()
WHERE application_id = $1
  AND request_id = $2
  AND status = 'pending'
  AND lease_until <= NOW()
RETURNING application_id, request_id, fingerprint, status, response_json,
          owner_token, lease_until, expires_at, created_at, updated_at;

-- name: ReuseExpiredAlexaRequestIdempotency :one
UPDATE alexa_request_idempotency
SET fingerprint = $3,
    status = 'pending',
    response_json = NULL,
    owner_token = $4,
    lease_until = $5,
    expires_at = NULL,
    updated_at = NOW()
WHERE application_id = $1
  AND request_id = $2
  AND status = 'completed'
  AND expires_at <= NOW()
RETURNING application_id, request_id, fingerprint, status, response_json,
          owner_token, lease_until, expires_at, created_at, updated_at;

-- name: CompleteAlexaRequestIdempotency :execrows
UPDATE alexa_request_idempotency
SET status = 'completed',
    response_json = $4,
    expires_at = $5,
    updated_at = NOW()
WHERE application_id = $1
  AND request_id = $2
  AND owner_token = $3
  AND status = 'pending';

-- name: DeleteExpiredAlexaRequestIdempotency :exec
DELETE FROM alexa_request_idempotency
WHERE status = 'completed' AND expires_at <= NOW();
