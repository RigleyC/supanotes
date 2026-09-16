package shares

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/pkg/uid"
)

var (
	ErrNoteNotFound        = errors.New("note not found")
	ErrNotOwner            = errors.New("only the note owner can manage shares")
	ErrUserNotFound        = errors.New("user not found")
	ErrCannotShareWithSelf = errors.New("cannot share with yourself")
)

type ShareResult struct {
	ID         string `json:"id"`
	NoteID     string `json:"note_id"`
	UserID     string `json:"user_id"`
	Email      string `json:"email"`
	Name       string `json:"name"`
	Permission string `json:"permission"`
}

type Service struct {
	repo Repository
}

func NewService(repo Repository) *Service {
	return &Service{repo: repo}
}

func (s *Service) ShareNote(ctx context.Context, ownerID pgtype.UUID, noteID pgtype.UUID, email, permission string) (ShareResult, error) {
	return shareNote(ctx, s.repo, ownerID, noteID, email, permission)
}

// ShareNoteInTransaction keeps the share upsert in the same transaction as
// the MCP confirmation result. The unique (note_id, user_id) key makes a
// recovered execution an upsert of the same logical share, never a duplicate.
func (s *Service) ShareNoteInTransaction(ctx context.Context, tx pgx.Tx, ownerID pgtype.UUID, noteID pgtype.UUID, email, permission string) (ShareResult, error) {
	repo, ok := s.repo.(interface {
		WithQuerier(sqlcgen.Querier) Repository
	})
	if !ok || tx == nil {
		return ShareResult{}, errors.New("share transaction is not configured")
	}
	return shareNote(ctx, repo.WithQuerier(sqlcgen.New(tx)), ownerID, noteID, email, permission)
}

func shareNote(ctx context.Context, repo Repository, ownerID pgtype.UUID, noteID pgtype.UUID, email, permission string) (ShareResult, error) {
	noteOwnerID, err := repo.GetNoteOwner(ctx, noteID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ShareResult{}, ErrNoteNotFound
		}
		return ShareResult{}, err
	}
	if noteOwnerID != ownerID {
		return ShareResult{}, ErrNotOwner
	}

	targetUser, err := repo.GetUserByEmail(ctx, email)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ShareResult{}, ErrUserNotFound
		}
		return ShareResult{}, err
	}
	if targetUser.ID == ownerID {
		return ShareResult{}, ErrCannotShareWithSelf
	}

	share, err := repo.CreateNoteShare(ctx, sqlcgen.CreateNoteShareParams{
		NoteID:     noteID,
		UserID:     targetUser.ID,
		Permission: permission,
	})
	if err != nil {
		return ShareResult{}, err
	}

	return ShareResult{
		ID:         uid.UUIDToString(share.ID),
		NoteID:     uid.UUIDToString(share.NoteID),
		UserID:     uid.UUIDToString(share.UserID),
		Email:      targetUser.Email,
		Name:       targetUser.Name,
		Permission: share.Permission,
	}, nil
}

func (s *Service) ListNoteShares(ctx context.Context, ownerID pgtype.UUID, noteID pgtype.UUID) ([]ShareResult, error) {
	noteOwnerID, err := s.repo.GetNoteOwner(ctx, noteID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNoteNotFound
		}
		return nil, err
	}
	if noteOwnerID != ownerID {
		return nil, ErrNotOwner
	}

	rows, err := s.repo.GetNoteShares(ctx, noteID)
	if err != nil {
		return nil, err
	}

	result := make([]ShareResult, len(rows))
	for i, row := range rows {
		result[i] = ShareResult{
			ID:         uid.UUIDToString(row.ID),
			NoteID:     uid.UUIDToString(row.NoteID),
			UserID:     uid.UUIDToString(row.UserID),
			Email:      row.Email,
			Name:       row.Name,
			Permission: row.Permission,
		}
	}
	return result, nil
}

func (s *Service) DeleteNoteShare(ctx context.Context, ownerID pgtype.UUID, noteID pgtype.UUID, targetUserID pgtype.UUID) error {
	return deleteNoteShare(ctx, s.repo, ownerID, noteID, targetUserID)
}

// DeleteNoteShareInTransaction atomically removes the share and records the
// confirmed result. DELETE is already a safe no-op when a recovered retry
// reaches an already-removed row.
func (s *Service) DeleteNoteShareInTransaction(ctx context.Context, tx pgx.Tx, ownerID pgtype.UUID, noteID pgtype.UUID, targetUserID pgtype.UUID) error {
	repo, ok := s.repo.(interface {
		WithQuerier(sqlcgen.Querier) Repository
	})
	if !ok || tx == nil {
		return errors.New("share transaction is not configured")
	}
	return deleteNoteShare(ctx, repo.WithQuerier(sqlcgen.New(tx)), ownerID, noteID, targetUserID)
}

func deleteNoteShare(ctx context.Context, repo Repository, ownerID pgtype.UUID, noteID pgtype.UUID, targetUserID pgtype.UUID) error {
	noteOwnerID, err := repo.GetNoteOwner(ctx, noteID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNoteNotFound
		}
		return err
	}
	if noteOwnerID != ownerID {
		return ErrNotOwner
	}

	return repo.DeleteNoteShare(ctx, sqlcgen.DeleteNoteShareParams{
		NoteID: noteID,
		UserID: targetUserID,
	})
}
