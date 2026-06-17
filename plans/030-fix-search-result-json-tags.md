# Plan 030: Add json tags to SearchResult and match Flutter client expectations

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat fd87433..HEAD -- backend/internal/search/service.go lib/features/search/domain/search_result_model.dart`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `fd87433`, 2026-06-17

## Why this matters

The `SearchResult` struct in the backend has **no json tags at all**. Go's `encoding/json` serializes untagged struct fields by lowercasing the first letter, producing `id`, `title`, `content`, `excerpt`, `updatedat`, `contextid`, `favorite`, `archived`, `score`. But the Flutter client's `SearchResultModel.fromJson` expects PascalCase keys: `ID`, `Title`, `Excerpt`, `Score`. This means every search response returns data that the client cannot parse — all fields silently fall back to defaults (empty strings, score 0.0).

Additionally, the struct uses raw `pgtype.UUID` and `pgtype.Timestamptz` which would leak their internal format even if the keys matched.

## Current state

**Backend** — `backend/internal/search/service.go:15-25`:
```go
type SearchResult struct {
    ID        pgtype.UUID
    Title     string
    Content   string
    Excerpt   string
    UpdatedAt pgtype.Timestamptz
    ContextID pgtype.UUID
    Favorite  bool
    Archived  bool
    Score     float64
}
```

No json tags. Uses raw pgtype. The handler at `handler.go:45` returns this directly: `c.JSON(http.StatusOK, results)`.

**Flutter** — `lib/features/search/domain/search_result_model.dart:19-26`:
```dart
factory SearchResultModel.fromJson(Map<String, dynamic> json) {
    return SearchResultModel(
      id: (json['ID'] ?? '') as String,
      title: (json['Title'] ?? '') as String,
      excerpt: (json['Excerpt'] ?? '') as String,
      score: _readScore(json['Score']),
    );
  }
