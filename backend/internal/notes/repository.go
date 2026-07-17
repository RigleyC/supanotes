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


