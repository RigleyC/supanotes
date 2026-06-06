package notifications

import (
	"net/http"

	"github.com/go-playground/validator/v10"
	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/auth"
	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/pkg/uid"
)

type RegisterDeviceTokenRequest struct {
	Token    string `json:"token" validate:"required"`
	Platform string `json:"platform" validate:"required,oneof=ios android web desktop"`
}

type DeviceTokenResponse struct {
	ID        string `json:"id"`
	Token     string `json:"token"`
	Platform  string `json:"platform"`
	CreatedAt string `json:"created_at"`
}

type Handler struct {
	q sqlcgen.Querier
	v *validator.Validate
}

func NewHandler(q sqlcgen.Querier) *Handler {
	return &Handler{q: q, v: validator.New(validator.WithRequiredStructEnabled())}
}

func (h *Handler) RegisterToken(c echo.Context) error {
	userID, err := auth.ParsedUserID(c)
	if err != nil {
		return err
	}

	var req RegisterDeviceTokenRequest
	if err := c.Bind(&req); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid request body"})
	}
	if err := h.v.Struct(req); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "validation failed"})
	}

	token, err := h.q.CreateDeviceToken(c.Request().Context(), sqlcgen.CreateDeviceTokenParams{
		UserID:   userID,
		Token:    req.Token,
		Platform: req.Platform,
	})
	if err != nil {
		c.Logger().Error(err)
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to register device token"})
	}

	return c.JSON(http.StatusCreated, DeviceTokenResponse{
		ID:        uid.UUIDToString(token.ID),
		Token:     token.Token,
		Platform:  token.Platform,
		CreatedAt: token.CreatedAt.Time.Format("2006-01-02T15:04:05Z07:00"),
	})
}

func (h *Handler) DeleteToken(c echo.Context) error {
	userID, err := auth.ParsedUserID(c)
	if err != nil {
		return err
	}

	id, err := uid.UUIDFromString(c.Param("id"))
	if err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid id format"})
	}

	if err := h.q.DeleteDeviceToken(c.Request().Context(), sqlcgen.DeleteDeviceTokenParams{
		ID:     id,
		UserID: userID,
	}); err != nil {
		c.Logger().Error(err)
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to delete device token"})
	}

	return c.NoContent(http.StatusNoContent)
}
