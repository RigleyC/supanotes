package tags

import (
	"context"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/dto"
	"github.com/RigleyC/supanotes/internal/mapper"
)

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
