package tasks

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
)

type fakeRepo struct {
	task           sqlcgen.Task
	conflictTask   sqlcgen.Task
	ops            map[pgtype.UUID]sqlcgen.TaskOperation
	changes        int
	readTx         bool
	inserted       bool
	lockMisses     int
	insertConflict bool
}

func (f *fakeRepo) WithTx(_ context.Context, fn func(Repository) error) error { return fn(f) }
func (f *fakeRepo) WithReadTx(_ context.Context, fn func(Repository) error) error {
	f.readTx = true
	return fn(f)
}
func (f *fakeRepo) WithQuerier(sqlcgen.Querier) Repository { return f }
func (f *fakeRepo) ListTasks(context.Context, pgtype.UUID) ([]sqlcgen.Task, error) {
	if !f.task.OwnerUserID.Valid {
		return nil, nil
	}
	return []sqlcgen.Task{f.task}, nil
}
func (f *fakeRepo) GetTask(_ context.Context, _ pgtype.UUID, u pgtype.UUID) (sqlcgen.Task, error) {
	if u != f.task.OwnerUserID {
		return sqlcgen.Task{}, pgx.ErrNoRows
	}
	return f.task, nil
}
func (f *fakeRepo) LockTask(_ context.Context, _ pgtype.UUID, u pgtype.UUID) (sqlcgen.Task, error) {
	if f.lockMisses > 0 {
		f.lockMisses--
		return sqlcgen.Task{}, pgx.ErrNoRows
	}
	if !f.task.OwnerUserID.Valid || u != f.task.OwnerUserID {
		return sqlcgen.Task{}, pgx.ErrNoRows
	}
	return f.task, nil
}
func (f *fakeRepo) GetOperation(_ context.Context, taskID, operationID pgtype.UUID) (sqlcgen.TaskOperation, error) {
	v, ok := f.ops[operationID]
	if !ok || v.TaskID != taskID {
		return sqlcgen.TaskOperation{}, pgx.ErrNoRows
	}
	return v, nil
}
func (f *fakeRepo) InsertTask(_ context.Context, a sqlcgen.InsertTaskParams) (sqlcgen.Task, error) {
	f.inserted = true
	if f.insertConflict {
		f.task = f.conflictTask
		return sqlcgen.Task{}, pgx.ErrNoRows
	}
	f.task = sqlcgen.Task{
		ID: a.ID, OwnerUserID: a.OwnerUserID, Title: a.Title, DueDate: a.DueDate, HasTime: a.HasTime,
		RecurrenceRule: a.RecurrenceRule, Reminder: a.Reminder, Completions: a.Completions,
		IsCompleted: a.IsCompleted, LastCompletedAt: a.LastCompletedAt, Revision: 1,
		ScheduleGeneration: a.ScheduleGeneration,
	}
	return f.task, nil
}
func (f *fakeRepo) UpdateTask(_ context.Context, a sqlcgen.UpdateTaskParams) (sqlcgen.Task, error) {
	f.task.Title = a.Title
	f.task.DueDate = a.DueDate
	f.task.HasTime = a.HasTime
	f.task.RecurrenceRule = a.RecurrenceRule
	f.task.Reminder = a.Reminder
	f.task.Completions = a.Completions
	f.task.IsCompleted = a.IsCompleted
	f.task.LastCompletedAt = a.LastCompletedAt
	f.task.ScheduleGeneration = a.ScheduleGeneration
	f.task.DeletedAt = a.DeletedAt
	f.task.Revision++
	return f.task, nil
}
func (f *fakeRepo) InsertOperation(_ context.Context, a sqlcgen.InsertTaskOperationParams) error {
	if f.ops == nil {
		f.ops = map[pgtype.UUID]sqlcgen.TaskOperation{}
	}
	f.ops[a.OperationID] = sqlcgen.TaskOperation{TaskID: a.TaskID, OperationID: a.OperationID, PayloadHash: a.PayloadHash, ResponseJson: a.ResponseJson}
	return nil
}
func (f *fakeRepo) InsertChange(context.Context, sqlcgen.InsertTaskSyncChangeParams) error {
	f.changes++
	return nil
}
func (f *fakeRepo) Watermark(context.Context, pgtype.UUID) (int64, error) {
	return int64(f.changes), nil
}

