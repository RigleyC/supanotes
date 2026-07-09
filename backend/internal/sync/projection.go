package sync

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/reearth/ygo/crdt"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

type noteNodeJSON struct {
	ID        string          `json:"id"`
	ParentID  string          `json:"parentId,omitempty"`
	Position  float64         `json:"position"`
	Type      string          `json:"type"`
	Data      json.RawMessage `json:"data"`
	CreatedAt float64         `json:"createdAt,omitempty"`
	UpdatedAt float64         `json:"updatedAt,omitempty"`
}

type taskJSON struct {
	ID          string  `json:"id"`
	NoteID      string  `json:"noteId"`
	UserID      string  `json:"userId,omitempty"`
	Title       string  `json:"title"`
	Status      string  `json:"status"`
	Position    float64 `json:"position"`
	Recurrence  string  `json:"recurrence,omitempty"`
	DueDate     string  `json:"dueDate,omitempty"`
	CreatedAt   float64 `json:"createdAt,omitempty"`
	CompletedAt float64 `json:"completedAt,omitempty"`
}

func parseUUIDStr(s string) (pgtype.UUID, error) {
	u, err := uuid.Parse(s)
	if err != nil {
		return pgtype.UUID{}, fmt.Errorf("uuid %q: %w", s, err)
	}
	return pgtype.UUID{Bytes: u, Valid: true}, nil
}

func uuidToStr(id pgtype.UUID) string {
	if !id.Valid {
		return ""
	}
	return uuid.UUID(id.Bytes).String()
}

func msToTimestamptz(ms float64) pgtype.Timestamptz {
	if ms <= 0 {
		return pgtype.Timestamptz{Valid: false}
	}
	return pgtype.Timestamptz{Time: time.UnixMilli(int64(ms)), Valid: true}
}

func timestamptzToMS(t pgtype.Timestamptz) float64 {
	if !t.Valid {
		return 0
	}
	return float64(t.Time.UnixMilli())
}

// ProjectToDBTxFromDoc projects the full Yjs Doc state onto relational
// tables using an existing transaction. The caller is responsible for
// acquiring the advisory lock (if needed) and for committing/rolling
// back the transaction.
func ProjectToDBTxFromDoc(ctx context.Context, tx pgx.Tx, doc *crdt.Doc, noteID string) error {
	return projectDocToDB(ctx, tx, doc, noteID)
}

