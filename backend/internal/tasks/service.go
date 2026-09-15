package tasks

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"strings"
	"time"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
)

const (
	kindCreate             = "create"
	kindUpsert             = "upsert"
	kindUpdate             = "update"
	kindCompleteOccurrence = "complete_occurrence"
	kindReopenOccurrence   = "reopen_occurrence"
	kindDelete             = "delete"
)

var (
	ErrTaskNotFound    = errors.New("task not found")
	ErrTaskExists      = errors.New("task already exists")
	ErrHashMismatch    = errors.New("operation payload hash mismatch")
	ErrScheduleChanged = errors.New("SCHEDULE_CHANGED")
	ErrTaskDeleted     = errors.New("TASK_DELETED")
	ErrInvalidMutation = errors.New("invalid task mutation")
	ErrNoopMutation    = errors.New("task mutation is a no-op")
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

type Service struct{ repo Repository }

func NewService(r Repository) *Service { return &Service{repo: r} }

func (s *Service) Bootstrap(c context.Context, u pgtype.UUID) (BootstrapResult, error) {
	var out BootstrapResult
	err := s.repo.WithReadTx(c, func(r Repository) error {
		rows, err := r.ListTasks(c, u)
		if err != nil {
			return err
		}
		out.Tasks = make([]Task, 0, len(rows))
		for _, row := range rows {
			out.Tasks = append(out.Tasks, taskFromFields(row.ID, row.OwnerUserID, row.Title, row.DueDate, row.HasTime, row.RecurrenceRule, row.Reminder, row.Completions, row.IsCompleted, row.LastCompletedAt, row.Revision, row.ScheduleGeneration, row.CreatedAt, row.UpdatedAt, row.DeletedAt))
		}
		out.Watermark, err = r.Watermark(c, u)
		return err
	})
	return out, err
}

func (s *Service) Get(c context.Context, id, u pgtype.UUID) (Task, error) {
	row, err := s.repo.GetTask(c, id, u)
	if errors.Is(err, pgx.ErrNoRows) || row.DeletedAt.Valid {
		return Task{}, ErrTaskNotFound
	}
	if err != nil {
		return Task{}, err
	}
	return taskFromFields(row.ID, row.OwnerUserID, row.Title, row.DueDate, row.HasTime, row.RecurrenceRule, row.Reminder, row.Completions, row.IsCompleted, row.LastCompletedAt, row.Revision, row.ScheduleGeneration, row.CreatedAt, row.UpdatedAt, row.DeletedAt), nil
}

func (s *Service) ApplyMutation(c context.Context, u, id pgtype.UUID, m Mutation) (MutationResult, error) {
	var out MutationResult
	err := s.repo.WithTx(c, func(r Repository) error {
		var err error
		out, err = apply(c, r, u, id, m)
		return err
	})
	return out, err
}

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

func apply(c context.Context, r Repository, u, id pgtype.UUID, m Mutation) (MutationResult, error) {
	op, err := uuid.Parse(m.OperationID)
	if err != nil || !validKind(m.Kind) || len(bytesTrimSpace(m.Payload)) == 0 || !isJSONObject(m.Payload) {
		return MutationResult{}, ErrInvalidMutation
	}
	hash, err := canonicalPayloadHash(m.Payload)
	if err != nil {
		return MutationResult{}, ErrInvalidMutation
	}
	operationID := pgtype.UUID{Bytes: op, Valid: true}

	row, err := r.LockTask(c, id, u)
	if errors.Is(err, pgx.ErrNoRows) {
		if m.Kind != kindCreate && m.Kind != kindUpsert {
			return MutationResult{}, ErrTaskNotFound
		}
		patch, parseErr := parseTaskPatch(m.Payload, true)
		if parseErr != nil {
			return MutationResult{}, parseErr
		}
		if patch.dueDate.Valid && !patch.hasTime && !isMidnight(patch.dueDate.Time) {
			return MutationResult{}, ErrInvalidMutation
		}
		if err := validateCompletionsForTask(patch.completions, patch.hasTime, patch.recurrenceRule); err != nil {
			return MutationResult{}, err
		}
		row, err = r.InsertTask(c, sqlcgen.InsertTaskParams{
			ID: id, OwnerUserID: u, Title: patch.title,
			DueDate: patch.dueDate, HasTime: patch.hasTime,
			RecurrenceRule: patch.recurrenceRule, Reminder: patch.reminder,
			Completions: encodeCompletions(patch.completions),
			IsCompleted: patch.isCompleted, LastCompletedAt: patch.lastCompleted,
			ScheduleGeneration: m.ScheduleGeneration,
		})
		if err == nil {
			return persistMutation(c, r, u, id, m, operationID, hash, row, "task_changed")
		}
		if !errors.Is(err, pgx.ErrNoRows) {
			return MutationResult{}, err
		}
		// An owner may have created this id concurrently. InsertTask uses
		// ON CONFLICT DO NOTHING, so the transaction remains usable and the
		// owner row can be locked and replayed/applied below.
		row, err = r.LockTask(c, id, u)
		if errors.Is(err, pgx.ErrNoRows) {
			return MutationResult{}, ErrTaskNotFound
		}
		if err != nil {
			return MutationResult{}, err
		}
	}
	if err != nil {
		return MutationResult{}, err
	}

	// Locking the owner-scoped row before replay lookup prevents returning an
	// operation response belonging to another task or another owner.
	old, err := r.GetOperation(c, id, operationID)
	if err == nil {
		if old.PayloadHash != hash {
			return MutationResult{}, ErrHashMismatch
		}
		var out MutationResult
		if err := json.Unmarshal(old.ResponseJson, &out); err != nil {
			return MutationResult{}, fmt.Errorf("decode stored task mutation response: %w", err)
		}
		return out, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return MutationResult{}, err
	}
	if row.DeletedAt.Valid {
		return MutationResult{}, ErrTaskDeleted
	}
	if isOccurrenceKind(m.Kind) {
		if m.ScheduleGeneration != row.ScheduleGeneration {
			return MutationResult{}, ErrScheduleChanged
		}
		return applyOccurrence(c, r, u, id, m, operationID, hash, row)
	}
	if m.Kind == kindDelete {
		var fields map[string]json.RawMessage
		if err := json.Unmarshal(m.Payload, &fields); err != nil || len(fields) != 0 {
			return MutationResult{}, ErrInvalidMutation
		}
		row.DeletedAt = pgtype.Timestamptz{Time: time.Now().UTC(), Valid: true}
		row, err = r.UpdateTask(c, sqlcgen.UpdateTaskParams{
			ID: id, OwnerUserID: u, Title: row.Title, DueDate: row.DueDate, HasTime: row.HasTime,
			RecurrenceRule: row.RecurrenceRule, Reminder: row.Reminder, Completions: row.Completions,
			IsCompleted: row.IsCompleted, LastCompletedAt: row.LastCompletedAt,
			ScheduleGeneration: row.ScheduleGeneration, DeletedAt: row.DeletedAt,
		})
		if err != nil {
			return MutationResult{}, err
		}
		return persistMutation(c, r, u, id, m, operationID, hash, row, "task_deleted")
	}
	if m.Kind == kindCreate {
		return MutationResult{}, ErrTaskExists
	}

	patch, err := parseTaskPatch(m.Payload, false)
	if err != nil {
		return MutationResult{}, err
	}
	if !patch.hasAny() {
		return MutationResult{}, ErrNoopMutation
	}

	dueDate := row.DueDate
	if patch.hasDueDate {
		dueDate = patch.dueDate
	}
	hasTime := row.HasTime
	if patch.hasHasTime {
		hasTime = patch.hasTime
	}
	recurrence := row.RecurrenceRule
	if patch.hasRecurrence {
		recurrence = patch.recurrenceRule
	}
	reminder := row.Reminder
	if patch.hasReminder {
		reminder = patch.reminder
	}
	title := row.Title
	if patch.hasTitle {
		title = patch.title
	}
	completions := decodeCompletions(row.Completions)
	originalCompletions := cloneCompletions(completions)
	if patch.hasCompletions {
		for key, value := range patch.completions {
			completions[key] = value
		}
	}
	isCompleted := row.IsCompleted
	if patch.hasIsCompleted {
		isCompleted = patch.isCompleted
	}
	lastCompleted := row.LastCompletedAt
	if patch.hasLast {
		lastCompleted = patch.lastCompleted
	}
	if dueDate.Valid && !hasTime && !isMidnight(dueDate.Time) {
		return MutationResult{}, ErrInvalidMutation
	}

	if patch.hasCompletions {
		if err := validateCompletionsForTask(patch.completions, hasTime, recurrence); err != nil {
			return MutationResult{}, err
		}
	}
	scheduleChanged := !sameTimestamp(dueDate, row.DueDate) || hasTime != row.HasTime || !sameText(recurrence, row.RecurrenceRule)
	generation := row.ScheduleGeneration
	if scheduleChanged {
		generation++
		completions = map[string]string{}
	} else if err := validateCompletionsForTask(completions, hasTime, recurrence); err != nil {
		return MutationResult{}, err
	}
	if !scheduleChanged && title == row.Title && sameText(reminder, row.Reminder) && sameCompletions(completions, originalCompletions) && isCompleted == row.IsCompleted && sameTimestamptz(lastCompleted, row.LastCompletedAt) {
		return MutationResult{}, ErrNoopMutation
	}

	row, err = r.UpdateTask(c, sqlcgen.UpdateTaskParams{
		ID: id, OwnerUserID: u, Title: title, DueDate: dueDate, HasTime: hasTime,
		RecurrenceRule: recurrence, Reminder: reminder, Completions: encodeCompletions(completions),
		IsCompleted: isCompleted, LastCompletedAt: lastCompleted,
		ScheduleGeneration: generation, DeletedAt: row.DeletedAt,
	})
	if err != nil {
		return MutationResult{}, err
	}
	return persistMutation(c, r, u, id, m, operationID, hash, row, "task_changed")
}

func applyOccurrence(c context.Context, r Repository, u, id pgtype.UUID, m Mutation, operationID pgtype.UUID, hash string, row sqlcgen.Task) (MutationResult, error) {
	scheduledAt, completedAt, err := parseOccurrencePayload(m.Payload, m.Kind == kindCompleteOccurrence, row.HasTime)
	if err != nil {
		return MutationResult{}, err
	}
	if !row.RecurrenceRule.Valid {
		if !row.DueDate.Valid || !sameWallClock(scheduledAt, row.DueDate.Time) {
			return MutationResult{}, ErrInvalidMutation
		}
	}
	completions := decodeCompletions(row.Completions)
	key := formatWallClock(scheduledAt)
	if m.Kind == kindCompleteOccurrence {
		if _, exists := completions[key]; exists || (!row.RecurrenceRule.Valid && row.IsCompleted) {
			return MutationResult{}, ErrNoopMutation
		}
		if completedAt == nil {
			now := time.Now().UTC()
			completedAt = &now
		}
		if row.RecurrenceRule.Valid {
			completions[key] = formatUTCInstant(*completedAt)
		} else {
			row.LastCompletedAt = pgtype.Timestamptz{Time: *completedAt, Valid: true}
			row.IsCompleted = true
		}
	} else {
		if !row.RecurrenceRule.Valid && !row.IsCompleted {
			return MutationResult{}, ErrNoopMutation
		}
		if _, exists := completions[key]; !exists && row.RecurrenceRule.Valid {
			return MutationResult{}, ErrNoopMutation
		}
		if row.RecurrenceRule.Valid {
			delete(completions, key)
		}
		if !row.RecurrenceRule.Valid {
			row.IsCompleted = false
			row.LastCompletedAt = pgtype.Timestamptz{}
		}
	}
	if row.RecurrenceRule.Valid {
		row.IsCompleted = false
	}
	updated, err := r.UpdateTask(c, sqlcgen.UpdateTaskParams{
		ID: id, OwnerUserID: u, Title: row.Title, DueDate: row.DueDate, HasTime: row.HasTime,
		RecurrenceRule: row.RecurrenceRule, Reminder: row.Reminder, Completions: encodeCompletions(completions),
		IsCompleted: row.IsCompleted, LastCompletedAt: row.LastCompletedAt,
		ScheduleGeneration: row.ScheduleGeneration, DeletedAt: row.DeletedAt,
	})
	if err != nil {
		return MutationResult{}, err
	}
	return persistMutation(c, r, u, id, m, operationID, hash, updated, "task_changed")
}

func persistMutation(c context.Context, r Repository, u, id pgtype.UUID, m Mutation, operationID pgtype.UUID, hash string, row sqlcgen.Task, kind string) (MutationResult, error) {
	task := taskFromFields(row.ID, row.OwnerUserID, row.Title, row.DueDate, row.HasTime, row.RecurrenceRule, row.Reminder, row.Completions, row.IsCompleted, row.LastCompletedAt, row.Revision, row.ScheduleGeneration, row.CreatedAt, row.UpdatedAt, row.DeletedAt)
	out := MutationResult{OperationID: m.OperationID, Revision: row.Revision, Task: task}
	response, err := json.Marshal(out)
	if err != nil {
		return MutationResult{}, err
	}
	if err := r.InsertOperation(c, sqlcgen.InsertTaskOperationParams{TaskID: id, OperationID: operationID, PayloadHash: hash, ResponseJson: response}); err != nil {
		return MutationResult{}, err
	}
	if err := r.InsertChange(c, sqlcgen.InsertTaskSyncChangeParams{TargetUserID: u, Kind: kind, TaskID: id, Revision: pgtype.Int8{Int64: row.Revision, Valid: true}}); err != nil {
		return MutationResult{}, err
	}
	return out, nil
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

func taskFromFields(id, owner pgtype.UUID, title string, due pgtype.Timestamp, has bool, rec, rem pgtype.Text, comp []byte, done bool, last pgtype.Timestamptz, rev, gen int64, created, updated, deleted pgtype.Timestamptz) Task {
	if len(comp) == 0 {
		comp = []byte(`{}`)
	}
	return Task{
		ID: id.String(), OwnerUserID: owner.String(), Title: title, DueDate: formatDate(due), HasTime: has,
		RecurrenceRule: textPtr(rec), Reminder: textPtr(rem), Completions: json.RawMessage(comp), IsCompleted: done,
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
