package tasks

import (
	"testing"
	"time"
)

func TestCalculateNextDueDate(t *testing.T) {
	tests := []struct {
		name       string
		from       time.Time
		recurrence string
		wantNext   bool
	}{
		{name: "daily", from: time.Date(2026, 6, 15, 0, 0, 0, 0, time.UTC), recurrence: "daily", wantNext: true},
		{name: "weekdays_friday", from: time.Date(2026, 6, 19, 0, 0, 0, 0, time.UTC), recurrence: "weekdays", wantNext: true},
		{name: "weekly", from: time.Date(2026, 6, 15, 0, 0, 0, 0, time.UTC), recurrence: "weekly", wantNext: true},
		{name: "monthly", from: time.Date(2026, 6, 15, 0, 0, 0, 0, time.UTC), recurrence: "monthly", wantNext: true},
		{name: "empty_recurrence", from: time.Date(2026, 6, 15, 0, 0, 0, 0, time.UTC), recurrence: "", wantNext: false},
		{name: "invalid_recurrence", from: time.Date(2026, 6, 15, 0, 0, 0, 0, time.UTC), recurrence: "unknown", wantNext: false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, ok := calculateNextDueDate(tt.from, tt.recurrence)
			if tt.wantNext && !ok {
				t.Errorf("calculateNextDueDate(%v, %q) = (_, %v), want (_, true)", tt.from, tt.recurrence, ok)
			}
			if !tt.wantNext && ok {
				t.Errorf("calculateNextDueDate(%v, %q) = (_, %v), want (_, false)", tt.from, tt.recurrence, ok)
			}
		})
	}
}
