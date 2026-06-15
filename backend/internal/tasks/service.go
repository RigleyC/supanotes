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
		arg.DueDate = pgtype.Date{Time: *dueDate, Valid: true}
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

func (s *Service) UpdateTask(ctx context.Context, userID, id pgtype.UUID, title *string, status *string, dueDate *time.Time, clearDueDate bool, recurrence *string, clearRecurrence bool, position *int) (sqlcgen.Task, error) {
	arg := sqlcgen.UpdateTaskParams{
		ID:     id,
		UserID: userID,
	}
	if title != nil {
		arg.SetTitle = pgtype.Bool{Bool: true, Valid: true}
		arg.Title = pgtype.Text{String: *title, Valid: true}
	}
	if status != nil {
		arg.SetStatus = pgtype.Bool{Bool: true, Valid: true}
		arg.Status = pgtype.Text{String: *status, Valid: true}
	}
	if dueDate != nil {
		arg.SetDueDate = pgtype.Bool{Bool: true, Valid: true}
		arg.DueDate = pgtype.Date{Time: *dueDate, Valid: true}
	} else if clearDueDate {
		arg.SetDueDate = pgtype.Bool{Bool: true, Valid: true}
		// arg.DueDate stays as zero value, Valid: false -> SQL receives NULL
	}
	if recurrence != nil {
		arg.SetRecurrence = pgtype.Bool{Bool: true, Valid: true}
		arg.Recurrence = pgtype.Text{String: *recurrence, Valid: true}
	} else if clearRecurrence {
		arg.SetRecurrence = pgtype.Bool{Bool: true, Valid: true}
		// arg.Recurrence stays as zero value -> NULL
	}
	if position != nil {
		arg.SetPosition = pgtype.Bool{Bool: true, Valid: true}
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
		nextDue, ok := calculateNextDueDate(task.DueDate.Time, task.Recurrence.String)
		if ok {
			task, err = s.repo.UpdateTask(ctx, sqlcgen.UpdateTaskParams{
				ID:         id,
				UserID:     userID,
				SetDueDate: pgtype.Bool{Bool: true, Valid: true},
				DueDate:    pgtype.Date{Time: nextDue, Valid: true},
				SetStatus:  pgtype.Bool{Bool: true, Valid: true},
				Status:     pgtype.Text{String: "open", Valid: true},
			})
			if err != nil {
				if errors.Is(err, pgx.ErrNoRows) {
					return sqlcgen.Task{}, ErrTaskNotFound
				}
				return sqlcgen.Task{}, err
			}
			return task, nil
		}
	}

	// Non-recurring: mark completed
	now := time.Now()
	task, err = s.repo.UpdateTask(ctx, sqlcgen.UpdateTaskParams{
		ID:             id,
		UserID:         userID,
		SetStatus:      pgtype.Bool{Bool: true, Valid: true},
		Status:         pgtype.Text{String: "done", Valid: true},
		SetCompletedAt: pgtype.Bool{Bool: true, Valid: true},
		CompletedAt:    pgtype.Timestamptz{Time: now, Valid: true},
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
		ID:        id,
		UserID:    userID,
		SetStatus: pgtype.Bool{Bool: true, Valid: true},
		Status:    pgtype.Text{String: "open", Valid: true},
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
		arg.DueAfter = pgtype.Date{Time: *dueAfter, Valid: true}
	}
	if dueBefore != nil {
		arg.DueBefore = pgtype.Date{Time: *dueBefore, Valid: true}
	}

	return s.repo.GetTasks(ctx, arg)
}

func (s *Service) GetTodayTasks(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.Task, error) {
	// Em produção real, este `now` deve estar no timezone do usuário.
	now := time.Now()
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	return s.repo.GetTodayTasks(ctx, userID, pgtype.Date{Time: today, Valid: true})
}

func calculateNextDueDate(current time.Time, recurrence string) (time.Time, bool) {
	switch recurrence {
	case "daily":
		return current.AddDate(0, 0, 1), true
	case "weekdays":
		next := current.AddDate(0, 0, 1)
		for next.Weekday() == time.Saturday || next.Weekday() == time.Sunday {
			next = next.AddDate(0, 0, 1)
		}
		return next, true
	case "weekly":
		return current.AddDate(0, 0, 7), true
	case "monthly":
		return current.AddDate(0, 1, 0), true
	default:
		return time.Time{}, false
	}
}
