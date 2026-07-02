package dto

type SettingsResponse struct {
	Timezone    string         `json:"timezone"`
	Preferences map[string]any `json:"preferences"`
	CreatedAt   string         `json:"created_at"`
	UpdatedAt   string         `json:"updated_at"`
}

type UpdateSettingsRequest struct {
	Timezone    string         `json:"timezone"`
	Preferences map[string]any `json:"preferences"`
}
