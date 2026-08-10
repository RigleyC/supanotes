package sharelinks

import (
	"context"
	"errors"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

type sqlRepository struct {
	q sqlcgen.Querier
}

func NewRepository(q sqlcgen.Querier) Repository {
	return &sqlRepository{q: q}
}

func (r *sqlRepository) GetOwner(ctx context.Context, noteID uuid.UUID) (uuid.UUID, error) {
	value, err := r.q.GetNoteOwner(ctx, toPGUUID(noteID))
	if err != nil {
		return uuid.Nil, err
	}
	return fromPGUUID(value), nil
}

func (r *sqlRepository) GetByNote(ctx context.Context, noteID uuid.UUID) (Link, error) {
	value, err := r.q.GetNoteShareLink(ctx, toPGUUID(noteID))
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Link{}, ErrLinkNotFound
		}
		return Link{}, err
	}
	return Link{
		NoteID:  fromPGUUID(value.NoteID),
		TokenID: fromPGUUID(value.TokenID),
		Enabled: value.Enabled,
	}, nil
}

func (r *sqlRepository) Upsert(ctx context.Context, link Link) (Link, error) {
	value, err := r.q.UpsertNoteShareLink(ctx, sqlcgen.UpsertNoteShareLinkParams{
		NoteID:  toPGUUID(link.NoteID),
		TokenID: toPGUUID(link.TokenID),
	})
	if err != nil {
		return Link{}, err
	}
	return Link{
		NoteID:  fromPGUUID(value.NoteID),
		TokenID: fromPGUUID(value.TokenID),
		Enabled: value.Enabled,
	}, nil
}

func (r *sqlRepository) Disable(ctx context.Context, noteID uuid.UUID) error {
	return r.q.DisableNoteShareLink(ctx, toPGUUID(noteID))
}

func (r *sqlRepository) GetPublicNote(ctx context.Context, tokenID uuid.UUID) (PublicNote, error) {
	value, err := r.q.GetPublicNoteByShareToken(ctx, toPGUUID(tokenID))
	if err != nil {
		return PublicNote{}, err
	}
	return PublicNote{ID: fromPGUUID(value.ID), Document: value.Document}, nil
}

func toPGUUID(value uuid.UUID) pgtype.UUID {
	return pgtype.UUID{Bytes: value, Valid: value != uuid.Nil}
}

func fromPGUUID(value pgtype.UUID) uuid.UUID {
	if !value.Valid {
		return uuid.Nil
	}
	return uuid.UUID(value.Bytes)
}
