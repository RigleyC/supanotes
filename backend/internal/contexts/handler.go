package contexts

import (
	"errors"
	"net/http"

	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/web"
	"github.com/RigleyC/supanotes/pkg/uid"
)

type CreateContextRequest struct {
	Slug string `json:"slug" validate:"required,min=1,max=50"`
	Name string `json:"name" validate:"required,min=1,max=100"`
}

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

func (h *Handler) List(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	ctxs, err := h.svc.List(c.Request().Context(), userID)
	if err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to get contexts")
	}

	return c.JSON(http.StatusOK, ctxs)
}

func (h *Handler) Create(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	var req CreateContextRequest
	if err := web.BindAndValidate(c, &req); err != nil {
		return err
	}

	ctxResult, err := h.svc.Create(c.Request().Context(), userID, req.Slug, req.Name)
	if err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to create context")
	}

	return c.JSON(http.StatusCreated, ctxResult)
}

func (h *Handler) Delete(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	id, err := uid.UUIDFromString(c.Param("id"))
	if err != nil {
		return web.JSONError(c, http.StatusBadRequest, "invalid id format")
	}

	err = h.svc.Delete(c.Request().Context(), userID, id)
	if err != nil {
		if errors.Is(err, ErrContextHasNotes) {
			return web.JSONError(c, http.StatusConflict, "cannot delete context with linked notes")
		}
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to delete context")
	}

	return c.NoContent(http.StatusNoContent)
}
