package soul

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/dto"
	"github.com/RigleyC/supanotes/internal/mapper"
)

var (
	ErrSoulNotFound = errors.New("soul: not found")
)

type Service struct {
	q sqlcgen.Querier
}

func NewService(q sqlcgen.Querier) *Service {
	return &Service{q: q}
}

func (s *Service) Get(ctx context.Context, userID pgtype.UUID) (dto.SoulResponse, error) {
	soul, err := s.q.GetSoul(ctx, userID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return dto.SoulResponse{}, ErrSoulNotFound
		}
		return dto.SoulResponse{}, err
	}
	return mapper.SoulFromSQLC(soul), nil
}

func (s *Service) Update(ctx context.Context, userID pgtype.UUID, personality string) (dto.SoulResponse, error) {
	soul, err := s.q.UpsertSoul(ctx, sqlcgen.UpsertSoulParams{
		UserID:      userID,
		Personality: personality,
	})
	if err != nil {
		return dto.SoulResponse{}, err
	}
	return mapper.SoulFromSQLC(soul), nil
}