func uuidWithByte(value byte) pgtype.UUID {
	return pgtype.UUID{Bytes: [16]byte{value}, Valid: true}
}

func TestApplyMutationSameOperationReturnsOriginalResult(t *testing.T) {
	id := uuidWithByte(1)
	f := &fakeRepo{task: sqlcgen.Task{ID: id, OwnerUserID: id, Title: "old", Completions: []byte(`{}`)}, ops: map[pgtype.UUID]sqlcgen.TaskOperation{}}
	s := NewService(f)
	m := Mutation{OperationID: "00000000-0000-4000-8000-000000000001", Kind: kindUpdate, Payload: []byte(`{"title":"A"}`)}
	a, err := s.ApplyMutation(context.Background(), id, id, m)
	if err != nil {
		t.Fatal(err)
	}
	b, err := s.ApplyMutation(context.Background(), id, id, m)
	if err != nil {
		t.Fatal(err)
	}
	if a.Revision != b.Revision || a.Task.Title != b.Task.Title {
		t.Fatalf("retry changed accepted result: %#v %#v", a, b)
	}
	if f.changes != 1 {
		t.Fatalf("retry emitted %d changes", f.changes)
	}
}

func TestApplyMutationHashIsStableAcrossJSONKeyOrder(t *testing.T) {
	id := uuidWithByte(11)
	f := &fakeRepo{task: sqlcgen.Task{ID: id, OwnerUserID: id, Title: "old", Completions: []byte(`{}`)}, ops: map[pgtype.UUID]sqlcgen.TaskOperation{}}
	m := Mutation{OperationID: "00000000-0000-4000-8000-000000000012", Kind: kindUpdate, Payload: []byte(`{"title":"A","isCompleted":false}`)}
	s := NewService(f)
	first, err := s.ApplyMutation(context.Background(), id, id, m)
	if err != nil {
		t.Fatal(err)
	}
	m.Payload = []byte(`{"isCompleted":false,"title":"A"}`)
	second, err := s.ApplyMutation(context.Background(), id, id, m)
	if err != nil {
		t.Fatal(err)
	}
	if first.Revision != second.Revision || f.changes != 1 {
		t.Fatalf("reordered payload was not replayed: first=%#v second=%#v changes=%d", first, second, f.changes)
	}
}

func TestApplyMutationDoesNotReplayAnotherTaskOperation(t *testing.T) {
	id := uuidWithByte(2)
	otherTask := uuidWithByte(3)
	operationID := uuidWithByte(4)
	response, err := json.Marshal(MutationResult{OperationID: operationID.String(), Revision: 99, Task: Task{Title: "secret"}})
	if err != nil {
		t.Fatal(err)
	}
	f := &fakeRepo{
		task: sqlcgen.Task{ID: id, OwnerUserID: id, Title: "mine", Completions: []byte(`{}`)},
		ops: map[pgtype.UUID]sqlcgen.TaskOperation{
			operationID: {TaskID: otherTask, OperationID: operationID, PayloadHash: "hash", ResponseJson: response},
		},
	}
	m := Mutation{OperationID: operationID.String(), Kind: kindUpdate, Payload: []byte(`{"title":"mine updated"}`)}
	result, err := NewService(f).ApplyMutation(context.Background(), id, id, m)
	if err != nil {
		t.Fatal(err)
	}
	if result.Task.Title != "mine updated" || result.Revision != 1 {
		t.Fatalf("replayed another task response: %#v", result)
	}
}

