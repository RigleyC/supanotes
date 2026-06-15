package routines

import (
	"testing"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/stretchr/testify/assert"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

func TestDaysAndTimeToCron(t *testing.T) {
	tests := []struct {
		daysOfWeek string
		timeOfDay  string
		want       string
	}{
		{daysOfWeek: "mon,wed,fri", timeOfDay: "09:30", want: "30 09 * * 1,3,5"},
		{daysOfWeek: "mon,tue,wed,thu,fri", timeOfDay: "08:00", want: "00 08 * * 1,2,3,4,5"},
		{daysOfWeek: "sat,sun", timeOfDay: "10:15", want: "15 10 * * 6,0"},
		{daysOfWeek: "mon", timeOfDay: "00:00", want: "00 00 * * 1"},
		{daysOfWeek: "mon,wed,fri", timeOfDay: "09:30", want: "30 09 * * 1,3,5"},
	}

	for _, tt := range tests {
		got := daysAndTimeToCron(tt.daysOfWeek, tt.timeOfDay)
		assert.Equal(t, tt.want, got, "daysAndTimeToCron(%q, %q)", tt.daysOfWeek, tt.timeOfDay)
	}
}

func TestCronToDaysAndTime(t *testing.T) {
	tests := []struct {
		cronExpr      string
		wantDays      string
		wantTime      string
	}{
		{cronExpr: "30 9 * * 1,3,5", wantDays: "mon,wed,fri", wantTime: "9:30"},
		{	cronExpr: "0 8 * * 1,2,3,4,5", wantDays: "mon,tue,wed,thu,fri", wantTime: "8:0"},
		{cronExpr: "15 10 * * 0,6", wantDays: "sun,sat", wantTime: "10:15"},
		{cronExpr: "short", wantDays: "", wantTime: ""},
	}

	for _, tt := range tests {
		gotDays, gotTime := cronToDaysAndTime(tt.cronExpr)
		assert.Equal(t, tt.wantDays, gotDays, "cronToDaysAndTime(%q) days", tt.cronExpr)
		assert.Equal(t, tt.wantTime, gotTime, "cronToDaysAndTime(%q) time", tt.cronExpr)
	}
}

func TestRoutineToResponse(t *testing.T) {
	r := sqlcgen.Routine{
		ID:        pgtype.UUID{Bytes: [16]byte{1}, Valid: true},
		UserID:    pgtype.UUID{Bytes: [16]byte{2}, Valid: true},
		Type:      "daily",
		CronExpr:  "0 8 * * 1,2,3,4,5",
		Enabled:   true,
		Name:      "Daily Brief",
		BriefType: "daily",
	}

	resp := routineToResponse(r)
	assert.Equal(t, "mon,tue,wed,thu,fri", resp.DaysOfWeek)
	assert.Equal(t, "8:0", resp.TimeOfDay)
	assert.Equal(t, "daily", resp.Type)
	assert.True(t, resp.Enabled)
	assert.Equal(t, "Daily Brief", resp.Name)
}

func TestBriefPreview(t *testing.T) {
	short := "short text"
	assert.Equal(t, short, briefPreview(short))

	long := ""
	for i := 0; i < 300; i++ {
		long += "x"
	}
	preview := briefPreview(long)
	assert.Equal(t, 202, len(preview))
	assert.Contains(t, preview, "…")
	assert.Equal(t, long[:199], preview[:199])
}
