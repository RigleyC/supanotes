package tasks

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
)

type fakeRepo struct {
	task     sqlcgen.Task
	ops      map[pgtype.UUID]sqlcgen.TaskOperation
	changes  int
	readTx   bool
	inserted bool
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