func TestCreatePersistsMetadataAndUsesSingleRevision(t *testing.T) {
	id := uuidWithByte(5)
	payload := []byte(`{"title":"A","dueDate":"2026-09-15T09:30:00.000","hasTime":true,"recurrenceRule":"weekly","reminder":"5m_before"}`)
	f := &fakeRepo{ops: map[pgtype.UUID]sqlcgen.TaskOperation{}}
	result, err := NewService(f).ApplyMutation(context.Background(), id, id, Mutation{
		OperationID: "00000000-0000-4000-8000-000000000005", Kind: kindCreate, Payload: payload,
	})
	if err != nil {
		t.Fatal(err)
	}
	if !f.inserted || result.Revision != 1 {
		t.Fatalf("create revision=%d inserted=%v", result.Revision, f.inserted)
	}
	if result.Task.DueDate == nil || *result.Task.DueDate != "2026-09-15T09:30:00.000" || !result.Task.HasTime || result.Task.RecurrenceRule == nil || result.Task.Reminder == nil {
		t.Fatalf("metadata was not persisted: %#v", result.Task)
	}
}

func TestCreateConflictReloadsOwnerRowAndReplaysOperation(t *testing.T) {
	id := uuidWithByte(12)
	m := Mutation{
		OperationID: "00000000-0000-4000-8000-000000000013",
		Kind:        kindCreate,
		Payload:     []byte(`{"title":"A"}`),
	}
	hash, err := canonicalPayloadHash(m.Payload)
	if err != nil {
		t.Fatal(err)
	}
	parsedOperationID, err := uuid.Parse(m.OperationID)
	if err != nil {
		t.Fatal(err)
	}
	operationID := pgtype.UUID{Bytes: parsedOperationID, Valid: true}
	existing := sqlcgen.Task{ID: id, OwnerUserID: id, Title: "A", Completions: []byte(`{}`), Revision: 1}
	response, err := json.Marshal(MutationResult{
		OperationID: m.OperationID,
		Revision:    existing.Revision,
		Task:        taskFromFields(existing.ID, existing.OwnerUserID, existing.Title, existing.DueDate, existing.HasTime, existing.RecurrenceRule, existing.Reminder, existing.Completions, existing.IsCompleted, existing.LastCompletedAt, existing.Revision, existing.ScheduleGeneration, existing.CreatedAt, existing.UpdatedAt, existing.DeletedAt),
	})
	if err != nil {
		t.Fatal(err)
	}
	f := &fakeRepo{
		conflictTask:   existing,
		lockMisses:     1,
		insertConflict: true,
		ops: map[pgtype.UUID]sqlcgen.TaskOperation{
			operationID: {TaskID: id, OperationID: operationID, PayloadHash: hash, ResponseJson: response},
		},
	}
	result, err := NewService(f).ApplyMutation(context.Background(), id, id, m)
	if err != nil {
		t.Fatal(err)
	}
	if result.Revision != existing.Revision || result.Task.Title != existing.Title {
		t.Fatalf("conflicting create did not replay stored result: %#v", result)
	}
	if f.changes != 0 {
		t.Fatalf("conflicting create emitted %d new changes", f.changes)
	}
}

func TestScheduleChangeIncrementsGenerationAndClearsCompletions(t *testing.T) {
	id := uuidWithByte(6)
	due, _ := time.ParseInLocation("2006-01-02T15:04:05.000", "2026-09-15T09:30:00.000", time.UTC)
	f := &fakeRepo{task: sqlcgen.Task{
		ID: id, OwnerUserID: id, Title: "A", DueDate: pgtype.Timestamp{Time: due, Valid: true}, HasTime: true,
		Completions: []byte(`{"2026-09-15T09:30:00.000":"2026-09-15T10:00:00.000Z"}`), Revision: 4, ScheduleGeneration: 7,
	}, ops: map[pgtype.UUID]sqlcgen.TaskOperation{}}
	result, err := NewService(f).ApplyMutation(context.Background(), id, id, Mutation{
		OperationID: "00000000-0000-4000-8000-000000000006", Kind: kindUpdate,
		Payload: []byte(`{"dueDate":"2026-09-16T09:30:00.000","hasTime":true}`),
	})
	if err != nil {
		t.Fatal(err)
	}
	if result.Task.ScheduleGeneration != 8 || string(result.Task.Completions) != `{}` {
		t.Fatalf("schedule change result=%#v", result.Task)
	}
}

