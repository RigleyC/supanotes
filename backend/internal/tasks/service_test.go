package tasks

import (
	"context"
	"testing"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
)

type fakeRepo struct {
	task    sqlcgen.Task
	ops     map[pgtype.UUID]sqlcgen.TaskOperation
	changes int
}

func (f *fakeRepo) WithTx(_ context.Context, fn func(Repository) error) error { return fn(f) }
func (f *fakeRepo) WithQuerier(sqlcgen.Querier) Repository                    { return f }
func (f *fakeRepo) ListTasks(context.Context, pgtype.UUID) ([]sqlcgen.Task, error) {
	return []sqlcgen.Task{f.task}, nil
}
func (f *fakeRepo) GetTask(_ context.Context, _ pgtype.UUID, u pgtype.UUID) (sqlcgen.Task, error) {
	if u != f.task.OwnerUserID {
		return sqlcgen.Task{}, pgx.ErrNoRows
	}
	return f.task, nil
}
func (f *fakeRepo) LockTask(_ context.Context, _ pgtype.UUID, u pgtype.UUID) (sqlcgen.Task, error) {
	if u != f.task.OwnerUserID {
		return sqlcgen.Task{}, pgx.ErrNoRows
	}
	return f.task, nil
}
func (f *fakeRepo) GetOperation(_ context.Context, id pgtype.UUID) (sqlcgen.TaskOperation, error) {
	v, ok := f.ops[id]
	if !ok {
		return sqlcgen.TaskOperation{}, pgx.ErrNoRows
	}
	return v, nil
}
func (f *fakeRepo) InsertTask(context.Context, sqlcgen.InsertTaskParams) (sqlcgen.Task, error) {
	return f.task, nil
}
func (f *fakeRepo) UpdateTask(_ context.Context, a sqlcgen.UpdateTaskParams) (sqlcgen.Task, error) {
	f.task.Title = a.Title
	f.task.Revision++
	f.task.Completions = a.Completions
	f.task.IsCompleted = a.IsCompleted
	return f.task, nil
}
func (f *fakeRepo) InsertOperation(_ context.Context, a sqlcgen.InsertTaskOperationParams) error {
	if f.ops == nil {
		f.ops = map[pgtype.UUID]sqlcgen.TaskOperation{}
	}
	f.ops[a.OperationID] = sqlcgen.TaskOperation{PayloadHash: a.PayloadHash, ResponseJson: a.ResponseJson}
	return nil
}
func (f *fakeRepo) InsertChange(context.Context, sqlcgen.InsertTaskSyncChangeParams) error {
	f.changes++
	return nil
}
func (f *fakeRepo) Watermark(context.Context, pgtype.UUID) (int64, error) {
	return int64(f.changes), nil
}

func TestApplyMutationSameOperationReturnsOriginalResult(t *testing.T) {
	id := pgtype.UUID{Bytes: [16]byte{1}, Valid: true}
	f := &fakeRepo{task: sqlcgen.Task{ID: id, OwnerUserID: id, Title: "old", Completions: []byte(`{}`), Revision: 0}, ops: map[pgtype.UUID]sqlcgen.TaskOperation{}}
	s := NewService(f)
	m := Mutation{OperationID: "00000000-0000-4000-8000-000000000001", Kind: "update", Payload: []byte(`{"title":"A"}`)}
	a, e := s.ApplyMutation(context.Background(), id, id, m)
	if e != nil {
		t.Fatal(e)
	}
	b, e := s.ApplyMutation(context.Background(), id, id, m)
	if e != nil {
		t.Fatal(e)
	}
	if a.Revision != b.Revision || a.Task.Title != b.Task.Title {
		t.Fatalf("retry changed accepted result: %#v %#v", a, b)
	}
	if f.changes != 1 {
		t.Fatalf("retry emitted %d changes", f.changes)
	}
}

func TestApplyMutationRejectsHashMismatch(t *testing.T) {
	id := pgtype.UUID{Bytes: [16]byte{2}, Valid: true}
	f := &fakeRepo{task: sqlcgen.Task{ID: id, OwnerUserID: id, Title: "old", Completions: []byte(`{}`)}, ops: map[pgtype.UUID]sqlcgen.TaskOperation{}}
	s := NewService(f)
	m := Mutation{OperationID: "00000000-0000-4000-8000-000000000002", Kind: "update", Payload: []byte(`{"title":"A"}`)}
	if _, e := s.ApplyMutation(context.Background(), id, id, m); e != nil {
		t.Fatal(e)
	}
	m.Payload = []byte(`{"title":"B"}`)
	if _, e := s.ApplyMutation(context.Background(), id, id, m); e != ErrHashMismatch {
		t.Fatalf("want hash mismatch, got %v", e)
	}
}
