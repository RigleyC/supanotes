package sync

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/reearth/ygo/crdt"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

const dueDateLayout = "2006-01-02"

func parseDueDate(s string) (time.Time, error) {
	t, err := time.Parse(dueDateLayout, s)
	if err != nil {
		return time.Time{}, fmt.Errorf("invalid due_date %q: expected YYYY-MM-DD", s)
	}
	return t, nil
}

func formatDate(d pgtype.Date) *string {
	if !d.Valid {
		return nil
	}
	s := d.Time.Format(dueDateLayout)
	return &s
}

func formatText(t pgtype.Text) *string {
	if !t.Valid {
		return nil
	}
	s := t.String
	return &s
}

// SyncTask is the wire shape of a task in the sync payload.
// Differs from sqlcgen.Task in that due_date is formatted as YYYY-MM-DD
// (a calendar date, not a timestamp).
type SyncTask struct {
	ID          pgtype.UUID `json:"id"`
	NoteID      pgtype.UUID `json:"note_id"`
	UserID      pgtype.UUID `json:"user_id"`
	Title       string      `json:"title"`
	Status      string      `json:"status"`
	Position    string      `json:"position"`
	Recurrence  *string     `json:"recurrence"`
	DueDate     *string     `json:"due_date"`
	CompletedAt *time.Time  `json:"completed_at"`
	CreatedAt   time.Time   `json:"created_at"`
	UpdatedAt   time.Time   `json:"updated_at"`
	DeletedAt   *time.Time  `json:"deleted_at"`
}

func toSyncTask(t sqlcgen.Task) SyncTask {
	st := SyncTask{
		ID:        t.ID,
		NoteID:    t.NoteID,
		UserID:    t.UserID,
		Title:     t.Title,
		Status:    t.Status,
		Position:  t.Position,
		CreatedAt: t.CreatedAt.Time,
		UpdatedAt: t.UpdatedAt.Time,
	}
	if rec := formatText(t.Recurrence); rec != nil {
		st.Recurrence = rec
	}
	if due := formatDate(t.DueDate); due != nil {
		st.DueDate = due
	}
	if t.CompletedAt.Valid {
		ct := t.CompletedAt.Time
		st.CompletedAt = &ct
	}
	if t.DeletedAt.Valid {
		dt := t.DeletedAt.Time
		st.DeletedAt = &dt
	}
	return st
}

// UserNotePreferencePayload is the wire shape of a user note preference
// in the sync payload. It uses string for Filters instead of []byte to
// avoid base64 encoding issues with the sqlcgen type.
type UserNotePreferencePayload struct {
	UserID        pgtype.UUID        `json:"user_id"`
	NoteID        pgtype.UUID        `json:"note_id"`
	HideCompleted bool               `json:"hide_completed"`
	Filters       string             `json:"filters"`
	Favorite      bool               `json:"favorite"`
	Archived      bool               `json:"archived"`
	CreatedAt     pgtype.Timestamptz `json:"created_at"`
	UpdatedAt     pgtype.Timestamptz `json:"updated_at"`
}

func toUserNotePreferencePayload(p sqlcgen.UserNotePreference) UserNotePreferencePayload {
	return UserNotePreferencePayload{
		UserID:        p.UserID,
		NoteID:        p.NoteID,
		HideCompleted: p.HideCompleted,
		Filters:       string(p.Filters),
		Favorite:      p.Favorite,
		Archived:      p.Archived,
		CreatedAt:     p.CreatedAt,
		UpdatedAt:     p.UpdatedAt,
	}
}

func fromUserNotePreferencePayload(p UserNotePreferencePayload) sqlcgen.UpsertUserNotePreferenceParams {
	return sqlcgen.UpsertUserNotePreferenceParams{
		UserID:        p.UserID,
		NoteID:        p.NoteID,
		HideCompleted: p.HideCompleted,
		Filters:       []byte(p.Filters),
		Favorite:      p.Favorite,
		Archived:      p.Archived,
		CreatedAt:     p.CreatedAt,
	}
}

func fromSyncTask(t SyncTask) (sqlcgen.Task, error) {
	out := sqlcgen.Task{
		ID:        t.ID,
		NoteID:    t.NoteID,
		UserID:    t.UserID,
		Title:     t.Title,
		Status:    t.Status,
		Position:  t.Position,
		CreatedAt: pgtype.Timestamptz{Time: t.CreatedAt, Valid: true},
		UpdatedAt: pgtype.Timestamptz{Time: t.UpdatedAt, Valid: true},
	}
	if t.Recurrence != nil {
		out.Recurrence = pgtype.Text{String: *t.Recurrence, Valid: true}
	}
	if t.DueDate != nil {
		d, err := parseDueDate(*t.DueDate)
		if err != nil {
			return sqlcgen.Task{}, err
		}
		out.DueDate = pgtype.Date{Time: d, Valid: true}
	}
	if t.CompletedAt != nil {
		out.CompletedAt = pgtype.Timestamptz{Time: *t.CompletedAt, Valid: true}
	}
	if t.DeletedAt != nil {
		out.DeletedAt = pgtype.Timestamptz{Time: *t.DeletedAt, Valid: true}
	}
	return out, nil
}

