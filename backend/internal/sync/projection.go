package sync

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"sort"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/reearth/ygo/crdt"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

// NodeEntry holds a parsed node from the YMap with its positional ordering key.
type NodeEntry struct {
	Type     string
	ID       string
	Position string
	Text     string
	Data     json.RawMessage
	// Metadata holds task-specific fields (completed, dueDate, recurrence, etc.)
	// normalized from either nested YMap keys (new schema) or the "data" sub-object
	// in the legacy JSON string. Consumers of NodeEntry should read from Metadata
	// instead of re-parsing raw YMap or JSON types.
	Metadata map[string]any
}

// normalizeNodeMetadata extracts task metadata from a raw YMap entry, supporting
// both the new nested YMap schema and the legacy JSON string schema.
// It also reads composite keys from the parent nodesMap.
func normalizeNodeMetadata(nodesMap *crdt.YMap, nodeID string, raw any) map[string]any {
	meta := make(map[string]any)

	switch v := raw.(type) {
	case *crdt.YMap:
		for _, key := range v.Keys() {
			switch key {
			case "id", "type", "position", "data":
				continue
			}
			val, ok := v.Get(key)
			if ok {
				meta[key] = val
			}
		}
	case map[string]any:
		for key, val := range v {
			switch key {
			case "id", "type", "position", "data":
				continue
			default:
				meta[key] = val
			}
		}
	case string:
		var legacy struct {
			Data map[string]any `json:"data"`
		}
		if err := json.Unmarshal([]byte(v), &legacy); err == nil {
			for k, val := range legacy.Data {
				switch k {
				case "completed", "dueDate", "recurrence", "lastCompletedAt":
					meta[k] = val
				}
			}
		}
	}

	// Override with composite keys from nodesMap if present
	if nodesMap != nil {
		if val, ok := nodesMap.Get(nodeID + ":completed"); ok {
			meta["completed"] = val
		}
		if val, ok := nodesMap.Get(nodeID + ":dueDate"); ok {
			meta["dueDate"] = val
		}
		if val, ok := nodesMap.Get(nodeID + ":recurrence"); ok {
			meta["recurrence"] = val
		}
		if val, ok := nodesMap.Get(nodeID + ":lastCompletedAt"); ok {
			meta["lastCompletedAt"] = val
		}
	}

	return meta
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

func nodeText(doc *crdt.Doc, nodeID string, data json.RawMessage) string {
	for _, key := range []string{"content_fixed/" + nodeID, "content/" + nodeID} {
		if textType := doc.GetText(key); textType != nil {
			if text := textType.ToString(); text != "" {
				return text
			}
		}
	}

	var dataMap map[string]any
	if json.Unmarshal(data, &dataMap) == nil {
		text, _ := dataMap["text"].(string)
		return text
	}
	return ""
}

// NodesFromDoc reads all nodes from the YMap and returns them sorted by position.
// Supports both nested YMap entries (new schema) and JSON string entries (legacy).
func NodesFromDoc(doc *crdt.Doc) []NodeEntry {
	nodesMap := doc.GetMap("nodes")
	if nodesMap == nil {
		return nil
	}
	var entries []NodeEntry
	for key, raw := range nodesMap.Entries() {
		if raw == nil {
			continue
		}
		switch v := raw.(type) {
		case *crdt.YMap:
			id, _ := v.Get("id")
			idStr, _ := id.(string)
			if idStr == "" {
				idStr = key
			}
			typeName, _ := v.Get("type")
			typeStr, _ := typeName.(string)
			pos, _ := v.Get("position")
			posStr := posToString(pos)
			// Serialize YMap data to JSON for backward compat
			var dataRaw json.RawMessage
			if d, exists := v.Get("data"); exists {
				switch d2 := d.(type) {
				case string:
					dataRaw = json.RawMessage(d2)
				case []byte:
					dataRaw = json.RawMessage(d2)
				default:
					if b, err := json.Marshal(d2); err == nil {
						dataRaw = b
					}
				}
			}
			text := nodeText(doc, idStr, dataRaw)
			entries = append(entries, NodeEntry{
				ID:       idStr,
				Type:     typeStr,
				Position: posStr,
				Data:     dataRaw,
				Text:     text,
				Metadata: normalizeNodeMetadata(nodesMap, idStr, v),
			})
		case map[string]any:
			idStr, _ := v["id"].(string)
			if idStr == "" {
				idStr = key
			}
			typeStr, _ := v["type"].(string)
			posStr := posToString(v["position"])

			var dataRaw json.RawMessage
			if data, exists := v["data"]; exists {
				switch d := data.(type) {
				case string:
					dataRaw = json.RawMessage(d)
				case []byte:
					dataRaw = json.RawMessage(d)
				default:
					if encoded, err := json.Marshal(d); err == nil {
						dataRaw = encoded
					}
				}
			}

			text := nodeText(doc, idStr, dataRaw)

			entries = append(entries, NodeEntry{
				ID:       idStr,
				Type:     typeStr,
				Position: posStr,
				Data:     dataRaw,
				Text:     text,
				Metadata: normalizeNodeMetadata(nodesMap, idStr, v),
			})
		case string:
			var nd struct {
				ID       string          `json:"id"`
				Type     string          `json:"type"`
				Position any             `json:"position"`
				Data     json.RawMessage `json:"data"`
			}
			if err := json.Unmarshal([]byte(v), &nd); err != nil {
				continue
			}
			posStr := posToString(nd.Position)
			text := nodeText(doc, nd.ID, nd.Data)
			entries = append(entries, NodeEntry{
				ID:       nd.ID,
				Type:     nd.Type,
				Position: posStr,
				Data:     nd.Data,
				Text:     text,
				Metadata: normalizeNodeMetadata(nodesMap, nd.ID, v),
			})
		}
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
//  1. Load — fetch YDoc state from DB, reconstruct crdt.Doc
//  2. Derive — compute markdown content + task list from the Doc
//  3. Persist — write content + upsert tasks + delete orphans + record completions
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
	PreRegisterYText(doc, state)
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

	// Serialize projections per note so two concurrent calls for the same note
	// cannot race (e.g., debounce callback + handleNotification or scheduler).
	if _, err := tx.Exec(ctx, "SELECT pg_advisory_xact_lock(hashtext($1::text), hashtext('projection'))", noteID); err != nil {
		return fmt.Errorf("advisory lock: %w", err)
	}

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

	// Batch upsert all derived tasks in a single query
	var (
		ids          []pgtype.UUID
		noteIDs      []pgtype.UUID
		userIDs      []pgtype.UUID
		titles       []string
		statuses     []string
		dueDates     []pgtype.Date
		recurrences  []string
		positions    []string
		completedAts []pgtype.Timestamptz
		createdAts   []pgtype.Timestamptz
		deletedAts   []pgtype.Timestamptz
	)
	for _, t := range tasks {
		ids = append(ids, t.ID)
		noteIDs = append(noteIDs, noteUUID)
		userIDs = append(userIDs, defaultUserID)
		titles = append(titles, t.Title)
		statuses = append(statuses, t.Status)
		dueDates = append(dueDates, t.DueDate)
		recurrences = append(recurrences, t.Recurrence.String)
		positions = append(positions, t.Position)
		completedAts = append(completedAts, t.CompletedAt)
		createdAts = append(createdAts, t.CreatedAt)
		deletedAts = append(deletedAts, pgtype.Timestamptz{Valid: false})
	}
	if err := q.UpsertTasksBatch(ctx, sqlcgen.UpsertTasksBatchParams{
		Column1:  ids,
		Column2:  noteIDs,
		Column3:  userIDs,
		Column4:  titles,
		Column5:  statuses,
		Column6:  dueDates,
		Column7:  recurrences,
		Column8:  positions,
		Column9:  completedAts,
		Column10: createdAts,
		Column11: deletedAts,
	}); err != nil {
		return fmt.Errorf("batch upsert tasks: %w", err)
	}

	if err := q.DeleteRecurringTaskCompletionsByNoteID(ctx, noteUUID); err != nil {
		return fmt.Errorf("clear recurring task completions: %w", err)
	}

	// --- Insert task completions from two sources: ---

	// 1) Legacy: completedAt transition nil → value (covers non-recurring tasks)
	for _, t := range tasks {
		oldCompleted := existingCompleted[t.ID.Bytes]
		if t.CompletedAt.Valid && !oldCompleted.Valid {
			scheduledAt := t.CompletedAt.Time
			completionUUID := uuid.NewSHA1(uuid.NameSpaceURL, []byte(uuid.UUID(t.ID.Bytes).String()+scheduledAt.Format(time.RFC3339Nano)))
			if err := q.UpsertTaskCompletion(ctx, sqlcgen.UpsertTaskCompletionParams{
				ID:          pgtype.UUID{Bytes: completionUUID, Valid: true},
				TaskID:      t.ID,
				CompletedAt: t.CompletedAt,
				ScheduledAt: pgtype.Timestamptz{Time: scheduledAt, Valid: true},
				UserID:      defaultUserID,
			}); err != nil {
				return fmt.Errorf("legacy task completion for %s: %w", uuid.UUID(t.ID.Bytes).String(), err)
			}
		}
	}

	// 2) Per-occurrence completions from YDoc taskCompletions root YMap
	//    (covers recurring tasks — new model)
	if taskCompletionsMap := doc.GetMap("taskCompletions"); taskCompletionsMap != nil {
		for key, rawVal := range taskCompletionsMap.Entries() {
			if rawVal == nil {
				continue
			}
			completedAtStr, ok := rawVal.(string)
			if !ok || completedAtStr == "" {
				continue
			}
			completedAt, err := time.Parse(time.RFC3339, completedAtStr)
			if err != nil {
				continue
			}

			colonIdx := strings.Index(key, ":")
			if colonIdx == -1 {
				continue
			}
			taskID := key[:colonIdx]
			scheduledAtStr := key[colonIdx+1:]

			taskUUID, err := parseUUIDStr(taskID)
			if err != nil {
				continue
			}

			var scheduledAt time.Time
			if strings.Contains(scheduledAtStr, "T") {
				scheduledAt, err = time.Parse("2006-01-02T15:04", scheduledAtStr)
			} else {
				scheduledAt, err = time.Parse("2006-01-02", scheduledAtStr)
			}
			if err != nil {
				continue
			}

			completionUUID := uuid.NewSHA1(uuid.NameSpaceURL, []byte(taskID+":"+scheduledAt.Format(time.RFC3339)))
			if err := q.UpsertTaskCompletion(ctx, sqlcgen.UpsertTaskCompletionParams{
				ID:          pgtype.UUID{Bytes: completionUUID, Valid: true},
				TaskID:      taskUUID,
				CompletedAt: pgtype.Timestamptz{Time: completedAt, Valid: true},
				ScheduledAt: pgtype.Timestamptz{Time: scheduledAt, Valid: true},
				UserID:      defaultUserID,
			}); err != nil {
				return fmt.Errorf("task completion for %s@%s: %w", taskID, scheduledAtStr, err)
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
