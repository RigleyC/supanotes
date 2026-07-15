package sync

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"sort"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/reearth/ygo/crdt"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

// nodeEntry holds a parsed node from the YMap with its positional ordering key.
type nodeEntry struct {
	Type     string
	ID       string
	Position string
	Text     string
	Data     json.RawMessage
}

func posToString(pos any) string {
	if pos == nil {
		return ""
	}
	switch v := pos.(type) {
	case string:
		return v
	case float64:
		return fmt.Sprintf("%g", v)
	default:
		slog.Warn("posToString: unexpected position type", "type", fmt.Sprintf("%T", pos))
		return ""
	}
}

// nodesFromDoc reads all nodes from the YMap and returns them sorted by position.
func nodesFromDoc(doc *crdt.Doc) []nodeEntry {
	nodesMap := doc.GetMap("nodes")
	if nodesMap == nil {
		return nil
	}
	var entries []nodeEntry
	for _, key := range nodesMap.Keys() {
		raw, ok := nodesMap.Get(key)
		if !ok || raw == nil {
			continue
		}
		nodeStr, ok := raw.(string)
		if !ok {
			continue
		}
		var nd struct {
			ID       string          `json:"id"`
			Type     string          `json:"type"`
			Position any             `json:"position"`
			Data     json.RawMessage `json:"data"`
		}
		if err := json.Unmarshal([]byte(nodeStr), &nd); err != nil {
			continue
		}
		posStr := posToString(nd.Position)
		text := ""
		if textType := doc.GetText("content/" + nd.ID); textType != nil {
			text = textType.ToString()
		} else {
			var dataMap map[string]interface{}
			if json.Unmarshal(nd.Data, &dataMap) == nil {
				if t, ok := dataMap["text"].(string); ok {
					text = t
				}
			}
		}
		entries = append(entries, nodeEntry{
			ID:       nd.ID,
			Type:     nd.Type,
			Position: posStr,
			Data:     nd.Data,
			Text:     text,
		})
	}
	sort.Slice(entries, func(i, j int) bool {
		return entries[i].Position < entries[j].Position
	})
	return entries
}

func parseUUIDStr(s string) (pgtype.UUID, error) {
	u, err := uuid.Parse(s)
	if err != nil {
		return pgtype.UUID{}, fmt.Errorf("uuid %q: %w", s, err)
	}
	return pgtype.UUID{Bytes: u, Valid: true}, nil
}

