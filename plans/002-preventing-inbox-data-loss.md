# Plan 002: Preventing Inbox Data Loss

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat ff944a4..HEAD -- backend/internal/notes/service.go`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `ff944a4`, 2026-06-13

## Why this matters

When planning the inbox organization, note snippets longer than 150 characters are truncated with `...` for display. When the user applies the plan, `ApplyOrganization` creates or appends notes using the truncated `OriginalSnippet` sent by the client. However, it successfully deletes the full original content from the inbox, leading to permanent data loss of all text beyond the 150-character limit.

## Current state

- `backend/internal/notes/service.go` — defines `ApplyOrganization` logic

Excerpts:
In `backend/internal/notes/service.go` line 181:
```go
func (s *Service) ApplyOrganization(ctx context.Context, userID pgtype.UUID, items []PlanOrganizationItem) error {
	inbox, err := s.GetInboxNote(ctx, userID)
	if err != nil {
		return err
	}

	outgoing := make(map[string]PlanOrganizationItem, len(items))
	for _, item := range items {
		if item.Accepted {
			outgoing[item.ItemID] = item
		}
	}

	for _, item := range items {
		if !item.Accepted {
			continue
		}
		switch item.DestinationType {
		case DestNewNote:
			if _, err := s.CreateNote(ctx, userID, item.DestinationTitle, item.OriginalSnippet, nil, false, false); err != nil {
				return fmt.Errorf("create note: %w", err)
			}
		case DestExistingNote:
			if item.DestinationNoteID == nil {
				continue
			}
			noteID, err := uid.UUIDFromString(*item.DestinationNoteID)
			if err != nil {
				return fmt.Errorf("invalid destination note id: %w", err)
			}
			if _, err := s.AppendToNoteContent(ctx, userID, noteID, item.OriginalSnippet); err != nil {
				return fmt.Errorf("append to note: %w", err)
			}
		case DestKeep:
		}
	}
```

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build   | `go build ./cmd/server` | exit 0              |
| Lint    | `go vet ./...`          | exit 0              |
| Tests   | `go test ./internal/notes/...` | all pass       |

## Scope

**In scope**:
- `backend/internal/notes/service.go`

**Out of scope**:
- Modifications to database schema
- Frontend code modifications

## Git workflow

- Branch: `fix/inbox-data-loss`
- Commit format: `fix(notes): resolve data loss on inbox organization`

## Steps

### Step 1: Map items to full snippets in ApplyOrganization
Update `ApplyOrganization` in `backend/internal/notes/service.go` to split `inbox.Content` into lines *before* iterating over the items, and map each item's ID back to its untruncated content.
Use the parsed index from `itemID` to get the line from `lines` slice. Add a safety prefix check to confirm we have the right snippet (supporting fallback if comparison fails).

Update `backend/internal/notes/service.go` as follows:
```go
func (s *Service) ApplyOrganization(ctx context.Context, userID pgtype.UUID, items []PlanOrganizationItem) error {
	inbox, err := s.GetInboxNote(ctx, userID)
	if err != nil {
		return err
	}

	noteIDStr := uid.UUIDToString(inbox.ID)
	lines := strings.Split(inbox.Content, "\n\n")

	outgoing := make(map[string]PlanOrganizationItem, len(items))
	for _, item := range items {
		if item.Accepted {
			outgoing[item.ItemID] = item
		}
	}

	for _, item := range items {
		if !item.Accepted {
			continue
		}

		// Reconstruct the full snippet from the split inbox content using the index in ItemID
		fullSnippet := item.OriginalSnippet
		parts := strings.Split(item.ItemID, "-")
		if len(parts) >= 2 {
			var idx int
			_, scanErr := fmt.Sscanf(parts[len(parts)-1], "%d", &idx)
			if scanErr == nil && idx >= 0 && idx < len(lines) {
				candidate := strings.TrimSpace(lines[idx])
				// Safety check: ensure the candidate has the same prefix as the truncated display snippet
				prefix := strings.TrimSuffix(item.OriginalSnippet, "...")
				if strings.HasPrefix(candidate, prefix) {
					fullSnippet = candidate
				}
			}
		}

		switch item.DestinationType {
		case DestNewNote:
			if _, err := s.CreateNote(ctx, userID, item.DestinationTitle, fullSnippet, nil, false, false); err != nil {
				return fmt.Errorf("create note: %w", err)
			}
		case DestExistingNote:
			if item.DestinationNoteID == nil {
				continue
			}
			noteID, err := uid.UUIDFromString(*item.DestinationNoteID)
			if err != nil {
				return fmt.Errorf("invalid destination note id: %w", err)
			}
			if _, err := s.AppendToNoteContent(ctx, userID, noteID, fullSnippet); err != nil {
				return fmt.Errorf("append to note: %w", err)
			}
		case DestKeep:
		}
	}

	var keptLines []string
	for i, line := range lines {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" {
			continue
		}
		itemID := fmt.Sprintf("%s-%d", noteIDStr, i)
		reqItem, isOutgoing := outgoing[itemID]
		if !isOutgoing || reqItem.DestinationType == DestKeep {
			keptLines = append(keptLines, trimmed)
		}
	}
	newContent := strings.Join(keptLines, "\n\n")
	_, err = s.SetInboxContent(ctx, userID, newContent)
	return err
}
```

**Verify**: `go build ./cmd/server` exits 0.

## Test plan

- Update or add tests in `backend/internal/notes/service_test.go` to test organizing a long snippet (> 150 characters) and verify that the newly created note receives the entire original text rather than the truncated preview.
- Verification: `go test ./internal/notes/...` exits 0.

## Done criteria

- [ ] `go test ./internal/notes/...` passes successfully
- [ ] No files outside `backend/internal/notes/service.go` are modified

## STOP conditions

- If `ApplyOrganization` logic does not split the inbox content by `\n\n` as shown in the Current state.
- If existing unit tests in `service_test.go` fail because of mismatched structs.
