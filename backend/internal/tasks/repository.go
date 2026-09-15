package tasks

import (
	"context"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Repository interface {
	WithTx(context.Context, func(Repository) error) error
	WithQuerier(sqlcgen.Querier) Repository
	ListTasks(context.Context, pgtype.UUID) ([]sqlcgen.Task, error)
	GetTask(context.Context, pgtype.UUID, pgtype.UUID) (sqlcgen.Task, error)
	LockTask(context.Context, pgtype.UUID, pgtype.UUID) (sqlcgen.Task, error)
	GetOperation(context.Context, pgtype.UUID) (sqlcgen.TaskOperation, error)
	InsertTask(context.Context, sqlcgen.InsertTaskParams) (sqlcgen.Task, error)
	UpdateTask(context.Context, sqlcgen.UpdateTaskParams) (sqlcgen.Task, error)
	InsertOperation(context.Context, sqlcgen.InsertTaskOperationParams) error
	InsertChange(context.Context, sqlcgen.InsertTaskSyncChangeParams) error
	Watermark(context.Context, pgtype.UUID) (int64, error)
}

type repository struct {
	q    sqlcgen.Querier
	pool *pgxpool.Pool
}

func NewRepository(q sqlcgen.Querier, pool *pgxpool.Pool) Repository {
	return &repository{q: q, pool: pool}
}
func (r *repository) WithTx(ctx context.Context, fn func(Repository) error) error {
	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return err
	}
	if err = fn(r.WithQuerier(sqlcgen.New(tx))); err != nil {
		_ = tx.Rollback(ctx)
		return err
	}
	return tx.Commit(ctx)
}
func (r *repository) WithQuerier(q sqlcgen.Querier) Repository {
	return &repository{q: q, pool: r.pool}
}
func (r *repository) ListTasks(c context.Context, id pgtype.UUID) ([]sqlcgen.Task, error) {
	return r.q.ListTasksForBootstrap(c, id)
}
func (r *repository) GetTask(c context.Context, id, user pgtype.UUID) (sqlcgen.Task, error) {
	return r.q.GetTaskForOwner(c, sqlcgen.GetTaskForOwnerParams{ID: id, OwnerUserID: user})
}
func (r *repository) LockTask(c context.Context, id, user pgtype.UUID) (sqlcgen.Task, error) {
	return r.q.LockTaskForOwner(c, sqlcgen.LockTaskForOwnerParams{ID: id, OwnerUserID: user})
}
func (r *repository) GetOperation(c context.Context, id pgtype.UUID) (sqlcgen.TaskOperation, error) {
	return r.q.GetTaskOperation(c, id)
}
func (r *repository) InsertTask(c context.Context, a sqlcgen.InsertTaskParams) (sqlcgen.Task, error) {
	return r.q.InsertTask(c, a)
}
func (r *repository) UpdateTask(c context.Context, a sqlcgen.UpdateTaskParams) (sqlcgen.Task, error) {
	return r.q.UpdateTask(c, a)
}
func (r *repository) InsertOperation(c context.Context, a sqlcgen.InsertTaskOperationParams) error {
	return r.q.InsertTaskOperation(c, a)
}
func (r *repository) InsertChange(c context.Context, a sqlcgen.InsertTaskSyncChangeParams) error {
	return r.q.InsertTaskSyncChange(c, a)
}
func (r *repository) Watermark(c context.Context, id pgtype.UUID) (int64, error) {
	return r.q.GetTaskWatermark(c, id)
}

func (r *repository) Begin(c context.Context) (pgx.Tx, error) {
	return r.pool.BeginTx(c, pgx.TxOptions{IsoLevel: pgx.ReadCommitted})
}
