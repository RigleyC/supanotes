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
	WithReadTx(context.Context, func(Repository) error) error
	WithQuerier(sqlcgen.Querier) Repository
	ListTasks(context.Context, pgtype.UUID) ([]taskRow, error)
	GetTask(context.Context, pgtype.UUID, pgtype.UUID) (taskRow, error)
	LockTask(context.Context, pgtype.UUID, pgtype.UUID) (taskRow, error)
	GetOperation(context.Context, pgtype.UUID, pgtype.UUID) (taskOperationRow, error)
	InsertTask(context.Context, taskInsert) (taskRow, error)
	UpdateTask(context.Context, taskUpdate) (taskRow, error)
	InsertOperation(context.Context, taskOperationInsert) error
	InsertChange(context.Context, taskChange) error
	Watermark(context.Context, pgtype.UUID) (int64, error)
}

// These types are the persistence boundary for the task domain. SQLC rows and
// arguments are translated here so mutation/domain code does not depend on
// generated database details.
type taskRow struct {
	ID                 pgtype.UUID
	OwnerUserID        pgtype.UUID
	Title              string
	DueDate            pgtype.Timestamp
	HasTime            bool
	RecurrenceRule     pgtype.Text
	Reminder           pgtype.Text
	Completions        []byte
	CompletionHistory  []byte
	IsCompleted        bool
	LastCompletedAt    pgtype.Timestamptz
	Revision           int64
	ScheduleGeneration int64
	CreatedAt          pgtype.Timestamptz
	UpdatedAt          pgtype.Timestamptz
	DeletedAt          pgtype.Timestamptz
}

type taskOperationRow struct {
	TaskID       pgtype.UUID
	OperationID  pgtype.UUID
	PayloadHash  string
	ResponseJSON []byte
}

type taskInsert struct {
	ID                 pgtype.UUID
	OwnerUserID        pgtype.UUID
	Title              string
	DueDate            pgtype.Timestamp
	HasTime            bool
	RecurrenceRule     pgtype.Text
	Reminder           pgtype.Text
	Completions        []byte
	CompletionHistory  []byte
	IsCompleted        bool
	LastCompletedAt    pgtype.Timestamptz
	ScheduleGeneration int64
}

type taskUpdate struct {
	ID                 pgtype.UUID
	OwnerUserID        pgtype.UUID
	Title              string
	DueDate            pgtype.Timestamp
	HasTime            bool
	RecurrenceRule     pgtype.Text
	Reminder           pgtype.Text
	Completions        []byte
	CompletionHistory  []byte
	IsCompleted        bool
	LastCompletedAt    pgtype.Timestamptz
	ScheduleGeneration int64
	DeletedAt          pgtype.Timestamptz
}

type taskOperationInsert struct {
	TaskID       pgtype.UUID
	OperationID  pgtype.UUID
	PayloadHash  string
	ResponseJSON []byte
}

type taskChange struct {
	TargetUserID pgtype.UUID
	Kind         string
	TaskID       pgtype.UUID
	Revision     int64
}

type repository struct {
	q    sqlcgen.Querier
	pool *pgxpool.Pool
}

func NewRepository(q sqlcgen.Querier, pool *pgxpool.Pool) Repository {
	return &repository{q: q, pool: pool}
}
func (r *repository) WithTx(ctx context.Context, fn func(Repository) error) error {
	return r.withTx(ctx, pgx.TxOptions{}, fn)
}

func (r *repository) WithReadTx(ctx context.Context, fn func(Repository) error) error {
	return r.withTx(ctx, pgx.TxOptions{
		IsoLevel:   pgx.RepeatableRead,
		AccessMode: pgx.ReadOnly,
	}, fn)
}

