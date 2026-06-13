# Plan 001: Securing Telegram Webhook

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat ff944a4..HEAD -- backend/pkg/config/config.go backend/internal/gateway/handler.go backend/cmd/server/main.go`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: security
- **Planned at**: commit `ff944a4`, 2026-06-13

## Why this matters

The Telegram webhook endpoint `/api/v1/gateway/telegram/webhook` is unauthenticated. Anyone can send a POST request with a custom JSON payload and spoof a linked user's Telegram ID to perform actions via the AI agent loop (e.g. creating/deleting notes, executing agent tools). Securing the webhook with a shared secret token prevents spoofing and unauthorized database/agent mutations.

## Current state

- `backend/pkg/config/config.go` — parses configuration variables from `.env`
- `backend/internal/gateway/handler.go` — defines `Webhook` handler that decodes update messages
- `backend/cmd/server/main.go` — wires up the Echo server routes and initializes handlers

Excerpts:
In `backend/internal/gateway/handler.go` line 147:
```go
func (h *Handler) Webhook(c echo.Context) error {
	var update WebhookUpdate
	if err := c.Bind(&update); err != nil {
		return web.JSONError(c, http.StatusBadRequest, "invalid update")
	}
```

In `backend/cmd/server/main.go` line 292:
```go
	gatewayH := gateway.NewHandler(gatewayRepo, gatewayBot, agentLoop)
	gateway.RegisterRoutes(protected, gatewayH)
	api.POST("/gateway/telegram/webhook", gatewayH.Webhook)
```

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build   | `go build ./cmd/server` | exit 0              |
| Lint    | `go vet ./...`          | exit 0              |
| Tests   | `go test ./internal/gateway/...` | all pass   |

## Scope

**In scope**:
- `backend/pkg/config/config.go`
- `backend/internal/gateway/handler.go`
- `backend/cmd/server/main.go`
- `backend/.env.example`

**Out of scope**:
- Direct network calls to Telegram API
- Changes to other endpoints

## Git workflow

- Branch: `feat/secure-telegram-webhook`
- Commit format: `sec(gateway): secure telegram webhook`

## Steps

### Step 1: Add config variable
Add `TelegramWebhookSecret` to the `Config` struct and load it from env `TELEGRAM_WEBHOOK_SECRET`.
In `backend/pkg/config/config.go`:
```diff
 type Config struct {
 	Port                   string
 	DatabaseURL            string
 	JWTSecret              string
+	TelegramWebhookSecret  string
```
And populate it in `Load()`:
```diff
 		FCMCredentialsFile:     os.Getenv("FCM_CREDENTIALS_FILE"),
+		TelegramWebhookSecret:  os.Getenv("TELEGRAM_WEBHOOK_SECRET"),
```
Update `backend/.env.example` to document `TELEGRAM_WEBHOOK_SECRET`.

**Verify**: `go build ./cmd/server` exits 0.

### Step 2: Update gateway handler to verify header token
Update the `Handler` struct in `backend/internal/gateway/handler.go` to store `webhookSecret string`.
Update `NewHandler` constructor signature:
```go
func NewHandler(repo *Repository, bot *TelegramClient, agent AgentBridge, webhookSecret string) *Handler {
```
In `Webhook(c echo.Context)` handler, check the `X-Telegram-Bot-Api-Secret-Token` header if `webhookSecret` is configured:
```go
	if h.webhookSecret != "" {
		token := c.Request().Header.Get("X-Telegram-Bot-Api-Secret-Token")
		if token != h.webhookSecret {
			log.Warn().Msg("unauthorized webhook request: secret token mismatch")
			return c.NoContent(http.StatusUnauthorized)
		}
	}
```

**Verify**: `go build ./cmd/server` exits 0.

### Step 3: Update main.go initialization
In `backend/cmd/server/main.go`, pass `cfg.TelegramWebhookSecret` to `gateway.NewHandler`:
```go
	gatewayH := gateway.NewHandler(gatewayRepo, gatewayBot, agentLoop, cfg.TelegramWebhookSecret)
```

**Verify**: Run `go build ./cmd/server` and `go test ./...` in the backend. All tests must pass.

## Test plan

- Update any mock/test calls in `backend/internal/gateway/handler_test.go` or related tests where `NewHandler` is called.
- Add a unit test in `handler_test.go` verifying that when a secret is configured:
  1. Requests without the header are rejected with `401 Unauthorized`.
  2. Requests with a mismatched header token are rejected with `401 Unauthorized`.
  3. Requests with the correct header token are allowed to pass.
- Verification: `go test ./internal/gateway/...` exits 0.

## Done criteria

- [ ] `go build ./cmd/server` exits 0
- [ ] `go test ./internal/gateway/...` exits 0
- [ ] `git diff` shows modifications only in the scoped files

## STOP conditions

- If files changed since commit `ff944a4` mismatch the code excerpts, stop and report.
- If existing tests fail due to compilation errors that are unrelated to the constructor signature change.

## Maintenance notes

- Webhook secret tokens are configured in the target environment (e.g. Fly.io secret variables) and registered at the Telegram bot setup phase.
