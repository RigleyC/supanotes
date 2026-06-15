package sync

import (
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

// SyncTask is the wire shape of a task in the sync payload.
// Differs from sqlcgen.Task in that due_date is formatted as YYYY-MM-DD
// (a calendar date, not a timestamp).
type SyncTask struct {
	ID          pgtype.UUID `json:"id"`
	NoteID      pgtype.UUID `json:"note_id"`
	UserID      pgtype.UUID `json:"user_id"`
	Title       string      `json:"title"`
	Status      string      `json:"status"`
	Position    int32       `json:"position"`
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
	if t.Recurrence.Valid {
		r := t.Recurrence.String
		st.Recurrence = &r
	}
	if t.DueDate.Valid {
		d := t.DueDate.Time.Format("2006-01-02")
		st.DueDate = &d
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
		d, err := time.Parse("2006-01-02", *t.DueDate)
		if err != nil {
			return sqlcgen.Task{}, fmt.Errorf("invalid due_date %q: expected YYYY-MM-DD", *t.DueDate)
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
