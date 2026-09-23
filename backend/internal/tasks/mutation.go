package tasks

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
)

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
		if err := validateTaskSchedule(patch.dueDate, patch.hasTime, patch.recurrenceRule, patch.reminder); err != nil {
			return MutationResult{}, err
		}
		if err := validateCompletionsForTask(patch.completions, patch.hasTime, patch.recurrenceRule); err != nil {
			return MutationResult{}, err
		}
		row, err = r.InsertTask(c, taskInsert{
			ID: id, OwnerUserID: u, Title: patch.title,
			DueDate: patch.dueDate, HasTime: patch.hasTime,
			RecurrenceRule: patch.recurrenceRule, Reminder: patch.reminder,
			Completions:       encodeCompletions(patch.completions),
			CompletionHistory: encodeCompletionHistory(nil),
			IsCompleted:       patch.isCompleted, LastCompletedAt: patch.lastCompleted,
			ScheduleGeneration: m.ScheduleGeneration,
		})
		if err == nil {
			return persistMutation(c, r, u, id, m, operationID, hash, row, "task_changed")
		}
		if !errors.Is(err, pgx.ErrNoRows) {
			return MutationResult{}, err
		}
		// InsertTask uses ON CONFLICT DO NOTHING. Reload the owner row so a
		// concurrent create can still replay or apply deterministically.
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
		if err := json.Unmarshal(old.ResponseJSON, &out); err != nil {
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
		row, err = r.UpdateTask(c, taskUpdate{
			ID: id, OwnerUserID: u, Title: row.Title, DueDate: row.DueDate, HasTime: row.HasTime,
			RecurrenceRule: row.RecurrenceRule, Reminder: row.Reminder, Completions: row.Completions,
			CompletionHistory: row.CompletionHistory,
			IsCompleted:       row.IsCompleted, LastCompletedAt: row.LastCompletedAt,
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
	history := decodeCompletionHistory(row.CompletionHistory)
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
	if err := validateTaskSchedule(dueDate, hasTime, recurrence, reminder); err != nil {
		return MutationResult{}, err
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
		history = archiveActiveCompletions(history, row)
		completions = map[string]string{}
		isCompleted = false
		lastCompleted = pgtype.Timestamptz{}
	} else if err := validateCompletionsForTask(completions, hasTime, recurrence); err != nil {
		return MutationResult{}, err
	}
	if !scheduleChanged && title == row.Title && sameText(reminder, row.Reminder) && sameCompletions(completions, originalCompletions) && isCompleted == row.IsCompleted && sameTimestamptz(lastCompleted, row.LastCompletedAt) {
		return MutationResult{}, ErrNoopMutation
	}

	row, err = r.UpdateTask(c, taskUpdate{
		ID: id, OwnerUserID: u, Title: title, DueDate: dueDate, HasTime: hasTime,
		RecurrenceRule: recurrence, Reminder: reminder, Completions: encodeCompletions(completions),
		CompletionHistory: encodeCompletionHistory(history),
		IsCompleted:       isCompleted, LastCompletedAt: lastCompleted,
		ScheduleGeneration: generation, DeletedAt: row.DeletedAt,
	})
	if err != nil {
		return MutationResult{}, err
	}
	return persistMutation(c, r, u, id, m, operationID, hash, row, "task_changed")
}

func applyOccurrence(c context.Context, r Repository, u, id pgtype.UUID, m Mutation, operationID pgtype.UUID, hash string, row taskRow) (MutationResult, error) {
	if err := validateTaskSchedule(row.DueDate, row.HasTime, row.RecurrenceRule, row.Reminder); err != nil {
		return MutationResult{}, err
	}
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
		} else {
			row.IsCompleted = false
			row.LastCompletedAt = pgtype.Timestamptz{}
		}
	}
	if row.RecurrenceRule.Valid {
		row.IsCompleted = false
	}
	updated, err := r.UpdateTask(c, taskUpdate{
		ID: id, OwnerUserID: u, Title: row.Title, DueDate: row.DueDate, HasTime: row.HasTime,
		RecurrenceRule: row.RecurrenceRule, Reminder: row.Reminder, Completions: encodeCompletions(completions),
		CompletionHistory: row.CompletionHistory,
		IsCompleted:       row.IsCompleted, LastCompletedAt: row.LastCompletedAt,
		ScheduleGeneration: row.ScheduleGeneration, DeletedAt: row.DeletedAt,
	})
	if err != nil {
		return MutationResult{}, err
	}
	return persistMutation(c, r, u, id, m, operationID, hash, updated, "task_changed")
}

func persistMutation(c context.Context, r Repository, u, id pgtype.UUID, m Mutation, operationID pgtype.UUID, hash string, row taskRow, kind string) (MutationResult, error) {
	task := taskFromRow(row)
	out := MutationResult{OperationID: m.OperationID, Revision: row.Revision, Task: task}
	response, err := json.Marshal(out)
	if err != nil {
		return MutationResult{}, err
	}
	if err := r.InsertOperation(c, taskOperationInsert{TaskID: id, OperationID: operationID, PayloadHash: hash, ResponseJSON: response}); err != nil {
		return MutationResult{}, err
	}
	if err := r.InsertChange(c, taskChange{TargetUserID: u, Kind: kind, TaskID: id, Revision: row.Revision}); err != nil {
		return MutationResult{}, err
	}
	return out, nil
}