func TestReminderChangePreservesScheduleHistory(t *testing.T) {
	id := uuidWithByte(14)
	due, _ := time.ParseInLocation("2006-01-02T15:04:05.000", "2026-09-15T09:30:00.000", time.UTC)
	f := &fakeRepo{task: sqlcgen.Task{
		ID: id, OwnerUserID: id, Title: "A", DueDate: pgtype.Timestamp{Time: due, Valid: true}, HasTime: true,
		RecurrenceRule: pgtype.Text{String: "weekly", Valid: true}, Reminder: pgtype.Text{String: "at_time", Valid: true},
		Completions: []byte(`{"2026-09-15T09:30:00.000":"2026-09-15T10:00:00.000Z"}`), Revision: 4, ScheduleGeneration: 7,
	}, ops: map[pgtype.UUID]sqlcgen.TaskOperation{}}
	result, err := NewService(f).ApplyMutation(context.Background(), id, id, Mutation{
		OperationID: "00000000-0000-4000-8000-000000000015", Kind: kindUpdate,
		Payload: []byte(`{"reminder":"5m_before"}`),
	})
	if err != nil {
		t.Fatal(err)
	}
	if result.Task.ScheduleGeneration != 7 || string(result.Task.Completions) != string(f.task.Completions) || result.Task.Reminder == nil || *result.Task.Reminder != "5m_before" {
		t.Fatalf("reminder change altered schedule history: %#v", result.Task)
	}
}

func TestGenericCompletionPatchRespectsTaskScheduleShape(t *testing.T) {
	t.Run("all-day recurring rejects timed occurrence", func(t *testing.T) {
		id := uuidWithByte(15)
		f := &fakeRepo{task: sqlcgen.Task{
			ID: id, OwnerUserID: id, Title: "A", HasTime: false,
			RecurrenceRule: pgtype.Text{String: "daily", Valid: true}, Completions: []byte(`{}`),
		}, ops: map[pgtype.UUID]sqlcgen.TaskOperation{}}
		_, err := NewService(f).ApplyMutation(context.Background(), id, id, Mutation{
			OperationID: "00000000-0000-4000-8000-000000000016", Kind: kindUpdate,
			Payload: []byte(`{"completions":{"2026-09-15T09:30:00.000":"2026-09-15T10:00:00.000Z"}}`),
		})
		if err != ErrInvalidMutation {
			t.Fatalf("timed completion on all-day recurring task error = %v", err)
		}
	})

	t.Run("non-recurring rejects completion history", func(t *testing.T) {
		id := uuidWithByte(16)
		f := &fakeRepo{task: sqlcgen.Task{
			ID: id, OwnerUserID: id, Title: "A", HasTime: true, Completions: []byte(`{}`),
		}, ops: map[pgtype.UUID]sqlcgen.TaskOperation{}}
		_, err := NewService(f).ApplyMutation(context.Background(), id, id, Mutation{
			OperationID: "00000000-0000-4000-8000-000000000017", Kind: kindUpdate,
			Payload: []byte(`{"completions":{"2026-09-15T09:30:00.000":"2026-09-15T10:00:00.000Z"}}`),
		})
		if err != ErrInvalidMutation {
			t.Fatalf("completion history on non-recurring task error = %v", err)
		}
	})
}

