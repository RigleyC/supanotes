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
	noteOwnerID, err := s.repo.GetNoteOwner(ctx, noteID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ShareResult{}, ErrNoteNotFound
		}
		return ShareResult{}, err
	}
	if noteOwnerID != ownerID {
		return ShareResult{}, ErrNotOwner
	}

	targetUser, err := s.repo.GetUserByEmail(ctx, email)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ShareResult{}, ErrUserNotFound
		}
		return ShareResult{}, err
	}
	if targetUser.ID == ownerID {
		return ShareResult{}, ErrCannotShareWithSelf
	}

	share, err := s.repo.CreateNoteShare(ctx, sqlcgen.CreateNoteShareParams{
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
	noteOwnerID, err := s.repo.GetNoteOwner(ctx, noteID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNoteNotFound
		}
		return err
	}
	if noteOwnerID != ownerID {
		return ErrNotOwner
	}

	return s.repo.DeleteNoteShare(ctx, sqlcgen.DeleteNoteShareParams{
		NoteID: noteID,
		UserID: targetUserID,
	})
}
