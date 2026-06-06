package settings

import (
	"net/http"
	"strings"
	"time"

	"github.com/go-playground/validator/v10"
	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/auth"
	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

type SettingsResponse struct {
	Timezone  string `json:"timezone"`
	CreatedAt string `json:"created_at"`
	UpdatedAt string `json:"updated_at"`
}

type UpdateSettingsRequest struct {
	Timezone string `json:"timezone" validate:"required"`
}

type Handler struct {
	q sqlcgen.Querier
	v *validator.Validate
}

func NewHandler(q sqlcgen.Querier) *Handler {
	return &Handler{q: q, v: validator.New(validator.WithRequiredStructEnabled())}
}

func (h *Handler) Get(c echo.Context) error {
	userID, err := auth.ParsedUserID(c)
	if err != nil {
		return err
	}

	settings, err := h.q.GetUserSettings(c.Request().Context(), userID)
	if err != nil {
		c.Logger().Error(err)
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to get settings"})
	}

	return c.JSON(http.StatusOK, toResponse(settings))
}

func (h *Handler) Update(c echo.Context) error {
	userID, err := auth.ParsedUserID(c)
	if err != nil {
		return err
	}

	var req UpdateSettingsRequest
	if err := c.Bind(&req); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid request body"})
	}
	if err := h.v.Struct(req); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "validation failed"})
	}

	tz := strings.TrimSpace(req.Timezone)
	if _, err := time.LoadLocation(tz); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid timezone"})
	}

	settings, err := h.q.UpdateUserSettings(c.Request().Context(), sqlcgen.UpdateUserSettingsParams{
		UserID:   userID,
		Timezone: tz,
	})
	if err != nil {
		c.Logger().Error(err)
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to update settings"})
	}

	return c.JSON(http.StatusOK, toResponse(settings))
}

func toResponse(s sqlcgen.UserSetting) SettingsResponse {
	return SettingsResponse{
		Timezone:  s.Timezone,
		CreatedAt: s.CreatedAt.Time.Format(time.RFC3339),
		UpdatedAt: s.UpdatedAt.Time.Format(time.RFC3339),
	}
}
