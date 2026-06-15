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
		wantDate   time.Time
	}{
		{name: "daily", from: time.Date(2026, 6, 15, 0, 0, 0, 0, time.UTC), recurrence: "daily", wantNext: true, wantDate: time.Date(2026, 6, 16, 0, 0, 0, 0, time.UTC)},
		{name: "weekdays_thursday", from: time.Date(2026, 6, 18, 0, 0, 0, 0, time.UTC), recurrence: "weekdays", wantNext: true, wantDate: time.Date(2026, 6, 19, 0, 0, 0, 0, time.UTC)},
		{name: "weekdays_friday", from: time.Date(2026, 6, 19, 0, 0, 0, 0, time.UTC), recurrence: "weekdays", wantNext: true, wantDate: time.Date(2026, 6, 22, 0, 0, 0, 0, time.UTC)},
		{name: "weekdays_saturday", from: time.Date(2026, 6, 20, 0, 0, 0, 0, time.UTC), recurrence: "weekdays", wantNext: true, wantDate: time.Date(2026, 6, 22, 0, 0, 0, 0, time.UTC)},
		{name: "weekly", from: time.Date(2026, 6, 15, 0, 0, 0, 0, time.UTC), recurrence: "weekly", wantNext: true, wantDate: time.Date(2026, 6, 22, 0, 0, 0, 0, time.UTC)},
		{name: "monthly", from: time.Date(2026, 6, 15, 0, 0, 0, 0, time.UTC), recurrence: "monthly", wantNext: true, wantDate: time.Date(2026, 7, 15, 0, 0, 0, 0, time.UTC)},
		{name: "empty_recurrence", from: time.Date(2026, 6, 15, 0, 0, 0, 0, time.UTC), recurrence: "", wantNext: false},
		{name: "invalid_recurrence", from: time.Date(2026, 6, 15, 0, 0, 0, 0, time.UTC), recurrence: "unknown", wantNext: false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, ok := calculateNextDueDate(tt.from, tt.recurrence)
			if tt.wantNext && !ok {
				t.Errorf("calculateNextDueDate(%v, %q) = (_, %v), want (_, true)", tt.from, tt.recurrence, ok)
			}
			if !tt.wantNext && ok {
				t.Errorf("calculateNextDueDate(%v, %q) = (_, %v), want (_, false)", tt.from, tt.recurrence, ok)
			}
			if tt.wantNext && !got.Equal(tt.wantDate) {
				t.Errorf("calculateNextDueDate(%v, %q) = (%v, _), want (%v, _)", tt.from, tt.recurrence, got, tt.wantDate)
			}
		})
	}
}
