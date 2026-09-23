package tasks

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgtype"
)

// Mutation parsing is kept separate from persistence and transaction orchestration.
type taskPatch struct {
	title          string
	hasTitle       bool
	dueDate        pgtype.Timestamp
	hasDueDate     bool
	hasTime        bool
	hasHasTime     bool
	recurrenceRule pgtype.Text
	hasRecurrence  bool
	reminder       pgtype.Text
	hasReminder    bool
	completions    map[string]string
	hasCompletions bool
	isCompleted    bool
	hasIsCompleted bool
	lastCompleted  pgtype.Timestamptz
	hasLast        bool
}

func validKind(kind string) bool {
	switch kind {
	case kindCreate, kindUpsert, kindUpdate, kindCompleteOccurrence, kindReopenOccurrence, kindDelete:
		return true
	default:
		return false
	}
}

func isOccurrenceKind(kind string) bool {
	return kind == kindCompleteOccurrence || kind == kindReopenOccurrence
}

func (p taskPatch) hasAny() bool {
	return p.hasTitle || p.hasDueDate || p.hasHasTime || p.hasRecurrence || p.hasReminder || p.hasCompletions || p.hasIsCompleted || p.hasLast
}

func parseTaskPatch(payload json.RawMessage, requireTitle bool) (taskPatch, error) {
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(payload, &fields); err != nil || fields == nil {
		return taskPatch{}, ErrInvalidMutation
	}
	var p taskPatch
	for key, raw := range fields {
		switch key {
		case "title":
			var value string
			if json.Unmarshal(raw, &value) != nil {
				return taskPatch{}, ErrInvalidMutation
			}
			p.title = strings.TrimSpace(value)
			if p.title == "" || len(p.title) > 500 {
				return taskPatch{}, ErrInvalidMutation
			}
			p.hasTitle = true
		case "dueDate":
			value, isNull, err := optionalString(raw)
			if err != nil {
				return taskPatch{}, ErrInvalidMutation
			}
			if !isNull {
				parsed, parseErr := parseWallClock(value, false)
				err = parseErr
				if err != nil {
					return taskPatch{}, ErrInvalidMutation
				}
				p.dueDate = pgtype.Timestamp{Time: parsed, Valid: true}
			}
			p.hasDueDate = true
		case "hasTime":
			if string(bytesTrimSpace(raw)) == "null" || json.Unmarshal(raw, &p.hasTime) != nil {
				return taskPatch{}, ErrInvalidMutation
			}
			p.hasHasTime = true
		case "recurrenceRule":
			value, isNull, err := optionalString(raw)
			if err != nil || (!isNull && !canonicalRecurrenceRules[value]) {
				return taskPatch{}, ErrInvalidMutation
			}
			if !isNull {
				p.recurrenceRule = pgtype.Text{String: value, Valid: true}
			}
			p.hasRecurrence = true
		case "reminder":
			value, isNull, err := optionalString(raw)
			if err != nil || (!isNull && !canonicalReminders[value]) {
				return taskPatch{}, ErrInvalidMutation
			}
			if !isNull {
				p.reminder = pgtype.Text{String: value, Valid: true}
			}
			p.hasReminder = true
		case "completions":
			if string(bytesTrimSpace(raw)) == "null" {
				p.completions = map[string]string{}
			} else if err := json.Unmarshal(raw, &p.completions); err != nil {
				return taskPatch{}, ErrInvalidMutation
			}
			if err := validateCompletions(p.completions); err != nil {
				return taskPatch{}, err
			}
			p.hasCompletions = true
		case "isCompleted":
			if string(bytesTrimSpace(raw)) == "null" || json.Unmarshal(raw, &p.isCompleted) != nil {
				return taskPatch{}, ErrInvalidMutation
			}
			p.hasIsCompleted = true
		case "lastCompletedAt":
			if string(bytesTrimSpace(raw)) == "null" {
				p.hasLast = true
				continue
			}
			value, err := decodeString(raw)
			if err != nil {
				return taskPatch{}, ErrInvalidMutation
			}
			t, err := parseUTCInstant(value)
			if err != nil {
				return taskPatch{}, ErrInvalidMutation
			}
			p.lastCompleted = pgtype.Timestamptz{Time: t, Valid: true}
			p.hasLast = true
		default:
			return taskPatch{}, ErrInvalidMutation
		}
	}
	if requireTitle && !p.hasTitle {
		return taskPatch{}, ErrInvalidMutation
	}
	return p, nil
}

