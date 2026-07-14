package tasks

import (
	"context"
	"testing"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

type mockRepository struct {
	Repository
	getTaskByID          func(ctx context.Context, id pgtype.UUID, userID pgtype.UUID) (sqlcgen.Task, error)
	createTaskCompletion func(ctx context.Context, taskID pgtype.UUID, dueDate pgtype.Date) (sqlcgen.TaskCompletion, error)
	updateTask           func(ctx context.Context, arg sqlcgen.UpdateTaskParams) (sqlcgen.Task, error)
}

func (m *mockRepository) GetTaskByID(ctx context.Context, id pgtype.UUID, userID pgtype.UUID) (sqlcgen.Task, error) {
	if m.getTaskByID != nil {
		return m.getTaskByID(ctx, id, userID)
	}
	return sqlcgen.Task{}, nil
}

func (m *mockRepository) CreateTaskCompletion(ctx context.Context, taskID pgtype.UUID, dueDate pgtype.Date) (sqlcgen.TaskCompletion, error) {
	if m.createTaskCompletion != nil {
		return m.createTaskCompletion(ctx, taskID, dueDate)
	}
	return sqlcgen.TaskCompletion{}, nil
}

func (m *mockRepository) UpdateTask(ctx context.Context, arg sqlcgen.UpdateTaskParams) (sqlcgen.Task, error) {
	if m.updateTask != nil {
		return m.updateTask(ctx, arg)
	}
	return sqlcgen.Task{}, nil
}

func (m *mockRepository) CreateTask(ctx context.Context, arg sqlcgen.CreateTaskParams) (sqlcgen.Task, error) {
	return sqlcgen.Task{}, nil
}
func (m *mockRepository) DeleteTask(ctx context.Context, id pgtype.UUID, userID pgtype.UUID) error {
	return nil
}
func (m *mockRepository) GetTasks(ctx context.Context, arg sqlcgen.GetTasksParams) ([]sqlcgen.Task, error) {
	return nil, nil
}
func (m *mockRepository) GetTodayTasks(ctx context.Context, userID pgtype.UUID, upTo pgtype.Date) ([]sqlcgen.Task, error) {
	return nil, nil
}
func (m *mockRepository) GetTasksByNoteID(ctx context.Context, userID pgtype.UUID, noteID pgtype.UUID) ([]sqlcgen.Task, error) {
	return nil, nil
}
func (m *mockRepository) CountTasks(ctx context.Context, userID pgtype.UUID) (int64, error) {
	return 0, nil
}
func (m *mockRepository) CountOpenTasks(ctx context.Context, userID pgtype.UUID) (int64, error) {
	return 0, nil
}
func (m *mockRepository) CountCompletedTasks(ctx context.Context, userID pgtype.UUID) (int64, error) {
	return 0, nil
}
func (m *mockRepository) SearchTasks(ctx context.Context, arg sqlcgen.SearchTasksParams) ([]sqlcgen.Task, error) {
	return nil, nil
}
func (m *mockRepository) GetRecentlyCompletedTasks(ctx context.Context, arg sqlcgen.GetRecentlyCompletedTasksParams) ([]sqlcgen.Task, error) {
	return nil, nil
}

func TestCompleteTask_Fallback(t *testing.T) {
	taskID := pgtype.UUID{Bytes: [16]byte{1}, Valid: true}
	userID := pgtype.UUID{Bytes: [16]byte{2}, Valid: true}

	repo := &mockRepository{
		getTaskByID: func(ctx context.Context, id pgtype.UUID, uID pgtype.UUID) (sqlcgen.Task, error) {
			return sqlcgen.Task{
				ID:     taskID,
				UserID: userID,
				Status: "open",
				NoteID: pgtype.UUID{Bytes: [16]byte{3}, Valid: true},
			}, nil
		},
		updateTask: func(ctx context.Context, arg sqlcgen.UpdateTaskParams) (sqlcgen.Task, error) {
			return sqlcgen.Task{
				ID:     taskID,
				UserID: userID,
				Status: "done",
			}, nil
		},
	}

	svc := NewService(repo, nil)
	_, err := svc.CompleteTask(context.Background(), userID, taskID)
	if err != nil {
		t.Fatalf("CompleteTask failed: %v", err)
	}
}


