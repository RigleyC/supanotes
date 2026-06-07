package dto

type DeviceTokenResponse struct {
	ID        string `json:"id"`
	Token     string `json:"token"`
	Platform  string `json:"platform"`
	CreatedAt string `json:"created_at"`
}
