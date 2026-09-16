package tasks

import (
	"context"
	"errors"

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
			out.Tasks = append(out.Tasks, taskFromRow(row))
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
	return taskFromRow(row), nil
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
