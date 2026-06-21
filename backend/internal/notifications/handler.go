package notifications

import (
	"net/http"

	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/web"
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

type DeleteDeviceTokenRequest struct {
	Token string `json:"token" validate:"required"`
}

func (h *Handler) DeleteToken(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	var req DeleteDeviceTokenRequest
	if err := web.BindAndValidate(c, &req); err != nil {
		return err
	}

	if err := h.svc.DeleteTokenByToken(c.Request().Context(), userID, req.Token); err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to delete device token")
	}

	return c.NoContent(http.StatusNoContent)
}
