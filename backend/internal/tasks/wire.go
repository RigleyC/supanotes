package tasks

import (
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgtype"
)

const dueDateLayout = "2006-01-02"

// ParseDueDate parses a YYYY-MM-DD calendar date. It is the shared
// parser used by both the REST handlers (handler.go) and the sync
// push loop (sync/sync_task.go) so the error message stays in one
// place.
func ParseDueDate(s string) (time.Time, error) {
	t, err := time.Parse(dueDateLayout, s)
	if err != nil {
		return time.Time{}, fmt.Errorf("invalid due_date %q: expected YYYY-MM-DD", s)
	}
	return t, nil
}

// FormatDate formats a pgtype.Date as YYYY-MM-DD, returning nil when
// the value is SQL NULL. Used by both TaskResponse (REST) and SyncTask.
func FormatDate(d pgtype.Date) *string {
	if !d.Valid {
		return nil
	}
	s := d.Time.Format(dueDateLayout)
	return &s
}

// FormatText returns the Text payload as a *string, or nil when
// the value is SQL NULL. Used by both TaskResponse (REST) and SyncTask
// for the optional recurrence field.
func FormatText(t pgtype.Text) *string {
	if !t.Valid {
		return nil
	}
	s := t.String
	return &s
}
