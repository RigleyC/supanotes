package notifications

import (
	"net/http"

	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/web"
	"github.com/RigleyC/supanotes/pkg/uid"
)

type RegisterDeviceTokenRequest struct {
	Token    string `json:"token" validate:"required"`
	Platform string `json:"platform" validate:"required,oneof=ios android web desktop"`
}

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

func (h *Handler) RegisterToken(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	var req RegisterDeviceTokenRequest
	if err := web.BindAndValidate(c, &req); err != nil {
		return err
	}

	token, err := h.svc.RegisterToken(c.Request().Context(), userID, req.Token, req.Platform)
	if err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to register device token")
	}

	return c.JSON(http.StatusCreated, token)
}

func (h *Handler) DeleteToken(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	id, err := uid.UUIDFromString(c.Param("id"))
	if err != nil {
		return web.JSONError(c, http.StatusBadRequest, "invalid id format")
	}

	if err := h.svc.DeleteToken(c.Request().Context(), userID, id); err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to delete device token")
	}

	return c.NoContent(http.StatusNoContent)
}