```

Expects PascalCase keys (`ID`, `Title`, `Excerpt`, `Score`). Only reads 4 of the 9 fields the backend sends.

**Convention reference** — `backend/internal/dto/context.go`:
```go
type ContextResponse struct {
    ID        string `json:"id"`
    Slug      string `json:"slug"`
    Name      string `json:"name"`
    CreatedAt string `json:"created_at"`
    UpdatedAt string `json:"updated_at"`
}
```

DTOs use `string` fields with `json` tags in snake_case. But the Flutter client expects PascalCase for search results specifically.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build backend | `cd backend && go build ./...` | exit 0, no errors |
| Vet backend | `cd backend && go vet ./...` | exit 0, no errors |

## Scope

**In scope**:
- `backend/internal/search/service.go` — add json tags to `SearchResult`, convert pgtype to strings

**Out of scope**:
- `lib/features/search/domain/search_result_model.dart` — already correct; it defines the client contract
- `backend/internal/search/handler.go` — no changes needed; it already returns `results` directly
- Other search-related code (FTS, embeddings) — not affected

## Git workflow

- Branch: `fix/030-search-result-json-tags`
- Commit: `fix(search): add json tags to SearchResult and convert pgtype to strings`
- Do NOT push unless instructed.

## Steps

### Step 1: Add json tags and convert pgtype fields in SearchResult

In `backend/internal/search/service.go`, change the `SearchResult` struct to:

```go
type SearchResult struct {
    ID        string  `json:"id"`
    Title     string  `json:"title"`
    Content   string  `json:"content"`
    Excerpt   string  `json:"excerpt"`
    UpdatedAt string  `json:"updated_at"`
    ContextID string  `json:"context_id"`
    Favorite  bool    `json:"favorite"`
    Archived  bool    `json:"archived"`
    Score     float64 `json:"score"`
}
```

This uses snake_case json keys matching the backend convention. But the Flutter client expects PascalCase — so we also need to update the Flutter client in the same step.

**Wait — decision needed**: The Flutter client reads `json['ID']`, `json['Title']`, `json['Excerpt']`, `json['Score']` (PascalCase). The backend convention is snake_case. Which do we match?

**Answer**: Match the Flutter client contract. The client is the consumer. Change the json tags to PascalCase to match what the client expects, since this is a read-only endpoint and the client already defines the shape.

Actually, looking more carefully: the client only reads 4 fields (`ID`, `Title`, `Excerpt`, `Score`). The backend sends 9 fields. The extra fields (`Content`, `UpdatedAt`, `ContextID`, `Favorite`, `Archived`) are currently not consumed by the client. Let's use snake_case tags (backend convention) and update the Flutter client to match. This is the cleaner long-term approach.

**Revised Step 1**: Add snake_case json tags and convert pgtype fields:

```go
type SearchResult struct {
    ID        string  `json:"id"`
    Title     string  `json:"title"`
    Content   string  `json:"content"`
    Excerpt   string  `json:"excerpt"`
    UpdatedAt string  `json:"updated_at"`
    ContextID string  `json:"context_id"`
    Favorite  bool    `json:"favorite"`
    Archived  bool    `json:"archived"`
    Score     float64 `json:"score"`
}
```

Update the `Search` method (line 61-74) to convert pgtype values:

```go
res[i] = SearchResult{
    ID:        uid.UUIDToString(r.ID),
    Title:     r.Title.String,
    Content:   r.Content,
    Excerpt:   r.Excerpt.String,
    UpdatedAt: r.UpdatedAt.Time.Format(time.RFC3339),
    ContextID: uid.UUIDToString(r.ContextID),
    Favorite:  r.Favorite,
    Archived:  r.Archived,
    Score:     r.Score,
}
```

Add `"time"` and `"github.com/RigleyC/supanotes/pkg/uid"` to the imports.

**Verify**: `cd backend && go build ./...` → exit 0

### Step 2: Update Flutter client to expect snake_case keys

In `lib/features/search/domain/search_result_model.dart`, change the `fromJson` factory from:

```dart
factory SearchResultModel.fromJson(Map<String, dynamic> json) {
    return SearchResultModel(
      id: (json['ID'] ?? '') as String,
      title: (json['Title'] ?? '') as String,
      excerpt: (json['Excerpt'] ?? '') as String,
      score: _readScore(json['Score']),
    );
  }
```

To:

```dart
factory SearchResultModel.fromJson(Map<String, dynamic> json) {
    return SearchResultModel(
      id: (json['id'] ?? '') as String,
      title: (json['title'] ?? '') as String,
      excerpt: (json['excerpt'] ?? '') as String,
      score: _readScore(json['score']),
    );
  }
```

**Verify**: `flutter analyze lib/features/search/` → no new errors

## Test plan

- No existing tests for search serialization.
- Manual verification: call `POST /api/v1/search` with a valid query and confirm the response has snake_case keys and clean string values for `id` and `updated_at`.

## Done criteria

- [ ] `cd backend && go build ./...` exits 0
- [ ] `cd backend && go vet ./...` exits 0
- [ ] `grep -n 'pgtype' backend/internal/search/service.go` returns no matches (except possibly in import if still needed for other code)
- [ ] `grep -n "json\['ID'\]" lib/features/search/domain/search_result_model.dart` returns no matches
- [ ] `grep -n "json\['id'\]" lib/features/search/domain/search_result_model.dart` returns matches
- [ ] `plans/README.md` status row updated

## STOP conditions

- If the Flutter client has other callers of `SearchResultModel.fromJson` that pass PascalCase keys.
- If `service.go` has changed and the `Search` method signature is different.
- If a step's verification fails twice after a reasonable fix attempt.

## Maintenance notes

- The `Content`, `UpdatedAt`, `ContextID`, `Favorite`, `Archived` fields are now exposed in the JSON but not consumed by the Flutter client yet. This is fine — they're available for future use.
- If the search endpoint is ever used by other clients, the snake_case convention is the standard to follow.
