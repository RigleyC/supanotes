package tasks

import (
	"context"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

func TestCalculateNextDueDate(t *testing.T) {
	tests := []struct {
		name       string
		from       time.Time
		recurrence string
		wantNext   bool
		wantDate   time.Time
	}{
		{name: "daily", from: time.Date(2026, 6, 15, 0, 0, 0, 0, time.UTC), recurrence: "daily", wantNext: true, wantDate: time.Date(2026, 6, 16, 0, 0, 0, 0, time.UTC)},
		{name: "weekdays_thursday", from: time.Date(2026, 6, 18, 0, 0, 0, 0, time.UTC), recurrence: "weekdays", wantNext: true, wantDate: time.Date(2026, 6, 19, 0, 0, 0, 0, time.UTC)},
		{name: "weekdays_friday", from: time.Date(2026, 6, 19, 0, 0, 0, 0, time.UTC), recurrence: "weekdays", wantNext: true, wantDate: time.Date(2026, 6, 22, 0, 0, 0, 0, time.UTC)},
		{name: "weekdays_saturday", from: time.Date(2026, 6, 20, 0, 0, 0, 0, time.UTC), recurrence: "weekdays", wantNext: true, wantDate: time.Date(2026, 6, 22, 0, 0, 0, 0, time.UTC)},
		{name: "weekly", from: time.Date(2026, 6, 15, 0, 0, 0, 0, time.UTC), recurrence: "weekly", wantNext: true, wantDate: time.Date(2026, 6, 22, 0, 0, 0, 0, time.UTC)},
		{name: "monthly", from: time.Date(2026, 6, 15, 0, 0, 0, 0, time.UTC), recurrence: "monthly", wantNext: true, wantDate: time.Date(2026, 7, 15, 0, 0, 0, 0, time.UTC)},
		{name: "empty_recurrence", from: time.Date(2026, 6, 15, 0, 0, 0, 0, time.UTC), recurrence: "", wantNext: false},
		{name: "invalid_recurrence", from: time.Date(2026, 6, 15, 0, 0, 0, 0, time.UTC), recurrence: "unknown", wantNext: false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, ok := calculateNextDueDate(tt.from, tt.recurrence)
			if tt.wantNext && !ok {
				t.Errorf("calculateNextDueDate(%v, %q) = (_, %v), want (_, true)", tt.from, tt.recurrence, ok)
			}
			if !tt.wantNext && ok {
				t.Errorf("calculateNextDueDate(%v, %q) = (_, %v), want (_, false)", tt.from, tt.recurrence, ok)
			}
			if tt.wantNext && !got.Equal(tt.wantDate) {
				t.Errorf("calculateNextDueDate(%v, %q) = (%v, _), want (%v, _)", tt.from, tt.recurrence, got, tt.wantDate)
			}
		})
	}
}

func TestCalculateNextDueDateCatchUp(t *testing.T) {
	// Simulates a 3-day overdue daily task.
	// The catch-up helper should stop at today.
	now := time.Now().UTC()
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.UTC)
	threeDaysAgo := today.AddDate(0, 0, -3)

	taskDueDate := catchUpDueDate(threeDaysAgo, "daily", today)

	if !taskDueDate.Equal(today) {
		t.Errorf("catchUpDueDate = %v, want %v", taskDueDate, today)
	}
}

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

