package tasks

import (
	"regexp"

	"github.com/jackc/pgx/v5/pgtype"
)

var (
	canonicalWallClockPattern  = regexp.MustCompile(`^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.(?:[0-9]{3}|[0-9]{6})$`)
	canonicalUTCInstantPattern = regexp.MustCompile(`^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.(?:[0-9]{3}|[0-9]{6})Z$`)
)

var canonicalRecurrenceRules = map[string]bool{
	"daily": true, "weekdays": true, "weekly": true, "monthly": true,
}

var canonicalReminders = map[string]bool{
	"at_time": true, "5m_before": true, "1h_before": true, "1d_before": true,
	"9am": true, "12pm": true, "6pm": true, "1d_before_9am": true,
}

// IsCanonicalRecurrenceRule and IsCanonicalReminder are the shared wire rules
// for independent Task values and document TaskNode metadata.
func IsCanonicalRecurrenceRule(value string) bool { return canonicalRecurrenceRules[value] }
func IsCanonicalReminder(value string) bool       { return canonicalReminders[value] }

// ValidScheduleMetadata makes the no-due-date case explicit: a task without
// an anchor cannot carry recurrence or reminder metadata.
func ValidScheduleMetadata(hasDueDate bool, recurrenceRule, reminder *string) bool {
	return hasDueDate || (recurrenceRule == nil && reminder == nil)
}

func validateTaskSchedule(dueDate pgtype.Timestamp, hasTime bool, recurrence, reminder pgtype.Text) error {
	if dueDate.Valid && !hasTime && !isMidnight(dueDate.Time) {
		return ErrInvalidMutation
	}
	var recurrenceValue, reminderValue *string
	if recurrence.Valid {
		recurrenceValue = &recurrence.String
	}
	if reminder.Valid {
		reminderValue = &reminder.String
	}
	if !ValidScheduleMetadata(dueDate.Valid, recurrenceValue, reminderValue) {
		return ErrInvalidMutation
	}
	return nil
}
