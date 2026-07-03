package sync

import (
	"time"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/tasks"
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
	Position    float64     `json:"position"`
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
	if rec := tasks.FormatText(t.Recurrence); rec != nil {
		st.Recurrence = rec
	}
	if due := tasks.FormatDate(t.DueDate); due != nil {
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
		d, err := tasks.ParseDueDate(*t.DueDate)
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
