# Plan 016: Implement Telegram simulated streaming

> **Executor instructions**: Follow this plan step by step.
> **Drift check**: `git diff --stat HEAD -- backend/internal/gateway/handler.go`

## Status
- **Priority**: P2
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none
- **Category**: direction

## Why this matters
Telegram bot UX feels broken because the bot waits for the full agent response instead of streaming it progressively every 600ms, which was planned in the roadmap.

## Scope
**In scope**: `backend/internal/gateway/handler.go`, `backend/internal/agent/loop.go`

## Steps

### Step 1: Change AgentBridge to return channel
Modify `AgentBridge` to return `(<-chan string, error)` instead of `(string, error)`.

### Step 2: Implement Ticker in Gateway
In `handler.go`, read from the channel. Keep a buffer. Every 600ms, if the buffer has changed, call `h.bot.EditMessageText`. 

## Done criteria
- [ ] Telegram gateway streams partial responses.
- [ ] `plans/README.md` updated.
