# Projection Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Three improvements to `backend/internal/sync/projection.go`

**Architecture:** All changes are in `backend/internal/sync/`. No new sqlc queries needed — `UpsertTaskCompletion` already exists.

**Tech Stack:** Go, sqlc, CRDT (ygo)

---

### Task 1: Add test for position-based ordering

**Files:**
- Modify: `backend/internal/sync/projection_unit_test.go`

- [ ] **Step 1: Add the test**

```go
func TestDeriveMarkdownFromDoc_PositionsCBA(t *testing.T) {
	doc := makeNodeDoc(t, []struct{ key, pos, typ, text string }{
		{key: "c", pos: "c", typ: "paragraph", text: "c content"},
		{key: "a", pos: "a", typ: "paragraph", text: "a content"},
		{key: "b", pos: "b", typ: "paragraph", text: "b content"},
	})

	md := deriveMarkdownFromDoc(doc)
	expected := "a content\nb content\nc content"
	assert.Equal(t, expected, md)
}
```

- [ ] **Step 2: Run test to verify**

```bash
cd C:\Users\rigleyc\projects\supanotes\backend
go test ./internal/sync/ -v -run TestDeriveMarkdownFromDoc_PositionsCBA
```

Expected: PASS

### Task 2: Switch task_completion to UpsertTaskCompletion with deterministic UUID

**Files:**
- Modify: `backend/internal/sync/projection.go`

- [ ] **Step 1: Change `CreateTaskCompletion` to `UpsertTaskCompletion`**

In `ProjectNoteContentFromYDoc`, replace:

```go
if _, err := q.CreateTaskCompletion(ctx, sqlcgen.CreateTaskCompletionParams{
    TaskID:  t.ID,
    DueDate: t.DueDate,
}); err != nil {
```

With:

```go
completionUUID := uuid.NewSHA1(uuid.NameSpaceURL, []byte(uuid.UUID(t.ID.Bytes).String()+t.CompletedAt.Time.Format(time.RFC3339Nano)))
if err := q.UpsertTaskCompletion(ctx, sqlcgen.UpsertTaskCompletionParams{
    ID:          pgtype.UUID{Bytes: completionUUID, Valid: true},
    TaskID:      t.ID,
    CompletedAt: t.CompletedAt,
    UserID:      defaultUserID,
}); err != nil {
```

- [ ] **Step 2: Build to verify compilation**

```bash
cd C:\Users\rigleyc\projects\supanotes\backend
go build ./...
```

Expected: exit code 0

- [ ] **Step 3: Run unit tests**

```bash
cd C:\Users\rigleyc\projects\supanotes\backend
go test ./internal/sync/ -v -run TestProjection 2>&1 | Select-Object -Last 20
```

Expected: tests pass
