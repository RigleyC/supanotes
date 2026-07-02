package settings

import (
	"errors"
	"net/http"

	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/dto"
	"github.com/RigleyC/supanotes/internal/web"
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

func (h *Handler) Get(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	settings, err := h.svc.Get(c.Request().Context(), userID)
	if err != nil {
		if errors.Is(err, ErrSettingsNotFound) {
			return web.JSONError(c, http.StatusNotFound, "settings not found")
		}
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to get settings")
	}

	return c.JSON(http.StatusOK, settings)
}

func (h *Handler) Update(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	var req dto.UpdateSettingsRequest
	if err := web.BindAndValidate(c, &req); err != nil {
		return err
	}

	settings, err := h.svc.Update(c.Request().Context(), userID, req)
	if err != nil {
		if errors.Is(err, ErrInvalidTimezone) {
			return web.JSONError(c, http.StatusBadRequest, "invalid timezone")
		}
		if errors.Is(err, ErrSettingsNotFound) {
			return web.JSONError(c, http.StatusNotFound, "settings not found")
		}
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to update settings")
	}

	return c.JSON(http.StatusOK, settings)
}
