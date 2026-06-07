package notifications

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

func (s *Service) RegisterToken(ctx context.Context, userID pgtype.UUID, token, platform string) (dto.DeviceTokenResponse, error) {
	deviceToken, err := s.q.CreateDeviceToken(ctx, sqlcgen.CreateDeviceTokenParams{
		UserID:   userID,
		Token:    token,
		Platform: platform,
	})
	if err != nil {
		return dto.DeviceTokenResponse{}, err
	}
	return mapper.DeviceTokenFromSQLC(deviceToken), nil
}

func (s *Service) DeleteToken(ctx context.Context, userID, id pgtype.UUID) error {
	return s.q.DeleteDeviceToken(ctx, sqlcgen.DeleteDeviceTokenParams{
		ID:     id,
		UserID: userID,
	})
}
