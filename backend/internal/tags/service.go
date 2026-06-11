package tags

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/dto"
	"github.com/RigleyC/supanotes/internal/mapper"
)

var ErrNoteNotFound = errors.New("note not found")

type Service struct {
	q sqlcgen.Querier
}

func NewService(q sqlcgen.Querier) *Service {
	return &Service{q: q}
}

func (s *Service) List(ctx context.Context, userID pgtype.UUID) ([]dto.TagResponse, error) {
	tags, err := s.q.GetTags(ctx, userID)
	if err != nil {
		return nil, err
	}
	res := make([]dto.TagResponse, 0, len(tags))
	for _, t := range tags {
		res = append(res, mapper.TagFromSQLC(t))
	}
	return res, nil
}

func (s *Service) Delete(ctx context.Context, id pgtype.UUID, userID pgtype.UUID) error {
	return s.q.DeleteTag(ctx, sqlcgen.DeleteTagParams{
		ID:     id,
		UserID: userID,
	})
}

func (s *Service) Create(ctx context.Context, userID pgtype.UUID, name string) (dto.TagResponse, error) {
	tag, err := s.q.CreateTag(ctx, sqlcgen.CreateTagParams{
		UserID: userID,
		Name:   name,
	})
	if err != nil {
		return dto.TagResponse{}, err
	}
	return mapper.TagFromSQLC(tag), nil
}

func (s *Service) AddTagToNote(ctx context.Context, noteID, tagID, userID pgtype.UUID) error {
	if _, err := s.q.GetNoteByID(ctx, sqlcgen.GetNoteByIDParams{
		ID:     noteID,
		UserID: userID,
	}); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNoteNotFound
		}
		return err
	}
	return s.q.AddTagToNote(ctx, sqlcgen.AddTagToNoteParams{
		NoteID: noteID,
		TagID:  tagID,
	})
}

func (s *Service) RemoveTagFromNote(ctx context.Context, noteID, tagID, userID pgtype.UUID) error {
	if _, err := s.q.GetNoteByID(ctx, sqlcgen.GetNoteByIDParams{
		ID:     noteID,
		UserID: userID,
	}); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNoteNotFound
		}
		return err
	}
	return s.q.RemoveTagFromNote(ctx, sqlcgen.RemoveTagFromNoteParams{
		NoteID: noteID,
		TagID:  tagID,
	})
}