// projectDocToDB projects the given Doc's state onto relational tables
// using the provided transaction.
func projectDocToDB(ctx context.Context, tx pgx.Tx, doc *crdt.Doc, noteID string) error {
	noteUUID, err := parseUUIDStr(noteID)
	if err != nil {
		return fmt.Errorf("parse note id: %w", err)
	}
	q := sqlcgen.New(tx)

	if nodesMap := doc.GetMap("nodes"); nodesMap != nil {
		for _, key := range nodesMap.Keys() {
			raw, ok := nodesMap.Get(key)
			if !ok || raw == nil {
				continue
			}
			nodeStr, ok := raw.(string)
			if !ok {
				continue
			}
			var nd noteNodeJSON
			if err := json.Unmarshal([]byte(nodeStr), &nd); err != nil {
				continue
			}

			// Override text content from YText (CRDT source of truth).
			// If a YText exists for this node's content, its value
			// takes precedence over whatever is in the YMap JSON.
			if textType := doc.GetText("content/" + nd.ID); textType != nil {
				textContent := textType.ToString()
				if textContent != "" {
					var dataMap map[string]interface{}
					if len(nd.Data) > 0 {
						json.Unmarshal(nd.Data, &dataMap)
					}
					if dataMap == nil {
						dataMap = make(map[string]interface{})
					}
					dataMap["text"] = textContent
					updatedData, _ := json.Marshal(dataMap)
					nd.Data = updatedData
				}
			}

			pgNodeID, err := parseUUIDStr(nd.ID)
			if err != nil {
				continue
			}
			var parentID pgtype.UUID
			if nd.ParentID != "" {
				parentID, _ = parseUUIDStr(nd.ParentID)
			}

			dataBytes := []byte("{}")
			if len(nd.Data) > 0 {
				dataBytes = nd.Data
			}

			createdAt := msToTimestamptz(nd.CreatedAt)
			if !createdAt.Valid {
				createdAt = pgtype.Timestamptz{Time: time.Now(), Valid: true}
			}

			params := sqlcgen.UpsertNoteNodeParams{
				ID:        pgNodeID,
				NoteID:    noteUUID,
				ParentID:  parentID,
				Position:  nd.Position,
				Type:      nd.Type,
				Data:      dataBytes,
				CreatedAt: createdAt,
				DeletedAt: pgtype.Timestamptz{Valid: false},
			}
			if _, err := q.UpsertNoteNode(ctx, params); err != nil {
				return fmt.Errorf("upsert node %s: %w", key, err)
			}

			if nd.Type == "task" {
				var dataMap map[string]interface{}
				if err := json.Unmarshal(dataBytes, &dataMap); err == nil {
					if completedVal, ok := dataMap["completed"]; ok {
						completed, _ := completedVal.(bool)
						status := "open"
						if completed {
							status = "done"
						}
						// Update the corresponding tasks table status and completed_at using the transaction
						if completed {
							_, err = tx.Exec(ctx, "UPDATE tasks SET status = $1, completed_at = NOW(), updated_at = NOW() WHERE node_id = $2 AND deleted_at IS NULL", status, pgNodeID)
						} else {
							_, err = tx.Exec(ctx, "UPDATE tasks SET status = $1, completed_at = NULL, updated_at = NOW() WHERE node_id = $2 AND deleted_at IS NULL", status, pgNodeID)
						}
						if err != nil {
							return fmt.Errorf("update task status for node %s: %w", nd.ID, err)
						}
					}
				}
			}
		}

		// Soft-delete nodes removed from the YMap.
		orphanRows, err := tx.Query(ctx, "SELECT id FROM note_nodes WHERE note_id = $1 AND deleted_at IS NULL", noteUUID)
		if err != nil {
			return fmt.Errorf("query active node ids: %w", err)
		}
		var existingIDs []string
		for orphanRows.Next() {
			var id string
			if err := orphanRows.Scan(&id); err != nil {
				orphanRows.Close()
				return fmt.Errorf("scan orphan id: %w", err)
			}
			existingIDs = append(existingIDs, id)
		}
		orphanRows.Close()

		activeIDs := make(map[string]bool, len(nodesMap.Keys()))
		for _, key := range nodesMap.Keys() {
			activeIDs[key] = true
		}
		var orphanIDs []pgtype.UUID
		for _, id := range existingIDs {
			if !activeIDs[id] {
				parsed, err := parseUUIDStr(id)
				if err == nil {
					orphanIDs = append(orphanIDs, parsed)
				}
			}
		}
		if len(orphanIDs) > 0 {
			if _, err := tx.Exec(ctx, "UPDATE note_nodes SET deleted_at = NOW() WHERE id = ANY($1) AND deleted_at IS NULL", orphanIDs); err != nil {
				return fmt.Errorf("soft-delete orphan nodes: %w", err)
			}
		}
	}

	if tasksMap := doc.GetMap("tasks"); tasksMap != nil {
		var defaultUserID pgtype.UUID
		if err := tx.QueryRow(ctx, "SELECT user_id FROM notes WHERE id = $1", noteUUID).Scan(&defaultUserID); err != nil {
			if !errors.Is(err, pgx.ErrNoRows) {
				return fmt.Errorf("get note owner: %w", err)
			}
		}

		for _, key := range tasksMap.Keys() {
			raw, ok := tasksMap.Get(key)
			if !ok || raw == nil {
				continue
			}
			taskStr, ok := raw.(string)
			if !ok {
				continue
			}
			var td taskJSON
			if err := json.Unmarshal([]byte(taskStr), &td); err != nil {
				continue
			}

			pgTaskID, err := parseUUIDStr(td.ID)
			if err != nil {
				continue
			}

			userID := defaultUserID
			if td.UserID != "" {
				if parsed, err := parseUUIDStr(td.UserID); err == nil {
					userID = parsed
				}
			}

			var dueDate pgtype.Date
			if td.DueDate != "" {
				t, err := time.Parse("2006-01-02", td.DueDate)
				if err == nil {
					dueDate = pgtype.Date{Time: t, Valid: true}
				}
			}

			var recurrence pgtype.Text
			if td.Recurrence != "" {
				recurrence = pgtype.Text{String: td.Recurrence, Valid: true}
			}

			createdAt := msToTimestamptz(td.CreatedAt)
			if !createdAt.Valid {
				createdAt = pgtype.Timestamptz{Time: time.Now(), Valid: true}
			}

			params := sqlcgen.UpsertTaskParams{
				ID:          pgTaskID,
				UserID:      userID,
				NoteID:      noteUUID,
				Title:       td.Title,
				Status:      td.Status,
				Position:    td.Position,
				Recurrence:  recurrence,
				DueDate:     dueDate,
				CompletedAt: msToTimestamptz(td.CompletedAt),
				CreatedAt:   createdAt,
				DeletedAt:   pgtype.Timestamptz{Valid: false},
			}
			if _, err := q.UpsertTask(ctx, params); err != nil {
				return fmt.Errorf("upsert task %s: %w", key, err)
			}
		}

		// Soft-delete tasks removed from the YMap.
		orphanTaskRows, err := tx.Query(ctx, "SELECT id FROM tasks WHERE note_id = $1 AND deleted_at IS NULL", noteUUID)
		if err != nil {
			return fmt.Errorf("query active task ids: %w", err)
		}
		var existingTaskIDs []string
		for orphanTaskRows.Next() {
			var id string
			if err := orphanTaskRows.Scan(&id); err != nil {
				orphanTaskRows.Close()
				return fmt.Errorf("scan orphan task id: %w", err)
			}
			existingTaskIDs = append(existingTaskIDs, id)
		}
		orphanTaskRows.Close()

		activeTaskIDs := make(map[string]bool, len(tasksMap.Keys()))
		for _, key := range tasksMap.Keys() {
			activeTaskIDs[key] = true
		}
		var orphanTaskIDs []pgtype.UUID
		for _, id := range existingTaskIDs {
			if !activeTaskIDs[id] {
				parsed, err := parseUUIDStr(id)
				if err == nil {
					orphanTaskIDs = append(orphanTaskIDs, parsed)
				}
			}
		}
		if len(orphanTaskIDs) > 0 {
			if _, err := tx.Exec(ctx, "UPDATE tasks SET deleted_at = NOW() WHERE id = ANY($1) AND deleted_at IS NULL", orphanTaskIDs); err != nil {
				return fmt.Errorf("soft-delete orphan tasks: %w", err)
			}
		}
	}

	return nil
}

