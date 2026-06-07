package settings

import (
	"net/http"
	"strings"
	"time"

	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/web"
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
}

func NewHandler(q sqlcgen.Querier) *Handler {
	return &Handler{q: q}
}

func (h *Handler) Get(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	settings, err := h.q.GetUserSettings(c.Request().Context(), userID)
	if err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to get settings")
	}

	return c.JSON(http.StatusOK, toResponse(settings))
}

func (h *Handler) Update(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	var req UpdateSettingsRequest
	if err := web.BindAndValidate(c, &req); err != nil {
		return err
	}

	tz := strings.TrimSpace(req.Timezone)
	if _, err := time.LoadLocation(tz); err != nil {
		return web.JSONError(c, http.StatusBadRequest, "invalid timezone")
	}

	settings, err := h.q.UpdateUserSettings(c.Request().Context(), sqlcgen.UpdateUserSettingsParams{
		UserID:   userID,
		Timezone: tz,
	})
	if err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to update settings")
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