func (r *repository) withTx(ctx context.Context, options pgx.TxOptions, fn func(Repository) error) error {
	tx, err := r.pool.BeginTx(ctx, options)
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
func (r *repository) ListTasks(c context.Context, id pgtype.UUID) ([]taskRow, error) {
	rows, err := r.q.ListTasksForBootstrap(c, id)
	if err != nil {
		return nil, err
	}
	result := make([]taskRow, 0, len(rows))
	for _, row := range rows {
		result = append(result, taskRowFromSQL(row))
	}
	return result, nil
}
func (r *repository) GetTask(c context.Context, id, user pgtype.UUID) (taskRow, error) {
	row, err := r.q.GetTaskForOwner(c, sqlcgen.GetTaskForOwnerParams{ID: id, OwnerUserID: user})
	return taskRowFromSQL(row), err
}
func (r *repository) LockTask(c context.Context, id, user pgtype.UUID) (taskRow, error) {
	row, err := r.q.LockTaskForOwner(c, sqlcgen.LockTaskForOwnerParams{ID: id, OwnerUserID: user})
	return taskRowFromSQL(row), err
}
func (r *repository) GetOperation(c context.Context, taskID, operationID pgtype.UUID) (taskOperationRow, error) {
	row, err := r.q.GetTaskOperation(c, sqlcgen.GetTaskOperationParams{TaskID: taskID, OperationID: operationID})
	return taskOperationRow{TaskID: row.TaskID, OperationID: row.OperationID, PayloadHash: row.PayloadHash, ResponseJSON: row.ResponseJson}, err
}
func (r *repository) InsertTask(c context.Context, a taskInsert) (taskRow, error) {
	row, err := r.q.InsertTask(c, sqlcgen.InsertTaskParams{
		ID: a.ID, OwnerUserID: a.OwnerUserID, Title: a.Title, DueDate: a.DueDate,
		HasTime: a.HasTime, RecurrenceRule: a.RecurrenceRule, Reminder: a.Reminder,
		Completions: a.Completions, CompletionHistory: a.CompletionHistory, IsCompleted: a.IsCompleted,
		LastCompletedAt: a.LastCompletedAt, ScheduleGeneration: a.ScheduleGeneration,
	})
	return taskRowFromSQL(row), err
}
func (r *repository) UpdateTask(c context.Context, a taskUpdate) (taskRow, error) {
	row, err := r.q.UpdateTask(c, sqlcgen.UpdateTaskParams{
		ID: a.ID, OwnerUserID: a.OwnerUserID, Title: a.Title, DueDate: a.DueDate,
		HasTime: a.HasTime, RecurrenceRule: a.RecurrenceRule, Reminder: a.Reminder,
		Completions: a.Completions, CompletionHistory: a.CompletionHistory, IsCompleted: a.IsCompleted,
		LastCompletedAt: a.LastCompletedAt, ScheduleGeneration: a.ScheduleGeneration,
		DeletedAt: a.DeletedAt,
	})
	return taskRowFromSQL(row), err
}
func (r *repository) InsertOperation(c context.Context, a taskOperationInsert) error {
	return r.q.InsertTaskOperation(c, sqlcgen.InsertTaskOperationParams{
		TaskID: a.TaskID, OperationID: a.OperationID, PayloadHash: a.PayloadHash, ResponseJson: a.ResponseJSON,
	})
}
func (r *repository) InsertChange(c context.Context, a taskChange) error {
	return r.q.InsertTaskSyncChange(c, sqlcgen.InsertTaskSyncChangeParams{
		TargetUserID: a.TargetUserID, Kind: a.Kind, TaskID: a.TaskID,
		Revision: pgtype.Int8{Int64: a.Revision, Valid: true},
	})
}
func (r *repository) Watermark(c context.Context, id pgtype.UUID) (int64, error) {
	return r.q.GetTaskWatermark(c, id)
}

func taskRowFromSQL(row sqlcgen.Task) taskRow {
	return taskRow{
		ID: row.ID, OwnerUserID: row.OwnerUserID, Title: row.Title, DueDate: row.DueDate,
		HasTime: row.HasTime, RecurrenceRule: row.RecurrenceRule, Reminder: row.Reminder,
		Completions: row.Completions, IsCompleted: row.IsCompleted,
		CompletionHistory: row.CompletionHistory,
		LastCompletedAt:   row.LastCompletedAt, Revision: row.Revision,
		ScheduleGeneration: row.ScheduleGeneration, CreatedAt: row.CreatedAt,
		UpdatedAt: row.UpdatedAt, DeletedAt: row.DeletedAt,
	}
}
