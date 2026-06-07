package soul

import (
	"errors"
	"net/http"

	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/web"
)

type PutSoulRequest struct {
	Personality string `json:"personality" validate:"required"`
}

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

	s, err := h.svc.Get(c.Request().Context(), userID)
	if err != nil {
		if errors.Is(err, ErrSoulNotFound) {
			return web.JSONError(c, http.StatusNotFound, "soul not found")
		}
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to get soul")
	}

	return c.JSON(http.StatusOK, s)
}

func (h *Handler) Update(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	var req PutSoulRequest
	if err := web.BindAndValidate(c, &req); err != nil {
		return err
	}

	s, err := h.svc.Update(c.Request().Context(), userID, req.Personality)
	if err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to update soul")
	}

	return c.JSON(http.StatusOK, s)
}