func TestCompleteTask_CatchUp(t *testing.T) {
	// A 3-day overdue daily task:
	now := time.Now().UTC()
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.UTC)
	threeDaysAgo := today.AddDate(0, 0, -3)

	taskID := pgtype.UUID{Bytes: [16]byte{1}, Valid: true}
	userID := pgtype.UUID{Bytes: [16]byte{2}, Valid: true}

	var completionDueDate pgtype.Date
	var updatedDueDate pgtype.Date

	repo := &mockRepository{
		getTaskByID: func(ctx context.Context, id pgtype.UUID, uID pgtype.UUID) (sqlcgen.Task, error) {
			return sqlcgen.Task{
				ID:         taskID,
				UserID:     userID,
				Status:     "open",
				DueDate:    pgtype.Date{Time: threeDaysAgo, Valid: true},
				Recurrence: pgtype.Text{String: "daily", Valid: true},
			}, nil
		},
		createTaskCompletion: func(ctx context.Context, taskID pgtype.UUID, dueDate pgtype.Date) (sqlcgen.TaskCompletion, error) {
			completionDueDate = dueDate
			return sqlcgen.TaskCompletion{}, nil
		},
		updateTask: func(ctx context.Context, arg sqlcgen.UpdateTaskParams) (sqlcgen.Task, error) {
			updatedDueDate = arg.DueDate
			return sqlcgen.Task{
				ID:         taskID,
				UserID:     userID,
				Status:     arg.Status.String,
				DueDate:    arg.DueDate,
				Recurrence: pgtype.Text{String: "daily", Valid: true},
			}, nil
		},
	}

	svc := NewService(repo)
	_, err := svc.CompleteTask(context.Background(), userID, taskID)
	if err != nil {
		t.Fatalf("CompleteTask failed: %v", err)
	}

	if !completionDueDate.Valid || !completionDueDate.Time.Equal(today) {
		t.Errorf("expected completion due date to be today (%v), got %v", today, completionDueDate.Time)
	}

	expectedNext := today.AddDate(0, 0, 1)
	if !updatedDueDate.Valid || !updatedDueDate.Time.Equal(expectedNext) {
		t.Errorf("expected updated task due date to be tomorrow (%v), got %v", expectedNext, updatedDueDate.Time)
	}
}

func TestUpdateTask_ReopenOnRecurrence(t *testing.T) {
	taskID := pgtype.UUID{Bytes: [16]byte{1}, Valid: true}
	userID := pgtype.UUID{Bytes: [16]byte{2}, Valid: true}
	completedTime := time.Date(2026, 6, 20, 15, 30, 0, 0, time.UTC)
	now := time.Now().UTC()
	expectedNextDue := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.UTC) // caught up to today

	var updatedParams sqlcgen.UpdateTaskParams

	repo := &mockRepository{
		getTaskByID: func(ctx context.Context, id pgtype.UUID, uID pgtype.UUID) (sqlcgen.Task, error) {
			return sqlcgen.Task{
				ID:          taskID,
				UserID:      userID,
				Status:      "done",
				CompletedAt: pgtype.Timestamptz{Time: completedTime, Valid: true},
			}, nil
		},
		updateTask: func(ctx context.Context, arg sqlcgen.UpdateTaskParams) (sqlcgen.Task, error) {
			updatedParams = arg
			return sqlcgen.Task{
				ID:         taskID,
				UserID:     userID,
				Status:     arg.Status.String,
				DueDate:    arg.DueDate,
				Recurrence: arg.Recurrence,
			}, nil
		},
	}

	svc := NewService(repo)
	recurrenceStr := "daily"
	opts := UpdateTaskOpts{
		Recurrence: &recurrenceStr,
	}

	task, err := svc.UpdateTask(context.Background(), userID, taskID, opts)
	if err != nil {
		t.Fatalf("UpdateTask failed: %v", err)
	}

	if !updatedParams.SetStatus.Bool || updatedParams.Status.String != "open" {
		t.Errorf("expected status to be updated to open, got SetStatus=%v, Status=%q", updatedParams.SetStatus.Bool, updatedParams.Status.String)
	}
	if !updatedParams.SetDueDate.Bool || !updatedParams.DueDate.Time.Equal(expectedNextDue) {
		t.Errorf("expected due date to be %v, got %v", expectedNextDue, updatedParams.DueDate.Time)
	}
	if !updatedParams.SetCompletedAt.Bool {
		t.Errorf("expected completed_at to be cleared")
	}

	if task.Status != "open" {
		t.Errorf("expected returned task status to be open, got %q", task.Status)
	}
}