func ReconstructYDocFromNodes(ctx context.Context, pool *pgxpool.Pool, noteID string) ([]byte, error) {
	startTotal := time.Now()
	noteUUID, err := parseUUIDStr(noteID)
	if err != nil {
		return nil, fmt.Errorf("parse note id: %w", err)
	}

	q := sqlcgen.New(pool)

	startNodes := time.Now()
	nodes, err := q.GetNodesByNoteId(ctx, noteUUID)
	if err != nil {
		slog.Error("ReconstructYDocFromNodes: query nodes failed", "note_id", noteID, "error", err, "elapsed_ms", time.Since(startNodes).Milliseconds())
		return nil, fmt.Errorf("query nodes: %w", err)
	}
	slog.Info("ReconstructYDocFromNodes: nodes loaded", "note_id", noteID, "count", len(nodes), "elapsed_ms", time.Since(startNodes).Milliseconds())

	startTasks := time.Now()
	rows, err := pool.Query(ctx, `SELECT id, note_id, user_id, title, status, due_date, recurrence, position, created_at, updated_at, deleted_at, completed_at, node_id FROM tasks WHERE note_id = $1 AND deleted_at IS NULL ORDER BY position ASC, created_at ASC`, noteUUID)
	if err != nil {
		slog.Error("ReconstructYDocFromNodes: query tasks failed", "note_id", noteID, "error", err, "elapsed_ms", time.Since(startTasks).Milliseconds())
		return nil, fmt.Errorf("query tasks: %w", err)
	}
	defer rows.Close()
	slog.Info("ReconstructYDocFromNodes: tasks queried", "note_id", noteID, "elapsed_ms", time.Since(startTasks).Milliseconds())

	var tasks []sqlcgen.Task
	for rows.Next() {
		var t sqlcgen.Task
		if err := rows.Scan(
			&t.ID, &t.NoteID, &t.UserID, &t.Title, &t.Status,
			&t.DueDate, &t.Recurrence, &t.Position,
			&t.CreatedAt, &t.UpdatedAt, &t.DeletedAt,
			&t.CompletedAt, &t.NodeID,
		); err != nil {
			return nil, fmt.Errorf("scan task: %w", err)
		}
		tasks = append(tasks, t)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("rows iter: %w", err)
	}

	doc := crdt.New(crdt.WithGC(false))
	nodesMap := doc.GetMap("nodes")
	tasksMap := doc.GetMap("tasks")

	// Build a taskStatusMap from the queried tasks
	taskStatusMap := make(map[string]string)
	for _, t := range tasks {
		if t.NodeID.Valid {
			taskStatusMap[uuidToStr(t.NodeID)] = t.Status
		}
	}

	// Pre-create/retrieve YText types outside transaction to avoid CGO deadlock
	textTypes := make(map[string]*crdt.YText)
	for _, node := range nodes {
		nodeID := uuidToStr(node.ID)
		nodeData := node.Data
		if node.Type == "task" {
			if status, ok := taskStatusMap[nodeID]; ok {
				var dataMap map[string]interface{}
				if err := json.Unmarshal(node.Data, &dataMap); err == nil {
					dataMap["completed"] = (status == "done")
					if updatedBytes, err := json.Marshal(dataMap); err == nil {
						nodeData = updatedBytes
					}
				}
			}
		}
		if len(nodeData) > 0 {
			var dataMap map[string]interface{}
			if err := json.Unmarshal(nodeData, &dataMap); err == nil {
				if text, ok := dataMap["text"].(string); ok && text != "" {
					textTypes[nodeID] = doc.GetText("content/" + nodeID)
				}
			}
		}
	}

	doc.Transact(func(txn *crdt.Transaction) {
		for _, node := range nodes {
			nodeID := uuidToStr(node.ID)
			nodeData := node.Data
			if node.Type == "task" {
				if status, ok := taskStatusMap[nodeID]; ok {
					var dataMap map[string]interface{}
					if err := json.Unmarshal(node.Data, &dataMap); err == nil {
						dataMap["completed"] = (status == "done")
						if updatedBytes, err := json.Marshal(dataMap); err == nil {
							nodeData = updatedBytes
						}
					}
				}
			}

			nd := noteNodeJSON{
				ID:        nodeID,
				ParentID:  uuidToStr(node.ParentID),
				Position:  node.Position,
				Type:      node.Type,
				Data:      nodeData,
				CreatedAt: timestamptzToMS(node.CreatedAt),
				UpdatedAt: timestamptzToMS(node.UpdatedAt),
			}
			b, err := json.Marshal(nd)
			if err != nil {
				continue
			}
			nodesMap.Set(txn, nodeID, string(b))

			if textType, ok := textTypes[nodeID]; ok {
				var dataMap map[string]interface{}
				if err := json.Unmarshal(nodeData, &dataMap); err == nil {
					if text, ok := dataMap["text"].(string); ok && text != "" {
						textType.Insert(txn, 0, text, nil)
					}
				}
			}
		}

		for _, t := range tasks {
			td := taskJSON{
				ID:          uuidToStr(t.ID),
				NoteID:      uuidToStr(t.NoteID),
				UserID:      uuidToStr(t.UserID),
				Title:       t.Title,
				Status:      t.Status,
				Position:    t.Position,
				CreatedAt:   timestamptzToMS(t.CreatedAt),
				CompletedAt: timestamptzToMS(t.CompletedAt),
			}
			if t.DueDate.Valid {
				td.DueDate = t.DueDate.Time.Format("2006-01-02")
			}
			if t.Recurrence.Valid {
				td.Recurrence = t.Recurrence.String
			}
			b, err := json.Marshal(td)
			if err != nil {
				continue
			}
			tasksMap.Set(txn, uuidToStr(t.ID), string(b))
		}
	})

	result := crdt.EncodeStateAsUpdateV1(doc, nil)
	slog.Info("ReconstructYDocFromNodes: done", "note_id", noteID, "result_bytes", len(result), "total_ms", time.Since(startTotal).Milliseconds())
	return result, nil
}