func parseOccurrencePayload(payload json.RawMessage, completing, hasTime bool) (time.Time, *time.Time, error) {
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(payload, &fields); err != nil || fields == nil {
		return time.Time{}, nil, ErrInvalidMutation
	}
	rawScheduled, ok := fields["scheduledAt"]
	if !ok {
		return time.Time{}, nil, ErrInvalidMutation
	}
	scheduled, err := decodeString(rawScheduled)
	if err != nil {
		return time.Time{}, nil, ErrInvalidMutation
	}
	t, err := parseWallClock(scheduled, !hasTime)
	if err != nil {
		return time.Time{}, nil, ErrInvalidMutation
	}
	var completed *time.Time
	if raw, ok := fields["completedAt"]; ok && string(bytesTrimSpace(raw)) != "null" {
		value, err := decodeString(raw)
		if err != nil {
			return time.Time{}, nil, ErrInvalidMutation
		}
		completedAt, err := parseUTCInstant(value)
		if err != nil {
			return time.Time{}, nil, ErrInvalidMutation
		}
		completed = &completedAt
	}
	for key := range fields {
		if key != "scheduledAt" && key != "completedAt" {
			return time.Time{}, nil, ErrInvalidMutation
		}
	}
	if !completing && completed != nil {
		return time.Time{}, nil, ErrInvalidMutation
	}
	return t, completed, nil
}

func parseWallClock(value string, dateOnly bool) (time.Time, error) {
	if !canonicalWallClockPattern.MatchString(value) {
		return time.Time{}, ErrInvalidMutation
	}
	layout := "2006-01-02T15:04:05.000"
	if len(value) == len("2006-01-02T15:04:05.000000") {
		layout = "2006-01-02T15:04:05.000000"
	}
	t, err := time.ParseInLocation(layout, value, time.UTC)
	if err != nil || (dateOnly && (t.Hour() != 0 || t.Minute() != 0 || t.Second() != 0 || t.Nanosecond() != 0)) {
		return time.Time{}, ErrInvalidMutation
	}
	return t, nil
}

func parseUTCInstant(value string) (time.Time, error) {
	if !canonicalUTCInstantPattern.MatchString(value) {
		return time.Time{}, ErrInvalidMutation
	}
	layout := "2006-01-02T15:04:05.000Z"
	if len(value) == len("2006-01-02T15:04:05.000000Z") {
		layout = "2006-01-02T15:04:05.000000Z"
	}
	return time.Parse(layout, value)
}

func formatWallClock(value time.Time) string {
	if value.Nanosecond()%int(time.Millisecond) != 0 {
		return value.Format("2006-01-02T15:04:05.000000")
	}
	return value.Format("2006-01-02T15:04:05.000")
}

func formatUTCInstant(value time.Time) string {
	value = value.UTC()
	if value.Nanosecond()%int(time.Millisecond) != 0 {
		return value.Format("2006-01-02T15:04:05.000000Z")
	}
	return value.Format("2006-01-02T15:04:05.000Z")
}

func decodeCompletions(raw []byte) map[string]string {
	var values map[string]string
	if len(raw) == 0 || json.Unmarshal(raw, &values) != nil || values == nil {
		return map[string]string{}
	}
	return values
}

func cloneCompletions(values map[string]string) map[string]string {
	clone := make(map[string]string, len(values))
	for key, value := range values {
		clone[key] = value
	}
	return clone
}

func sameCompletions(a, b map[string]string) bool {
	if len(a) != len(b) {
		return false
	}
	for key, value := range a {
		if b[key] != value {
			return false
		}
	}
	return true
}

func encodeCompletions(values map[string]string) []byte {
	if values == nil {
		values = map[string]string{}
	}
	b, _ := json.Marshal(values)
	return b
}

func decodeCompletionHistory(raw []byte) []CompletionRecord {
	var records []CompletionRecord
	if len(raw) == 0 || json.Unmarshal(raw, &records) != nil || records == nil {
		return []CompletionRecord{}
	}
	return records
}

func encodeCompletionHistory(records []CompletionRecord) []byte {
	if records == nil {
		records = []CompletionRecord{}
	}
	raw, _ := json.Marshal(records)
	return raw
}

func archiveActiveCompletions(history []CompletionRecord, row taskRow) []CompletionRecord {
	seen := make(map[string]struct{}, len(history))
	for _, record := range history {
		seen[completionRecordKey(record)] = struct{}{}
	}
	appendRecord := func(scheduledAt *string, completedAt time.Time) {
		record := CompletionRecord{ScheduledAt: scheduledAt, HasTime: row.HasTime, CompletedAt: formatUTCInstant(completedAt)}
		key := completionRecordKey(record)
		if _, exists := seen[key]; exists {
			return
		}
		seen[key] = struct{}{}
		history = append(history, record)
	}
	if row.RecurrenceRule.Valid {
		for scheduled, completed := range decodeCompletions(row.Completions) {
			scheduledAt := scheduled
			completedAt, err := parseUTCInstant(completed)
			if err != nil {
				continue
			}
			appendRecord(&scheduledAt, completedAt)
		}
	} else if row.IsCompleted && row.LastCompletedAt.Valid {
		var scheduledAt *string
		if row.DueDate.Valid {
			value := formatWallClock(row.DueDate.Time)
			scheduledAt = &value
		}
		appendRecord(scheduledAt, row.LastCompletedAt.Time)
	}
	sort.Slice(history, func(i, j int) bool {
		return completionRecordKey(history[i]) < completionRecordKey(history[j])
	})
	return history
}

