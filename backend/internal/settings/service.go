package settings

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/dto"
	"github.com/RigleyC/supanotes/internal/mapper"
)

var (
	ErrSettingsNotFound = errors.New("settings: not found")
	ErrInvalidTimezone  = errors.New("settings: invalid timezone")
)

type Service struct {
	q sqlcgen.Querier
}

func NewService(q sqlcgen.Querier) *Service {
	return &Service{q: q}
}

func (s *Service) Get(ctx context.Context, userID pgtype.UUID) (dto.SettingsResponse, error) {
	settings, err := s.q.GetUserSettings(ctx, userID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return dto.SettingsResponse{}, ErrSettingsNotFound
		}
		return dto.SettingsResponse{}, err
	}
	return mapper.SettingsFromSQLC(settings), nil
}

func (s *Service) Update(ctx context.Context, userID pgtype.UUID, req dto.UpdateSettingsRequest) (dto.SettingsResponse, error) {
	tz := strings.TrimSpace(req.Timezone)
	if tz != "" {
		if _, err := time.LoadLocation(tz); err != nil {
			return dto.SettingsResponse{}, ErrInvalidTimezone
		}
	}

	var prefsBytes []byte
	if req.Preferences != nil {
		var err error
		prefsBytes, err = json.Marshal(req.Preferences)
		if err != nil {
			return dto.SettingsResponse{}, fmt.Errorf("serialize preferences: %w", err)
		}
	}

	settings, err := s.q.UpdateUserSettings(ctx, sqlcgen.UpdateUserSettingsParams{
		UserID:      userID,
		Timezone:    tz,
		Preferences: prefsBytes,
	})
	if err != nil {
		return dto.SettingsResponse{}, err
	}
	return mapper.SettingsFromSQLC(settings), nil
}