func validateNoteID(noteID string) error {
	_, err := parseUUIDStr(noteID)
	if err != nil {
		return fmt.Errorf("parse note id: %w", err)
	}
	return nil
}

// LoadYDocState loads the Yjs document state for a note from the database.
// It prefers the compacted snapshot from note_yjs_states + pending updates,
// falling back to ReconstructYDocFromNodes when no snapshot exists yet.
// Returns nil, nil if pool is nil (used in tests).
func LoadYDocState(ctx context.Context, pool *pgxpool.Pool, noteID string) ([]byte, error) {
	if pool == nil {
		return nil, nil
	}
	startTotal := time.Now()
	if err := validateNoteID(noteID); err != nil {
		return nil, err
	}

	noteUUID, err := parseUUIDStr(noteID)

	startQuery := time.Now()
	var state []byte
	err = pool.QueryRow(ctx, "SELECT state FROM note_yjs_states WHERE note_id = $1", noteUUID).Scan(&state)
	queryElapsed := time.Since(startQuery)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			slog.Info("LoadYDocState: no snapshot, reconstructing", "note_id", noteID, "query_ms", queryElapsed.Milliseconds())
			state, err = ReconstructYDocFromNodes(ctx, pool, noteID)
			if err != nil {
				return nil, err
			}
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
	all := append([][]byte{state}, pending...)
	merged, err := crdt.MergeUpdatesV1(all...)
	if err != nil {
		slog.Error("LoadYDocState: merge failed", "note_id", noteID, "error", err, "elapsed_ms", time.Since(startMerge).Milliseconds())
		return nil, fmt.Errorf("merge pending updates: %w", err)
	}
	slog.Info("LoadYDocState: done (merged)", "note_id", noteID, "merged_bytes", len(merged), "merge_ms", time.Since(startMerge).Milliseconds(), "total_ms", time.Since(startTotal).Milliseconds())
	return merged, nil
}
