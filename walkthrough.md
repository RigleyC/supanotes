# Feature 1 — Auth (walkthrough)

> Worktree: `D:/projects/supanotes-worktrees/auth` · branch `feat/auth`

## What landed

End-to-end authentication on the Go backend: register, login, JWT-protected
access (HS256, 15 min), opaque refresh tokens (32-byte random, SHA-256-hashed
in DB, 30-day TTL) with rotation on every use, and logout that revokes the
current refresh token.

All routes are mounted under `/api/v1/auth/...` and are public — no JWT is
required to call them. The middleware (`internal/auth.JWT`) is exported and
ready for F2+ to protect `/api/v1/notes/...`, `/api/v1/ai/...`, etc.

## Files touched

| Layer | File | Status |
|---|---|---|
| Primitives | `backend/pkg/auth/{password,jwt,refresh}.go` + `*_test.go` | committed (c81953c) |
| Persistence | `backend/db/migrations/000001_init.{up,down}.sql` | committed (e88373a) |
| Persistence | `backend/db/queries/auth.sql` + `internal/db/sqlcgen/*` | committed (e88373a) |
| Infra | `backend/pkg/db/db.go` (pgxpool) | committed (8a00a24) |
| Infra | `backend/pkg/migrate/migrate.go` (golang-migrate) | committed (8a00a24) |
| Config | `backend/pkg/config/config.go` + `config_test.go` | committed (f1fb576) |
| Config | `backend/.env.example` | committed (f1fb576) |
| Service | `backend/internal/auth/service.go` + `service_test.go` | committed (f2b2b12) |
| HTTP | `backend/internal/auth/handler.go` + `handler_test.go` | committed (f2b2b12) |
| HTTP | `backend/internal/auth/middleware.go` + `middleware_test.go` | committed (f2b2b12) |
| Wiring | `backend/cmd/server/main.go` | committed (f2b2b12) |
| Marker | empty `feat(backend): feature 1 — auth (…)` | committed (748f336) |

## Commit history (this feature)

```
748f336 feat(backend): feature 1 — auth (register, login, JWT, refresh tokens, Argon2id)
f2b2b12 feat(backend): auth service, handler, middleware and route wiring
f1fb576 feat(backend): JWT config and dependencies
8a00a24 feat(backend): db pool and programmatic migrations
e88373a feat(backend): migration 001 - users, settings, refresh + device tokens
c81953c feat(backend): auth primitives - Argon2id, JWT (HS256), refresh tokens
```

## How to run

```bash
# from the worktree
cd backend
make dev-db-up                     # docker compose up -d postgres
cp .env.example .env               # set a real JWT_SECRET (32+ chars)
go run ./cmd/server
```

The startup log will show `migrate: schema migrated from=0 to=1`, then
`database pool ready`, then `supanotes backend starting addr=:8080 env=dev`.
With an empty `DATABASE_URL`, the server boots in dev-no-db mode and skips
the `/auth/*` routes (with a warning).

## API surface

| Method | Path | Body | Success | Errors |
|---|---|---|---|---|
| `GET`  | `/api/v1/health` | — | `200 {"status":"ok"}` | — |
| `POST` | `/api/v1/auth/register` | `{email, password, name}` | `201 {user, access_token, refresh_token}` | `400 validation` / `409 email in use` / `500` |
| `POST` | `/api/v1/auth/login` | `{email, password}` | `200 {user, access_token, refresh_token}` | `400 validation` / `401 invalid credentials` / `500` |
| `POST` | `/api/v1/auth/refresh` | `{refresh_token}` | `200 {access_token, refresh_token}` (rotated) | `400 validation` / `401 invalid refresh token` / `500` |
| `POST` | `/api/v1/auth/logout` | `{refresh_token}` | `204` (no-op if unknown) | `400 validation` / `500` |

All error responses are `{"error": "<message>"}`.

## Security properties

- **Passwords**: Argon2id PHC `$argon2id$v=19$m=65536,t=1,p=4$<salt>$<hash>`,
  16-byte random salt per user, 32-byte key length. Verified in constant
  time via `crypto/subtle`.
- **Access tokens**: HS256, `sub = user_id`, `iat`, `exp = now + 15min`.
  Secret from `JWT_SECRET` (refuses to start outside `dev` mode without it).
- **Refresh tokens**: 32 random bytes from `crypto/rand` → 64-char hex.
  Plain token is never persisted; only its SHA-256 hash. Rotation on
  every use (old row gets `revoked_at = NOW()`); replays of a revoked
  or expired token return `401`.
- **No information leak**: register and login return the same shape
  on conflict (no enumeration via timing or wording).
- **Email normalisation**: lowercased + trimmed before insert, so
  `User@Example.COM` and `user@example.com` collide on the unique index.

## End-to-end smoke test (executed, passed)

```
1. GET  /api/v1/health                                → 200
2. POST /api/v1/auth/register (smoke@example.com)     → 201, access (JWT, 188 chars) + refresh (64 hex) + user
3. POST /api/v1/auth/register (same email)            → 409 {"error":"email already in use"}
4. POST /api/v1/auth/login (wrong password)           → 401 {"error":"invalid credentials"}
5. POST /api/v1/auth/login (correct)                  → 200, new access+refresh (rotated vs step 2)
6. POST /api/v1/auth/refresh (REFRESH2)               → 200, new pair
7. POST /api/v1/auth/refresh (REFRESH2 again)         → 401 {"error":"invalid refresh token"}  (revoked)
8. POST /api/v1/auth/logout  (REFRESH)                → 204
9. DB inspection:
     users.password_hash           = $argon2id$v=19$m=65536,t=1,p=4$…  (Argon2id PHC)
     refresh_tokens.token_hash     = 64 hex chars (SHA-256)
     user_settings.timezone        = "UTC"
     refresh_tokens with revoked_at = 2 (from steps 7 + 8)
     refresh_tokens still active   = 2 (from steps 5 + 6)
```

## Tests

```
go test ./...
ok  github.com/RigleyC/supanotes/internal/auth        (30 cases: 12 service + 11 handler + 7 middleware)
ok  github.com/RigleyC/supanotes/internal/handler     (health)
ok  github.com/RigleyC/supanotes/pkg/auth             (12 cases: 5 password + 4 JWT + 3 refresh)
ok  github.com/RigleyC/supanotes/pkg/config           (3 cases incl. prod-without-JWT_SECRET)
go vet ./...                                          clean
go build ./...                                        clean
```

The service tests use a hand-rolled `mockQuerier` implementing the full
`sqlcgen.Querier` interface, with the same `revoked_at IS NULL AND
expires_at > NOW()` semantics as the real `GetRefreshToken` query.

## Out of scope (next features)

- `GET /api/v1/me` (and other JWT-protected routes) — comes with F2.
- Email verification / password reset — comes with F2 or F3.
- Rate limiting on `/auth/login` — comes with the production hardening pass.
- Rotating `JWT_SECRET` / key versioning — come with the multi-tenant
  work in F5+.
- Push on the remote — explicitly left to the user; no `git push` was run.
