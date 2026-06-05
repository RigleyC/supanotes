package tasks

import (
	"testing"
	"time"
)

func TestCalculateNextDueDate(t *testing.T) {
	tests := []struct {
		name       string
		current    time.Time
		recurrence string
		want       time.Time
	}{
		{
			name:       "daily",
			current:    time.Date(2026, 6, 4, 10, 0, 0, 0, time.UTC), // Thursday
			recurrence: "daily",
			want:       time.Date(2026, 6, 5, 10, 0, 0, 0, time.UTC), // Friday
		},
		{
			name:       "weekdays - Thursday to Friday",
			current:    time.Date(2026, 6, 4, 10, 0, 0, 0, time.UTC), // Thursday
			recurrence: "weekdays",
			want:       time.Date(2026, 6, 5, 10, 0, 0, 0, time.UTC), // Friday
		},
		{
			name:       "weekdays - Friday to Monday",
			current:    time.Date(2026, 6, 5, 10, 0, 0, 0, time.UTC), // Friday
			recurrence: "weekdays",
			want:       time.Date(2026, 6, 8, 10, 0, 0, 0, time.UTC), // Monday
		},
		{
			name:       "weekdays - Saturday to Monday",
			current:    time.Date(2026, 6, 6, 10, 0, 0, 0, time.UTC), // Saturday
			recurrence: "weekdays",
			want:       time.Date(2026, 6, 8, 10, 0, 0, 0, time.UTC), // Monday
		},
		{
			name:       "weekly",
			current:    time.Date(2026, 6, 4, 10, 0, 0, 0, time.UTC),
			recurrence: "weekly",
			want:       time.Date(2026, 6, 11, 10, 0, 0, 0, time.UTC),
		},
		{
			name:       "monthly",
			current:    time.Date(2026, 6, 4, 10, 0, 0, 0, time.UTC),
			recurrence: "monthly",
			want:       time.Date(2026, 7, 4, 10, 0, 0, 0, time.UTC),
		},
		{
			name:       "unsupported recurrence returns current date",
			current:    time.Date(2026, 6, 4, 10, 0, 0, 0, time.UTC),
			recurrence: "yearly",
			want:       time.Date(2026, 6, 4, 10, 0, 0, 0, time.UTC),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := calculateNextDueDate(tt.current, tt.recurrence)
			if !got.Equal(tt.want) {
				t.Errorf("calculateNextDueDate() = %v, want %v", got, tt.want)
			}
		})
	}
}
