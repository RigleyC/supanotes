package notes

import (
	"context"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

type Repository interface {
	CreateNote(ctx context.Context, arg sqlcgen.CreateNoteParams) (sqlcgen.Note, error)
	GetNoteByID(ctx context.Context, id pgtype.UUID, userID pgtype.UUID) (sqlcgen.Note, error)
	UpdateNote(ctx context.Context, arg sqlcgen.UpdateNoteParams) (sqlcgen.Note, error)
	DeleteNote(ctx context.Context, id pgtype.UUID, userID pgtype.UUID) error
	GetNotes(ctx context.Context, arg sqlcgen.GetNotesParams) ([]sqlcgen.Note, error)
	GetInboxNote(ctx context.Context, userID pgtype.UUID) (sqlcgen.Note, error)
	AppendToInbox(ctx context.Context, arg sqlcgen.AppendToInboxParams) (sqlcgen.Note, error)
	SetInboxContent(ctx context.Context, arg sqlcgen.SetInboxContentParams) (sqlcgen.Note, error)
	AppendToNoteContent(ctx context.Context, arg sqlcgen.AppendToNoteContentParams) (sqlcgen.Note, error)
}

type repository struct {
	q sqlcgen.Querier
}

func NewRepository(q sqlcgen.Querier) Repository {
	return &repository{q: q}
}

func (r *repository) CreateNote(ctx context.Context, arg sqlcgen.CreateNoteParams) (sqlcgen.Note, error) {
	return r.q.CreateNote(ctx, arg)
}

func (r *repository) GetNoteByID(ctx context.Context, id pgtype.UUID, userID pgtype.UUID) (sqlcgen.Note, error) {
	return r.q.GetNoteByID(ctx, sqlcgen.GetNoteByIDParams{ID: id, UserID: userID})
}

func (r *repository) UpdateNote(ctx context.Context, arg sqlcgen.UpdateNoteParams) (sqlcgen.Note, error) {
	return r.q.UpdateNote(ctx, arg)
}

func (r *repository) DeleteNote(ctx context.Context, id pgtype.UUID, userID pgtype.UUID) error {
	return r.q.DeleteNote(ctx, sqlcgen.DeleteNoteParams{ID: id, UserID: userID})
}

func (r *repository) GetNotes(ctx context.Context, arg sqlcgen.GetNotesParams) ([]sqlcgen.Note, error) {
	return r.q.GetNotes(ctx, arg)
}

func (r *repository) GetInboxNote(ctx context.Context, userID pgtype.UUID) (sqlcgen.Note, error) {
	return r.q.GetInboxNote(ctx, userID)
}

func (r *repository) AppendToInbox(ctx context.Context, arg sqlcgen.AppendToInboxParams) (sqlcgen.Note, error) {
	return r.q.AppendToInbox(ctx, arg)
}

func (r *repository) SetInboxContent(ctx context.Context, arg sqlcgen.SetInboxContentParams) (sqlcgen.Note, error) {
	return r.q.SetInboxContent(ctx, arg)
}

func (r *repository) AppendToNoteContent(ctx context.Context, arg sqlcgen.AppendToNoteContentParams) (sqlcgen.Note, error) {
	return r.q.AppendToNoteContent(ctx, arg)
}