// ProjectNoteContentFromYDoc derives relational projections (notes.content, tasks)
// from the YDoc state. Called asynchronously after YDoc mutations.
//
// Pipeline (3 phases, all synchronous within a single DB transaction):
//
//	1. Load — fetch YDoc state from DB, reconstruct crdt.Doc
//	2. Derive — compute markdown content + task list from the Doc
//	3. Persist — write content + upsert tasks + delete orphans + record completions
func ProjectNoteContentFromYDoc(ctx context.Context, pool *pgxpool.Pool, noteID string) error {
	startTotal := time.Now()

	// ---- Phase 1: Load YDoc state ----
	noteUUID, err := parseUUIDStr(noteID)
	if err != nil {
		return fmt.Errorf("parse note id: %w", err)
	}

	state, err := LoadYDocState(ctx, pool, noteID)
	if err != nil {
		return fmt.Errorf("load ydoc state: %w", err)
	}
	if len(state) == 0 {
		return nil
	}

	doc := crdt.New(crdt.WithGC(false))
	if err := crdt.ApplyUpdateV1(doc, state, nil); err != nil {
		return fmt.Errorf("apply ydoc state: %w", err)
	}

	// ---- Phase 2: Derive projections from YDoc ----
	content := deriveMarkdownFromDoc(doc)

	tasks := deriveTasksFromDoc(doc)

	// ---- Phase 3: Persist projections to SQL ----


	tx, err := pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	q := sqlcgen.New(tx)

	var defaultUserID pgtype.UUID
	if err := tx.QueryRow(ctx, "SELECT user_id FROM notes WHERE id = $1", noteUUID).Scan(&defaultUserID); err != nil {
		if !errors.Is(err, pgx.ErrNoRows) {
			return fmt.Errorf("get note owner: %w", err)
		}
	}

	if err := q.UpdateNoteContent(ctx, sqlcgen.UpdateNoteContentParams{
		ID:      noteUUID,
		Content: content,
	}); err != nil {
		return fmt.Errorf("update note content: %w", err)
	}

	// Read existing tasks before upsert to detect completion transitions
	existingRows, err := q.GetTasksByNoteID(ctx, sqlcgen.GetTasksByNoteIDParams{
		UserID: defaultUserID,
		NoteID: noteUUID,
	})
	if err != nil {
		return fmt.Errorf("get existing tasks: %w", err)
	}
	existingCompleted := make(map[[16]byte]pgtype.Timestamptz)
	for _, e := range existingRows {
		existingCompleted[e.ID.Bytes] = e.CompletedAt
	}

	// Delete orphaned tasks that exist in DB but not in the YDoc
	var keepIDs []pgtype.UUID
	for _, t := range tasks {
		keepIDs = append(keepIDs, t.ID)
	}
	if err := q.DeleteTasksByNoteID(ctx, sqlcgen.DeleteTasksByNoteIDParams{
		NoteID:  noteUUID,
		KeepIds: keepIDs,
	}); err != nil {
		return fmt.Errorf("delete orphaned tasks: %w", err)
	}

	for _, t := range tasks {
		params := sqlcgen.UpsertTaskParams{
			ID:          t.ID,
			UserID:      defaultUserID,
			NoteID:      noteUUID,
			Title:       t.Title,
			Status:      t.Status,
			Position:    t.Position,
			Recurrence:  t.Recurrence,
			DueDate:     t.DueDate,
			CompletedAt: t.CompletedAt,
			CreatedAt:   t.CreatedAt,
			DeletedAt:   pgtype.Timestamptz{Valid: false},
		}
		if _, err := q.UpsertTask(ctx, params); err != nil {
			return fmt.Errorf("upsert task %s: %w", uuid.UUID(t.ID.Bytes).String(), err)
		}

		// Insert task_completion when completed transitions from nil → value
		// Uses deterministic UUID v5 from task_id + completed_at for idempotency
		oldCompleted := existingCompleted[t.ID.Bytes]
		if t.CompletedAt.Valid && !oldCompleted.Valid {
			completionUUID := uuid.NewSHA1(uuid.NameSpaceURL, []byte(uuid.UUID(t.ID.Bytes).String()+t.CompletedAt.Time.Format(time.RFC3339Nano)))
			if err := q.UpsertTaskCompletion(ctx, sqlcgen.UpsertTaskCompletionParams{
				ID:          pgtype.UUID{Bytes: completionUUID, Valid: true},
				TaskID:      t.ID,
				CompletedAt: t.CompletedAt,
				UserID:      defaultUserID,
			}); err != nil {
				return fmt.Errorf("create task completion for %s: %w", uuid.UUID(t.ID.Bytes).String(), err)
			}
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit: %w", err)
	}

	slog.Info("ProjectNoteContentFromYDoc: done", "note_id", noteID, "content_bytes", len(content), "tasks", len(tasks), "total_ms", time.Since(startTotal).Milliseconds())
	return nil
	// ---- End Phase 3 ----
}

// LoadYDocState loads the Yjs document state for a note from the database.
// It prefers the compacted snapshot from note_yjs_states + pending updates.
// Returns nil, nil if pool is nil (used in tests).
func LoadYDocState(ctx context.Context, pool *pgxpool.Pool, noteID string) ([]byte, error) {
	if pool == nil {
		return nil, nil
	}
	startTotal := time.Now()

	noteUUID, err := parseUUIDStr(noteID)
	if err != nil {
		return nil, err
	}

	startQuery := time.Now()
	var state []byte
	err = pool.QueryRow(ctx, "SELECT state FROM note_yjs_states WHERE note_id = $1", noteUUID).Scan(&state)
	queryElapsed := time.Since(startQuery)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			slog.Info("LoadYDocState: no snapshot, returning empty state", "note_id", noteID, "query_ms", queryElapsed.Milliseconds())
			state = nil
		} else {
			slog.Error("LoadYDocState: query state failed", "note_id", noteID, "error", err, "elapsed_ms", queryElapsed.Milliseconds())
			return nil, fmt.Errorf("load state: %w", err)
		}
	} else {
		slog.Info("LoadYDocState: state loaded", "note_id", noteID, "state_bytes", len(state), "query_ms", queryElapsed.Milliseconds())
	}

	startPending := time.Now()
	rows, err := pool.Query(ctx, "SELECT update_data FROM note_yjs_updates WHERE note_id = $1 ORDER BY created_at ASC", noteUUID)
	if err != nil {
		slog.Error("LoadYDocState: query updates failed", "note_id", noteID, "error", err, "elapsed_ms", time.Since(startPending).Milliseconds())
		return nil, fmt.Errorf("query pending updates: %w", err)
	}
	defer rows.Close()

	var pending [][]byte
	for rows.Next() {
		var u []byte
		if err := rows.Scan(&u); err != nil {
			slog.Error("LoadYDocState: scan update failed", "note_id", noteID, "error", err)
			return nil, fmt.Errorf("scan pending update: %w", err)
		}
		pending = append(pending, u)
	}
	if err := rows.Err(); err != nil {
		slog.Error("LoadYDocState: rows iter failed", "note_id", noteID, "error", err)
		return nil, fmt.Errorf("rows iter: %w", err)
	}
	slog.Info("LoadYDocState: pending updates loaded", "note_id", noteID, "pending_count", len(pending), "elapsed_ms", time.Since(startPending).Milliseconds())

	if len(pending) == 0 {
		slog.Info("LoadYDocState: done (no merge needed)", "note_id", noteID, "total_ms", time.Since(startTotal).Milliseconds())
		return state, nil
	}

	startMerge := time.Now()
	var all [][]byte
	if len(state) > 0 {
		all = append(all, state)
	}
	for _, u := range pending {
		if len(u) > 0 {
			all = append(all, u)
		}
	}
	if len(all) == 0 {
		slog.Info("LoadYDocState: done (no valid updates to merge)", "note_id", noteID, "total_ms", time.Since(startTotal).Milliseconds())
		return nil, nil
	}
	if len(all) == 1 {
		slog.Info("LoadYDocState: done (single valid update)", "note_id", noteID, "total_ms", time.Since(startTotal).Milliseconds())
		return all[0], nil
	}
	merged, err := crdt.MergeUpdatesV1(all...)
	if err != nil {
		slog.Error("LoadYDocState: merge failed", "note_id", noteID, "error", err, "elapsed_ms", time.Since(startMerge).Milliseconds())
		return nil, fmt.Errorf("merge pending updates: %w", err)
	}
	slog.Info("LoadYDocState: done (merged)", "note_id", noteID, "merged_bytes", len(merged), "merge_ms", time.Since(startMerge).Milliseconds(), "total_ms", time.Since(startTotal).Milliseconds())
	return merged, nil
}
