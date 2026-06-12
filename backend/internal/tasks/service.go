package tasks

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

var (
	ErrTaskNotFound = errors.New("task not found")
)

type Service struct {
	repo Repository
}

func NewService(repo Repository) *Service {
	return &Service{repo: repo}
}

func (s *Service) CreateTask(ctx context.Context, userID, noteID pgtype.UUID, title string, dueDate *time.Time, recurrence *string, position int) (sqlcgen.Task, error) {
	arg := sqlcgen.CreateTaskParams{
		NoteID:   noteID,
		UserID:   userID,
		Title:    title,
		Position: int32(position),
	}
	if dueDate != nil {
		arg.DueDate = pgtype.Timestamptz{Time: *dueDate, Valid: true}
	}
	if recurrence != nil {
		arg.Recurrence = pgtype.Text{String: *recurrence, Valid: true}
	}
	return s.repo.CreateTask(ctx, arg)
}

func (s *Service) GetTaskByID(ctx context.Context, id pgtype.UUID, userID pgtype.UUID) (sqlcgen.Task, error) {
	task, err := s.repo.GetTaskByID(ctx, id, userID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return sqlcgen.Task{}, ErrTaskNotFound
		}
		return sqlcgen.Task{}, err
	}
	return task, nil
}

func (s *Service) UpdateTask(ctx context.Context, userID, id pgtype.UUID, title *string, status *string, dueDate *time.Time, recurrence *string, position *int) (sqlcgen.Task, error) {
	arg := sqlcgen.UpdateTaskParams{
		ID:     id,
		UserID: userID,
	}
	if title != nil {
		arg.Title = pgtype.Text{String: *title, Valid: true}
	}
	if status != nil {
		arg.Status = pgtype.Text{String: *status, Valid: true}
	}
	if dueDate != nil {
		arg.DueDate = pgtype.Timestamptz{Time: *dueDate, Valid: true}
	}
	if recurrence != nil {
		arg.Recurrence = pgtype.Text{String: *recurrence, Valid: true}
	}
	if position != nil {
		arg.Position = pgtype.Int4{Int32: int32(*position), Valid: true}
	}

	task, err := s.repo.UpdateTask(ctx, arg)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return sqlcgen.Task{}, ErrTaskNotFound
		}
		return sqlcgen.Task{}, err
	}
	return task, nil
}

func (s *Service) DeleteTask(ctx context.Context, userID, id pgtype.UUID) error {
	if err := s.repo.DeleteTask(ctx, id, userID); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrTaskNotFound
		}
		return err
	}
	return nil
}

func (s *Service) CompleteTask(ctx context.Context, userID, id pgtype.UUID) (sqlcgen.Task, error) {
	task, err := s.repo.GetTaskByID(ctx, id, userID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return sqlcgen.Task{}, ErrTaskNotFound
		}
		return sqlcgen.Task{}, err
	}

	dueDate := pgtype.Date{}
	if task.DueDate.Valid {
		dueDate = pgtype.Date{Time: task.DueDate.Time, Valid: true}
	}
	if _, err := s.repo.CreateTaskCompletion(ctx, id, dueDate); err != nil {
		return sqlcgen.Task{}, err
	}

	// Recurring task: calculate next due_date, keep 'open'
	if task.Recurrence.Valid && task.Recurrence.String != "" && task.DueDate.Valid {
		nextDue := calculateNextDueDate(task.DueDate.Time, task.Recurrence.String)
		task, err = s.repo.UpdateTask(ctx, sqlcgen.UpdateTaskParams{
			ID:      id,
			UserID:  userID,
			DueDate: pgtype.Timestamptz{Time: nextDue, Valid: true},
			Status:  pgtype.Text{String: "open", Valid: true},
		})
		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return sqlcgen.Task{}, ErrTaskNotFound
			}
			return sqlcgen.Task{}, err
		}
		return task, nil
	}

	// Non-recurring: mark completed
	now := time.Now()
	task, err = s.repo.UpdateTask(ctx, sqlcgen.UpdateTaskParams{
		ID:          id,
		UserID:      userID,
		Status:      pgtype.Text{String: "done", Valid: true},
		CompletedAt: pgtype.Timestamptz{Time: now, Valid: true},
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return sqlcgen.Task{}, ErrTaskNotFound
		}
		return sqlcgen.Task{}, err
	}
	return task, nil
}

func (s *Service) ReopenTask(ctx context.Context, userID, id pgtype.UUID) (sqlcgen.Task, error) {
	task, err := s.repo.UpdateTask(ctx, sqlcgen.UpdateTaskParams{
		ID:     id,
		UserID: userID,
		Status: pgtype.Text{String: "open", Valid: true},
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return sqlcgen.Task{}, ErrTaskNotFound
		}
		return sqlcgen.Task{}, err
	}
	return task, nil
}

func (s *Service) GetTasks(ctx context.Context, userID pgtype.UUID, noteID *pgtype.UUID, status *string, dueBefore, dueAfter *time.Time, limit int32, offset int32) ([]sqlcgen.Task, error) {
	arg := sqlcgen.GetTasksParams{
		UserID: userID,
		Limit:  limit,
		Offset: offset,
	}
	if noteID != nil {
		arg.NoteID = *noteID
	}
	if status != nil {
		arg.Status = pgtype.Text{String: *status, Valid: true}
	}
	if dueAfter != nil {
		arg.DueAfter = pgtype.Timestamptz{Time: *dueAfter, Valid: true}
	}
	if dueBefore != nil {
		arg.DueBefore = pgtype.Timestamptz{Time: *dueBefore, Valid: true}
	}

	return s.repo.GetTasks(ctx, arg)
}

func (s *Service) GetTodayTasks(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.Task, error) {
	// Em produção real, este `now` deve estar no timezone do usuário.
	// Por simplicidade aqui, usando a hora atual no final do dia.
	now := time.Now()
	upTo := time.Date(now.Year(), now.Month(), now.Day(), 23, 59, 59, 0, now.Location())
	return s.repo.GetTodayTasks(ctx, userID, pgtype.Timestamptz{Time: upTo, Valid: true})
}

func calculateNextDueDate(current time.Time, recurrence string) time.Time {
	switch recurrence {
	case "daily":
		return current.AddDate(0, 0, 1)
	case "weekdays":
		next := current.AddDate(0, 0, 1)
		for next.Weekday() == time.Saturday || next.Weekday() == time.Sunday {
			next = next.AddDate(0, 0, 1)
		}
		return next
	case "weekly":
		return current.AddDate(0, 0, 7)
	case "monthly":
		return current.AddDate(0, 1, 0)
	default:
		return current // Não suportado
	}
}
