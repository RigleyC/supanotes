package mapper

import (
	"encoding/json"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/dto"
)

func SettingsFromSQLC(s sqlcgen.UserSetting) dto.SettingsResponse {
	var prefs map[string]any
	if len(s.Preferences) > 0 {
		_ = json.Unmarshal(s.Preferences, &prefs)
	}
	if prefs == nil {
		prefs = make(map[string]any)
	}

	return dto.SettingsResponse{
		Timezone:    s.Timezone,
		Preferences: prefs,
		CreatedAt:   Time(s.CreatedAt),
		UpdatedAt:   Time(s.UpdatedAt),
	}
}
