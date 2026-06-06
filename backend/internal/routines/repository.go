package routines

import (
	"context"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

type Repository interface {
	CreateRoutine(ctx context.Context, userID pgtype.UUID, rType string, cronExpr string, enabled bool) (sqlcgen.Routine, error)
	UpdateRoutine(ctx context.Context, id, userID pgtype.UUID, cronExpr *string, enabled *bool) (sqlcgen.Routine, error)
	GetRoutinesByUser(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.Routine, error)
	GetEnabledRoutines(ctx context.Context) ([]sqlcgen.GetEnabledRoutinesRow, error)
	CreateRoutineLog(ctx context.Context, routineID, userID pgtype.UUID, status string, content *string, errorMsg *string) (sqlcgen.RoutineLog, error)
	GetRoutineLogsByUser(ctx context.Context, userID pgtype.UUID, limit, offset int32) ([]sqlcgen.RoutineLog, error)
	CleanupOldMessages(ctx context.Context) error
	HardDeleteExpired(ctx context.Context) error
}

type repo struct {
	q sqlcgen.Querier
}

func NewRepository(q sqlcgen.Querier) Repository {
	return &repo{q: q}
}

func (r *repo) CreateRoutine(ctx context.Context, userID pgtype.UUID, rType string, cronExpr string, enabled bool) (sqlcgen.Routine, error) {
	return r.q.CreateRoutine(ctx, sqlcgen.CreateRoutineParams{
		UserID:   userID,
		Type:     rType,
		CronExpr: cronExpr,
		Enabled:  enabled,
	})
}

func (r *repo) UpdateRoutine(ctx context.Context, id, userID pgtype.UUID, cronExpr *string, enabled *bool) (sqlcgen.Routine, error) {
	var cExpr pgtype.Text
	if cronExpr != nil {
		cExpr = pgtype.Text{String: *cronExpr, Valid: true}
	}
	var en pgtype.Bool
	if enabled != nil {
		en = pgtype.Bool{Bool: *enabled, Valid: true}
	}
	return r.q.UpdateRoutine(ctx, sqlcgen.UpdateRoutineParams{
		ID:       id,
		UserID:   userID,
		CronExpr: cExpr,
		Enabled:  en,
	})
}

func (r *repo) GetRoutinesByUser(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.Routine, error) {
	return r.q.GetRoutinesByUser(ctx, userID)
}

func (r *repo) GetEnabledRoutines(ctx context.Context) ([]sqlcgen.GetEnabledRoutinesRow, error) {
	return r.q.GetEnabledRoutines(ctx)
}

func (r *repo) CreateRoutineLog(ctx context.Context, routineID, userID pgtype.UUID, status string, content *string, errorMsg *string) (sqlcgen.RoutineLog, error) {
	var c pgtype.Text
	if content != nil {
		c = pgtype.Text{String: *content, Valid: true}
	}
	var e pgtype.Text
	if errorMsg != nil {
		e = pgtype.Text{String: *errorMsg, Valid: true}
	}
	return r.q.CreateRoutineLog(ctx, sqlcgen.CreateRoutineLogParams{
		RoutineID: routineID,
		UserID:    userID,
		Status:    status,
		Content:   c,
		ErrorMsg:  e,
	})
}

func (r *repo) GetRoutineLogsByUser(ctx context.Context, userID pgtype.UUID, limit, offset int32) ([]sqlcgen.RoutineLog, error) {
	return r.q.GetRoutineLogsByUser(ctx, sqlcgen.GetRoutineLogsByUserParams{
		UserID: userID,
		Limit:  limit,
		Offset: offset,
	})
}

func (r *repo) CleanupOldMessages(ctx context.Context) error {
	return r.q.CleanupOldMessages(ctx)
}

// HardDeleteExpired purges notes, tasks, and contexts that have been
// soft-deleted for more than 30 days. Tags are skipped on purpose:
// the table has no deleted_at column yet.
func (r *repo) HardDeleteExpired(ctx context.Context) error {
	if err := r.q.HardDeleteExpiredNotes(ctx); err != nil {
		return err
	}
	if err := r.q.HardDeleteExpiredTasks(ctx); err != nil {
		return err
	}
	return r.q.HardDeleteExpiredContexts(ctx)
}