func completionRecordKey(record CompletionRecord) string {
	scheduled := "<null>"
	if record.ScheduledAt != nil {
		scheduled = *record.ScheduledAt
	}
	return scheduled + "\x00" + strconv.FormatBool(record.HasTime) + "\x00" + record.CompletedAt
}

func validateCompletions(values map[string]string) error {
	for scheduledAt, completedAt := range values {
		if _, err := parseWallClock(scheduledAt, false); err != nil {
			return ErrInvalidMutation
		}
		if _, err := parseUTCInstant(completedAt); err != nil {
			return ErrInvalidMutation
		}
	}
	return nil
}

func validateCompletionsForTask(values map[string]string, hasTime bool, recurrence pgtype.Text) error {
	if len(values) == 0 {
		return nil
	}
	if !recurrence.Valid {
		return ErrInvalidMutation
	}
	for scheduledAt, completedAt := range values {
		if _, err := parseWallClock(scheduledAt, !hasTime); err != nil {
			return ErrInvalidMutation
		}
		if _, err := parseUTCInstant(completedAt); err != nil {
			return ErrInvalidMutation
		}
	}
	return nil
}

func optionalString(raw json.RawMessage) (string, bool, error) {
	if string(bytesTrimSpace(raw)) == "null" {
		return "", true, nil
	}
	value, err := decodeString(raw)
	return value, false, err
}

func decodeString(raw json.RawMessage) (string, error) {
	var value string
	if err := json.Unmarshal(raw, &value); err != nil || strings.TrimSpace(value) == "" {
		return "", ErrInvalidMutation
	}
	return value, nil
}

func isJSONObject(raw []byte) bool {
	var value map[string]json.RawMessage
	return json.Unmarshal(raw, &value) == nil && value != nil
}

func canonicalPayloadHash(raw []byte) (string, error) {
	var value any
	decoder := json.NewDecoder(strings.NewReader(string(raw)))
	decoder.UseNumber()
	if err := decoder.Decode(&value); err != nil {
		return "", err
	}
	canonical, err := json.Marshal(value)
	if err != nil {
		return "", err
	}
	digest := sha256.Sum256(canonical)
	return hex.EncodeToString(digest[:]), nil
}

func bytesTrimSpace(raw []byte) []byte { return []byte(strings.TrimSpace(string(raw))) }

func sameTimestamp(a, b pgtype.Timestamp) bool {
	return a.Valid == b.Valid && (!a.Valid || a.Time.Equal(b.Time))
}

func sameTimestamptz(a, b pgtype.Timestamptz) bool {
	return a.Valid == b.Valid && (!a.Valid || a.Time.Equal(b.Time))
}

func sameText(a, b pgtype.Text) bool {
	return a.Valid == b.Valid && (!a.Valid || a.String == b.String)
}

func sameWallClock(a, b time.Time) bool { return a.Equal(b) }

func isMidnight(value time.Time) bool {
	return value.Hour() == 0 && value.Minute() == 0 && value.Second() == 0 && value.Nanosecond() == 0
}

func taskFromRow(row taskRow) Task {
	return taskFromFields(row.ID, row.OwnerUserID, row.Title, row.DueDate, row.HasTime, row.RecurrenceRule, row.Reminder, row.Completions, row.CompletionHistory, row.IsCompleted, row.LastCompletedAt, row.Revision, row.ScheduleGeneration, row.CreatedAt, row.UpdatedAt, row.DeletedAt)
}

func taskFromFields(id, owner pgtype.UUID, title string, due pgtype.Timestamp, has bool, rec, rem pgtype.Text, comp, history []byte, done bool, last pgtype.Timestamptz, rev, gen int64, created, updated, deleted pgtype.Timestamptz) Task {
	if len(comp) == 0 {
		comp = []byte(`{}`)
	}
	return Task{
		ID: id.String(), OwnerUserID: owner.String(), Title: title, DueDate: formatDate(due), HasTime: has,
		RecurrenceRule: textPtr(rec), Reminder: textPtr(rem), Completions: json.RawMessage(comp), CompletionHistory: decodeCompletionHistory(history), IsCompleted: done,
		LastCompletedAt: formatTimestamp(last), Revision: rev, ScheduleGeneration: gen,
		CreatedAt: created.Time.UTC().Format(time.RFC3339Nano), UpdatedAt: updated.Time.UTC().Format(time.RFC3339Nano), DeletedAt: formatTimestamp(deleted),
	}
}

func textPtr(v pgtype.Text) *string {
	if !v.Valid {
		return nil
	}
	return &v.String
}
