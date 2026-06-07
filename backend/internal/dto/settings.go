package dto

type SettingsResponse struct {
	Timezone  string `json:"timezone"`
	CreatedAt string `json:"created_at"`
	UpdatedAt string `json:"updated_at"`
}
