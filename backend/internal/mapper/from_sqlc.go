package mapper

import (
	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/dto"
)

func ContextFromSQLC(c sqlcgen.Context) dto.ContextResponse {
	return dto.ContextResponse{
		ID:        UUID(c.ID),
		Slug:      c.Slug,
		Name:      c.Name,
		CreatedAt: Time(c.CreatedAt),
		UpdatedAt: Time(c.UpdatedAt),
	}
}

func TagFromSQLC(t sqlcgen.Tag) dto.TagResponse {
	return dto.TagResponse{
		ID:        UUID(t.ID),
		Name:      t.Name,
		CreatedAt: Time(t.CreatedAt),
	}
}

func SettingsFromSQLC(s sqlcgen.UserSetting) dto.SettingsResponse {
	return dto.SettingsResponse{
		Timezone:  s.Timezone,
		CreatedAt: Time(s.CreatedAt),
		UpdatedAt: Time(s.UpdatedAt),
	}
}

func SoulFromSQLC(s sqlcgen.Soul) dto.SoulResponse {
	return dto.SoulResponse{
		Personality: s.Personality,
		CreatedAt:   Time(s.CreatedAt),
		UpdatedAt:   Time(s.UpdatedAt),
	}
}

func DeviceTokenFromSQLC(t sqlcgen.DeviceToken) dto.DeviceTokenResponse {
	return dto.DeviceTokenResponse{
		ID:        UUID(t.ID),
		Token:     t.Token,
		Platform:  t.Platform,
		CreatedAt: Time(t.CreatedAt),
	}
}
