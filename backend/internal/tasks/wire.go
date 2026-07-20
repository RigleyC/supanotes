package tasks

import (
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgtype"
)

const dueDateLayout = "2006-01-02"

// ParseDueDate parses a calendar date or RFC3339 timestamp. It is the shared
// parser used by both the REST handlers (handler.go) and the sync
// push loop (sync/sync_task.go) so the error message stays in one
// place.
func ParseDueDate(s string) (time.Time, error) {
	if timestamp, err := time.Parse(time.RFC3339, s); err == nil {
		return timestamp, nil
	}
	t, err := time.Parse(dueDateLayout, s)
	if err != nil {
		return time.Time{}, fmt.Errorf("invalid due_date %q: expected YYYY-MM-DD or RFC3339", s)
	}
	return t, nil
}

// FormatDate formats a pgtype.Date as YYYY-MM-DD, returning nil when
// the value is SQL NULL. Used by both TaskResponse (REST) and SyncTask.
func FormatDate(d pgtype.Timestamptz) *string {
	if !d.Valid {
		return nil
	}
	s := d.Time.Format(time.RFC3339)
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