func TestOccurrenceCompletionCanonicalizesAndReopens(t *testing.T) {
	id := uuidWithByte(7)
	f := &fakeRepo{task: sqlcgen.Task{
		ID: id, OwnerUserID: id, Title: "A", HasTime: false,
		RecurrenceRule: pgtype.Text{String: "daily", Valid: true}, Completions: []byte(`{}`), Revision: 1,
	}, ops: map[pgtype.UUID]sqlcgen.TaskOperation{}}
	s := NewService(f)
	complete := Mutation{OperationID: "00000000-0000-4000-8000-000000000007", Kind: kindCompleteOccurrence, ScheduleGeneration: 0, Payload: []byte(`{"scheduledAt":"2026-09-15T00:00:00.000","completedAt":"2026-09-15T12:00:00.000Z"}`)}
	result, err := s.ApplyMutation(context.Background(), id, id, complete)
	if err != nil {
		t.Fatal(err)
	}
	var completions map[string]string
	if err := json.Unmarshal(result.Task.Completions, &completions); err != nil {
		t.Fatal(err)
	}
	if completions["2026-09-15T00:00:00.000"] != "2026-09-15T12:00:00.000Z" {
		t.Fatalf("completion key/value = %#v", completions)
	}
	reopen := complete
	reopen.OperationID = "00000000-0000-4000-8000-000000000008"
	reopen.Kind = kindReopenOccurrence
	reopen.Payload = []byte(`{"scheduledAt":"2026-09-15T00:00:00.000","completedAt":null}`)
	result, err = s.ApplyMutation(context.Background(), id, id, reopen)
	if err != nil {
		t.Fatal(err)
	}
	if string(result.Task.Completions) != `{}` {
		t.Fatalf("reopen did not remove only completion: %s", result.Task.Completions)
	}
}

func TestOccurrenceRejectsArbitraryTimestampAndNoop(t *testing.T) {
	id := uuidWithByte(8)
	f := &fakeRepo{task: sqlcgen.Task{
		ID: id, OwnerUserID: id, Title: "A", HasTime: false,
		RecurrenceRule: pgtype.Text{String: "daily", Valid: true}, Completions: []byte(`{"2026-09-15T00:00:00.000":"2026-09-15T12:00:00.000Z"}`),
	}, ops: map[pgtype.UUID]sqlcgen.TaskOperation{}}
	s := NewService(f)
	bad := Mutation{OperationID: "00000000-0000-4000-8000-000000000009", Kind: kindCompleteOccurrence, Payload: []byte(`{"scheduledAt":"tomorrow"}`)}
	if _, err := s.ApplyMutation(context.Background(), id, id, bad); err != ErrInvalidMutation {
		t.Fatalf("arbitrary occurrence timestamp error = %v", err)
	}
	noop := Mutation{OperationID: "00000000-0000-4000-8000-000000000011", Kind: kindCompleteOccurrence, Payload: []byte(`{"scheduledAt":"2026-09-15T00:00:00.000"}`)}
	if _, err := s.ApplyMutation(context.Background(), id, id, noop); err != ErrNoopMutation {
		t.Fatalf("duplicate occurrence error = %v", err)
	}
}

func TestBootstrapUsesRepeatableReadTransaction(t *testing.T) {
	id := uuidWithByte(9)
	f := &fakeRepo{task: sqlcgen.Task{ID: id, OwnerUserID: id, Title: "A"}}
	if _, err := NewService(f).Bootstrap(context.Background(), id); err != nil {
		t.Fatal(err)
	}
	if !f.readTx {
		t.Fatal("bootstrap did not use the repeatable-read transaction seam")
	}
}

func TestApplyMutationRejectsHashMismatch(t *testing.T) {
	id := uuidWithByte(10)
	f := &fakeRepo{task: sqlcgen.Task{ID: id, OwnerUserID: id, Title: "old", Completions: []byte(`{}`)}, ops: map[pgtype.UUID]sqlcgen.TaskOperation{}}
	s := NewService(f)
	m := Mutation{OperationID: "00000000-0000-4000-8000-000000000010", Kind: kindUpdate, Payload: []byte(`{"title":"A"}`)}
	if _, err := s.ApplyMutation(context.Background(), id, id, m); err != nil {
		t.Fatal(err)
	}
	m.Payload = []byte(`{"title":"B"}`)
	if _, err := s.ApplyMutation(context.Background(), id, id, m); err != ErrHashMismatch {
		t.Fatalf("want hash mismatch, got %v", err)
	}
}
