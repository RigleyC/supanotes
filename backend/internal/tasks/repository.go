package tasks

import (
	"context"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

type Repository interface {
	CreateTask(ctx context.Context, arg sqlcgen.CreateTaskParams) (sqlcgen.Task, error)
	GetTaskByID(ctx context.Context, id pgtype.UUID, userID pgtype.UUID) (sqlcgen.Task, error)
	UpdateTask(ctx context.Context, arg sqlcgen.UpdateTaskParams) (sqlcgen.Task, error)
	DeleteTask(ctx context.Context, id pgtype.UUID, userID pgtype.UUID) error
	GetTasks(ctx context.Context, arg sqlcgen.GetTasksParams) ([]sqlcgen.Task, error)
	GetTodayTasks(ctx context.Context, userID pgtype.UUID, upTo pgtype.Timestamptz) ([]sqlcgen.Task, error)
	GetTasksByNoteID(ctx context.Context, userID pgtype.UUID, noteID pgtype.UUID) ([]sqlcgen.Task, error)
	CreateTaskCompletion(ctx context.Context, taskID pgtype.UUID, status string) (sqlcgen.TaskCompletion, error)
}

type repository struct {
	q sqlcgen.Querier
}

func NewRepository(q sqlcgen.Querier) Repository {
	return &repository{q: q}
}

func (r *repository) CreateTask(ctx context.Context, arg sqlcgen.CreateTaskParams) (sqlcgen.Task, error) {
	return r.q.CreateTask(ctx, arg)
}

func (r *repository) GetTaskByID(ctx context.Context, id pgtype.UUID, userID pgtype.UUID) (sqlcgen.Task, error) {
	return r.q.GetTaskByID(ctx, sqlcgen.GetTaskByIDParams{ID: id, UserID: userID})
}

func (r *repository) UpdateTask(ctx context.Context, arg sqlcgen.UpdateTaskParams) (sqlcgen.Task, error) {
	return r.q.UpdateTask(ctx, arg)
}

func (r *repository) DeleteTask(ctx context.Context, id pgtype.UUID, userID pgtype.UUID) error {
	return r.q.DeleteTask(ctx, sqlcgen.DeleteTaskParams{ID: id, UserID: userID})
}

func (r *repository) GetTasks(ctx context.Context, arg sqlcgen.GetTasksParams) ([]sqlcgen.Task, error) {
	return r.q.GetTasks(ctx, arg)
}

func (r *repository) GetTodayTasks(ctx context.Context, userID pgtype.UUID, upTo pgtype.Timestamptz) ([]sqlcgen.Task, error) {
	return r.q.GetTodayTasks(ctx, sqlcgen.GetTodayTasksParams{UserID: userID, Column2: upTo})
}

func (r *repository) GetTasksByNoteID(ctx context.Context, userID pgtype.UUID, noteID pgtype.UUID) ([]sqlcgen.Task, error) {
	return r.q.GetTasksByNoteID(ctx, sqlcgen.GetTasksByNoteIDParams{UserID: userID, NoteID: noteID})
}

func (r *repository) CreateTaskCompletion(ctx context.Context, taskID pgtype.UUID, status string) (sqlcgen.TaskCompletion, error) {
	return r.q.CreateTaskCompletion(ctx, sqlcgen.CreateTaskCompletionParams{TaskID: taskID, Status: status})
}
