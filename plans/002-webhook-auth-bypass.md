# Plan 002: Enforce webhook auth unconditionally

> **Executor instructions**: Follow this plan step by step.
> **Drift check**: `git diff --stat HEAD -- backend/internal/gateway/handler.go`

## Status
- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: security

## Why this matters
The Telegram webhook bypasses security if the `TelegramWebhookSecret` environment variable is not configured. This means a misconfigured server exposes a public endpoint where attackers can spoof Telegram requests and extract user agent data.

## Current state
`backend/internal/gateway/handler.go:151`
```go
	if h.webhookSecret != "" {
		if c.Request().Header.Get("X-Telegram-Bot-Api-Secret-Token") != h.webhookSecret {
			return c.NoContent(http.StatusUnauthorized)
		}
	}
```

## Scope
**In scope**: `backend/internal/gateway/handler.go`

## Steps

### Step 1: Remove the empty string bypass
Remove the `if h.webhookSecret != ""` wrapper so the check always applies.
If the secret is empty, it will fail to match incoming requests.

```go
	if c.Request().Header.Get("X-Telegram-Bot-Api-Secret-Token") != h.webhookSecret {
		return c.NoContent(http.StatusUnauthorized)
	}
```

**Verify**: Run `cd backend && go test ./internal/gateway/...` -> compiles.

## Done criteria
- [ ] Empty secret bypass removed.
- [ ] `plans/README.md` updated.
