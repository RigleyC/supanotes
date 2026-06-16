package shares

import (
	"context"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

type Repository interface {
	GetNoteOwner(ctx context.Context, noteID pgtype.UUID) (pgtype.UUID, error)
	GetUserByEmail(ctx context.Context, email string) (sqlcgen.User, error)
	CreateNoteShare(ctx context.Context, arg sqlcgen.CreateNoteShareParams) (sqlcgen.NoteShare, error)
	GetNoteShares(ctx context.Context, noteID pgtype.UUID) ([]sqlcgen.GetNoteSharesRow, error)
	DeleteNoteShare(ctx context.Context, arg sqlcgen.DeleteNoteShareParams) error
}

type repository struct {
	q sqlcgen.Querier
}

func NewRepository(q sqlcgen.Querier) Repository {
	return &repository{q: q}
}

func (r *repository) GetNoteOwner(ctx context.Context, noteID pgtype.UUID) (pgtype.UUID, error) {
	return r.q.GetNoteOwner(ctx, noteID)
}

func (r *repository) GetUserByEmail(ctx context.Context, email string) (sqlcgen.User, error) {
	return r.q.GetUserByEmail(ctx, email)
}

func (r *repository) CreateNoteShare(ctx context.Context, arg sqlcgen.CreateNoteShareParams) (sqlcgen.NoteShare, error) {
	return r.q.CreateNoteShare(ctx, arg)
}

func (r *repository) GetNoteShares(ctx context.Context, noteID pgtype.UUID) ([]sqlcgen.GetNoteSharesRow, error) {
	return r.q.GetNoteShares(ctx, noteID)
}

func (r *repository) DeleteNoteShare(ctx context.Context, arg sqlcgen.DeleteNoteShareParams) error {
	return r.q.DeleteNoteShare(ctx, arg)
}
