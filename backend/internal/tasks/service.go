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

// UpdateTaskOpts expresses the tri-state (set / clear / leave alone)
// for each nullable field on a task. The pointer fields default to
// "leave alone"; setting a pointer to a non-nil value means "set"; the
// Clear* bool fields mean "explicitly clear" (must not be combined with
// a non-nil value for the same field).
type UpdateTaskOpts struct {
	Title           *string
	Status          *string
	DueDate         *time.Time
	ClearDueDate    bool
	Recurrence      *string
	ClearRecurrence bool
	Position        *string
	HasTime         *bool
	Reminder        *string
	ClearReminder   bool
}

// Validate catches conflicting "set" + "clear" inputs early so callers
// can't accidentally pass both DueDate != nil and ClearDueDate = true.
func (o UpdateTaskOpts) Validate() error {
	if o.DueDate != nil && o.ClearDueDate {
		return errors.New("due_date and clear_due_date are mutually exclusive")
	}
	if o.Recurrence != nil && o.ClearRecurrence {
		return errors.New("recurrence and clear_recurrence are mutually exclusive")
	}
	return nil
}

type Service struct {
	repo Repository
}

func NewService(repo Repository) *Service {
	return &Service{repo: repo}
}

func (s *Service) CreateTask(ctx context.Context, userID, noteID pgtype.UUID, title string, dueDate *time.Time, recurrence *string, position string, hasTime *bool, reminder *string) (sqlcgen.Task, error) {
	arg := sqlcgen.CreateTaskParams{
		NoteID:   noteID,
		UserID:   userID,
		Title:    title,
		Position: position,
	}
	if dueDate != nil {
		arg.DueDate = pgtype.Timestamptz{Time: *dueDate, Valid: true}
	}
	if recurrence != nil {
		arg.Recurrence = pgtype.Text{String: *recurrence, Valid: true}
	}
	if hasTime != nil {
		arg.HasTime = *hasTime
	}
	if reminder != nil {
		arg.Reminder = pgtype.Text{String: *reminder, Valid: true}
	}
	task, err := s.repo.CreateTask(ctx, arg)
	if err != nil {
		return sqlcgen.Task{}, err
	}
	return task, nil
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

func (s *Service) UpdateTask(ctx context.Context, userID, id pgtype.UUID, opts UpdateTaskOpts) (sqlcgen.Task, error) {
	if err := opts.Validate(); err != nil {
		return sqlcgen.Task{}, err
	}

	arg := sqlcgen.UpdateTaskParams{
		ID:     id,
		UserID: userID,
	}
	if opts.Title != nil {
		arg.SetTitle = pgtype.Bool{Bool: true, Valid: true}
		arg.Title = pgtype.Text{String: *opts.Title, Valid: true}
	}
	if opts.Status != nil {
		arg.SetStatus = pgtype.Bool{Bool: true, Valid: true}
		arg.Status = pgtype.Text{String: *opts.Status, Valid: true}
	}
	if opts.DueDate != nil {
		arg.SetDueDate = pgtype.Bool{Bool: true, Valid: true}
		arg.DueDate = pgtype.Timestamptz{Time: *opts.DueDate, Valid: true}
	} else if opts.ClearDueDate {
		arg.SetDueDate = pgtype.Bool{Bool: true, Valid: true}
	}
	if opts.Recurrence != nil {
		arg.SetRecurrence = pgtype.Bool{Bool: true, Valid: true}
		arg.Recurrence = pgtype.Text{String: *opts.Recurrence, Valid: true}
	} else if opts.ClearRecurrence {
		arg.SetRecurrence = pgtype.Bool{Bool: true, Valid: true}
	}
	if opts.Position != nil {
		arg.SetPosition = pgtype.Bool{Bool: true, Valid: true}
		arg.Position = pgtype.Text{String: *opts.Position, Valid: true}
	}
	if opts.HasTime != nil {
		arg.SetHasTime = pgtype.Bool{Bool: true, Valid: true}
		arg.HasTime = pgtype.Bool{Bool: *opts.HasTime, Valid: true}
	}
	if opts.Reminder != nil {
		arg.SetReminder = pgtype.Bool{Bool: true, Valid: true}
		arg.Reminder = pgtype.Text{String: *opts.Reminder, Valid: true}
	} else if opts.ClearReminder {
		arg.SetReminder = pgtype.Bool{Bool: true, Valid: true}
	}

	// Clear completed_at when re-opening
	if opts.Status != nil && *opts.Status == "open" {
		arg.SetCompletedAt = pgtype.Bool{Bool: true, Valid: true}
		// CompletedAt stays zero-value (NULL)
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

	// Re-read after projection to return projected state
	task, err = s.repo.GetTaskByID(ctx, id, userID)
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
	return s.GetTodayTasksInTimezone(ctx, userID, time.Now().Location())
}

func (s *Service) GetTodayTasksInTimezone(ctx context.Context, userID pgtype.UUID, loc *time.Location) ([]sqlcgen.Task, error) {
	now := time.Now().In(loc)
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	return s.repo.GetTodayTasks(ctx, userID, pgtype.Date{Time: today, Valid: true})
}

func (s *Service) SearchTasks(ctx context.Context, userID pgtype.UUID, query string, status *string, limit, offset int32) ([]sqlcgen.Task, error) {
	arg := sqlcgen.SearchTasksParams{
		UserID: userID,
		Query:  query,
		Limit:  limit,
		Offset: offset,
	}
	if status != nil {
		arg.Status = pgtype.Text{String: *status, Valid: true}
	}
	return s.repo.SearchTasks(ctx, arg)
}

func (s *Service) GetRecentlyCompletedTasks(ctx context.Context, userID pgtype.UUID, days int32) ([]sqlcgen.Task, error) {
	return s.repo.GetRecentlyCompletedTasks(ctx, sqlcgen.GetRecentlyCompletedTasksParams{
		UserID: userID,
		Days:   days,
	})
}
