package notes

import (
	"context"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

type Repository interface {
	CreateNote(ctx context.Context, arg sqlcgen.CreateNoteParams) (sqlcgen.Note, error)
	GetNoteByID(ctx context.Context, id pgtype.UUID, userID pgtype.UUID) (sqlcgen.GetNoteByIDRow, error)
	UpdateNote(ctx context.Context, arg sqlcgen.UpdateNoteParams) (sqlcgen.Note, error)
	DeleteNote(ctx context.Context, id pgtype.UUID, userID pgtype.UUID) error
	GetNotes(ctx context.Context, arg sqlcgen.GetNotesParams) ([]sqlcgen.GetNotesRow, error)
	AppendToNoteContent(ctx context.Context, arg sqlcgen.AppendToNoteContentParams) (sqlcgen.Note, error)
	CountNotes(ctx context.Context, userID pgtype.UUID) (int64, error)
	GetNodesByNoteId(ctx context.Context, noteID pgtype.UUID) ([]sqlcgen.NoteNode, error)
	InsertNode(ctx context.Context, arg sqlcgen.InsertNodeParams) (sqlcgen.NoteNode, error)
	DeleteNodesByNoteID(ctx context.Context, noteID pgtype.UUID) error
	CreateTask(ctx context.Context, arg sqlcgen.CreateTaskParams) (sqlcgen.Task, error)
	DeleteTaskByNodeID(ctx context.Context, arg sqlcgen.DeleteTaskByNodeIDParams) error
	GetTasksByNoteID(ctx context.Context, userID pgtype.UUID, noteID pgtype.UUID) ([]sqlcgen.Task, error)
	WithQuerier(q sqlcgen.Querier) Repository
}

type repository struct {
	q sqlcgen.Querier
}

func NewRepository(q sqlcgen.Querier) Repository {
	return &repository{q: q}
}

func (r *repository) WithQuerier(q sqlcgen.Querier) Repository {
	return &repository{q: q}
}

func (r *repository) CreateNote(ctx context.Context, arg sqlcgen.CreateNoteParams) (sqlcgen.Note, error) {
	return r.q.CreateNote(ctx, arg)
}

func (r *repository) GetNoteByID(ctx context.Context, id pgtype.UUID, userID pgtype.UUID) (sqlcgen.GetNoteByIDRow, error) {
	return r.q.GetNoteByID(ctx, sqlcgen.GetNoteByIDParams{ID: id, UserID: userID})
}

func (r *repository) UpdateNote(ctx context.Context, arg sqlcgen.UpdateNoteParams) (sqlcgen.Note, error) {
	return r.q.UpdateNote(ctx, arg)
}

func (r *repository) DeleteNote(ctx context.Context, id pgtype.UUID, userID pgtype.UUID) error {
	return r.q.DeleteNote(ctx, sqlcgen.DeleteNoteParams{ID: id, UserID: userID})
}

func (r *repository) GetNotes(ctx context.Context, arg sqlcgen.GetNotesParams) ([]sqlcgen.GetNotesRow, error) {
	return r.q.GetNotes(ctx, arg)
}

func (r *repository) AppendToNoteContent(ctx context.Context, arg sqlcgen.AppendToNoteContentParams) (sqlcgen.Note, error) {
	return r.q.AppendToNoteContent(ctx, arg)
}

func (r *repository) CountNotes(ctx context.Context, userID pgtype.UUID) (int64, error) {
	return r.q.CountNotes(ctx, userID)
}

func (r *repository) GetNodesByNoteId(ctx context.Context, noteID pgtype.UUID) ([]sqlcgen.NoteNode, error) {
	return r.q.GetNodesByNoteId(ctx, noteID)
}

func (r *repository) InsertNode(ctx context.Context, arg sqlcgen.InsertNodeParams) (sqlcgen.NoteNode, error) {
	return r.q.InsertNode(ctx, arg)
}

func (r *repository) DeleteNodesByNoteID(ctx context.Context, noteID pgtype.UUID) error {
	return r.q.DeleteNodesByNoteID(ctx, noteID)
}

func (r *repository) CreateTask(ctx context.Context, arg sqlcgen.CreateTaskParams) (sqlcgen.Task, error) {
	return r.q.CreateTask(ctx, arg)
}

func (r *repository) DeleteTaskByNodeID(ctx context.Context, arg sqlcgen.DeleteTaskByNodeIDParams) error {
	return r.q.DeleteTaskByNodeID(ctx, arg)
}

func (r *repository) GetTasksByNoteID(ctx context.Context, userID pgtype.UUID, noteID pgtype.UUID) ([]sqlcgen.Task, error) {
	return r.q.GetTasksByNoteID(ctx, sqlcgen.GetTasksByNoteIDParams{
		UserID: userID,
		NoteID: noteID,
	})
}