// ProduceUpdateFromRows serializes incoming REST Push note_nodes + tasks into a
// single Yjs update blob suitable for IngestUpdate. This is the only path by
// which legacy REST Push can mutate note content.
func ProduceUpdateFromRows(
	ctx context.Context,
	pool *pgxpool.Pool,
	noteID string,
	nodes []sqlcgen.NoteNode,
	tasks []SyncTask,
) ([]byte, error) {
	state, err := LoadYDocState(ctx, pool, noteID)
	if err != nil {
		return nil, fmt.Errorf("load ydoc state: %w", err)
	}

	doc := crdt.New(crdt.WithGC(false))
	if len(state) > 0 {
		if err := crdt.ApplyUpdateV1(doc, state, nil); err != nil {
			return nil, fmt.Errorf("apply existing ydoc state: %w", err)
		}
	}

	nodesMap := doc.GetMap("nodes")

	// Build a map of task properties from the REST tasks slice
	restTaskMap := make(map[string]SyncTask)
	for _, t := range tasks {
		tID := uuid.UUID(t.ID.Bytes).String()
		restTaskMap[tID] = t
	}

	// Pre-create/retrieve YText types and their contents outside transaction to avoid deadlock
	textTypes := make(map[string]*crdt.YText)
	oldTexts := make(map[string]string)
	for _, n := range nodes {
		if !n.DeletedAt.Valid {
			nID := uuid.UUID(n.ID.Bytes).String()
			ytext := doc.GetText("content/" + nID)
			textTypes[nID] = ytext
			oldTexts[nID] = ytext.ToString()
		}
	}

	doc.Transact(func(txn *crdt.Transaction) {
		for _, n := range nodes {
			nID := uuid.UUID(n.ID.Bytes).String()
			if n.DeletedAt.Valid {
				nodesMap.Delete(txn, nID)
				continue
			}

			nodeData := n.Data
			if n.Type == "task" {
				if t, ok := restTaskMap[nID]; ok {
					var dataMap map[string]interface{}
					if len(n.Data) > 0 {
						json.Unmarshal(n.Data, &dataMap)
					}
					if dataMap == nil {
						dataMap = make(map[string]interface{})
					}
					dataMap["completed"] = (t.Status == "done")
					if t.DueDate != nil {
						dataMap["dueDate"] = *t.DueDate
					} else {
						delete(dataMap, "dueDate")
					}
					if t.Recurrence != nil {
						dataMap["recurrence"] = *t.Recurrence
					} else {
						delete(dataMap, "recurrence")
					}
					if updatedBytes, err := json.Marshal(dataMap); err == nil {
						nodeData = updatedBytes
					}
				}
			}

			nd := noteNodeJSON{
				ID:        nID,
				ParentID:  uuidToStr(n.ParentID),
				Position:  n.Position,
				Type:      n.Type,
				Data:      nodeData,
				CreatedAt: timestamptzToMS(n.CreatedAt),
			}
			b, _ := json.Marshal(nd)
			nodesMap.Set(txn, nID, string(b))

			// Populate YText for the node's text content
			if len(nodeData) > 0 {
				var dataMap map[string]interface{}
				if err := json.Unmarshal(nodeData, &dataMap); err == nil {
					if text, ok := dataMap["text"].(string); ok {
						if textType, ok := textTypes[nID]; ok {
							updateYTextIncrementally(txn, textType, oldTexts[nID], text)
						}
					}
				}
			}
		}
	})

	return crdt.EncodeStateAsUpdateV1(doc, nil), nil
}

func updateYTextIncrementally(txn *crdt.Transaction, ytext *crdt.YText, oldText string, newText string) {
	if oldText == newText {
		return
	}

	oldRunes := []rune(oldText)
	newRunes := []rune(newText)

	start := 0
	oldEnd := len(oldRunes)
	newEnd := len(newRunes)

	// Find common prefix
	for start < oldEnd && start < newEnd && oldRunes[start] == newRunes[start] {
		start++
	}

	// Find common suffix
	for oldEnd > start && newEnd > start && oldRunes[oldEnd-1] == newRunes[newEnd-1] {
		oldEnd--
		newEnd--
	}

	// Delete deleted characters
	deleteLen := oldEnd - start
	if deleteLen > 0 {
		ytext.Delete(txn, start, deleteLen)
	}

	// Insert inserted characters
	if newEnd > start {
		insertText := string(newRunes[start:newEnd])
		ytext.Insert(txn, start, insertText, nil)
	}
}
