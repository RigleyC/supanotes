# Plan 005: Sanitize FTS syntax injection

> **Executor instructions**: Follow this plan step by step.
> **Drift check**: `git diff --stat HEAD -- backend/internal/search/service.go`

## Status
- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: security

## Why this matters
Users can crash the full-text search endpoint by including characters like `(`, `|`, `!` in their queries. These are concatenated into PostgreSQL's `to_tsquery`, resulting in 500 errors.

## Current state
`backend/internal/search/service.go:85`

## Scope
**In scope**: `backend/internal/search/service.go`

## Steps

### Step 1: Strip non-alphanumeric chars
In `toPrefixTsQuery`, use a regex or string replacer to remove `(`, `)`, `|`, `&`, `!`, `:` before splitting into words.

```go
var re = regexp.MustCompile(`[^a-zA-Z0-9\s]`)
safeQuery := re.ReplaceAllString(query, "")
words := strings.Fields(safeQuery)
```

**Verify**: `cd backend && go test ./internal/search/...`

## Done criteria
- [ ] Punctuation is stripped from `toPrefixTsQuery`.
- [ ] `plans/README.md` updated.
