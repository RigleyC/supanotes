package sync

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
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

func ProjectToDB(ctx context.Context, pool *pgxpool.Pool, noteID string, update []byte) error {
	tx, err := pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx, "SELECT pg_advisory_xact_lock(hashtext($1::text), hashtext('nodes'))", noteID); err != nil {
		return fmt.Errorf("advisory lock: %w", err)
	}

	doc := crdt.New(crdt.WithGC(false))
	if err := crdt.ApplyUpdateV1(doc, update, nil); err != nil {
		return fmt.Errorf("apply update: %w", err)
	}

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

			params := sqlcgen.UpsertNoteNodeParams{
				ID:        pgNodeID,
				NoteID:    noteUUID,
				ParentID:  parentID,
				Position:  nd.Position,
				Type:      nd.Type,
				Data:      dataBytes,
				CreatedAt: msToTimestamptz(nd.CreatedAt),
				DeletedAt: pgtype.Timestamptz{Valid: false},
			}
			if _, err := q.UpsertNoteNode(ctx, params); err != nil {
				return fmt.Errorf("upsert node %s: %w", key, err)
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

			params := sqlcgen.UpsertTaskParams{
				ID:         pgTaskID,
				UserID:     userID,
				NoteID:     noteUUID,
				Title:      td.Title,
				Status:     td.Status,
				Position:   td.Position,
				Recurrence: recurrence,
				DueDate:    dueDate,
				CreatedAt:  msToTimestamptz(td.CreatedAt),
				DeletedAt:  pgtype.Timestamptz{Valid: false},
			}
			if _, err := q.UpsertTask(ctx, params); err != nil {
				return fmt.Errorf("upsert task %s: %w", key, err)
			}
		}
	}

	return tx.Commit(ctx)
}

func ReconstructYDocFromNodes(ctx context.Context, pool *pgxpool.Pool, noteID string) ([]byte, error) {
	noteUUID, err := parseUUIDStr(noteID)
	if err != nil {
		return nil, fmt.Errorf("parse note id: %w", err)
	}

	q := sqlcgen.New(pool)

	nodes, err := q.GetNodesByNoteId(ctx, noteUUID)
	if err != nil {
		return nil, fmt.Errorf("query nodes: %w", err)
	}

	rows, err := pool.Query(ctx, `SELECT id, note_id, user_id, title, status, due_date, recurrence, position, created_at, updated_at, deleted_at, completed_at, node_id FROM tasks WHERE note_id = $1 AND deleted_at IS NULL ORDER BY position ASC, created_at ASC`, noteUUID)
	if err != nil {
		return nil, fmt.Errorf("query tasks: %w", err)
	}
	defer rows.Close()

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

	doc.Transact(func(txn *crdt.Transaction) {
		for _, node := range nodes {
			nd := noteNodeJSON{
				ID:        uuidToStr(node.ID),
				ParentID:  uuidToStr(node.ParentID),
				Position:  node.Position,
				Type:      node.Type,
				Data:      node.Data,
				CreatedAt: timestamptzToMS(node.CreatedAt),
				UpdatedAt: timestamptzToMS(node.UpdatedAt),
			}
			b, err := json.Marshal(nd)
			if err != nil {
				continue
			}
			nodesMap.Set(txn, uuidToStr(node.ID), string(b))
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

	return crdt.EncodeStateAsUpdateV1(doc, nil), nil
}
