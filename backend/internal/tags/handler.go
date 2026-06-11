package tags

import (
	"net/http"

	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/web"
	"github.com/RigleyC/supanotes/pkg/uid"
)

type CreateTagRequest struct {
	Name string `json:"name" validate:"required,min=1,max=50"`
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

	tags, err := h.svc.List(c.Request().Context(), userID)
	if err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to get tags")
	}

	return c.JSON(http.StatusOK, tags)
}

func (h *Handler) Delete(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	id, err := uid.UUIDFromString(c.Param("id"))
	if err != nil {
		return web.JSONError(c, http.StatusBadRequest, "invalid tag id")
	}

	if err := h.svc.Delete(c.Request().Context(), id, userID); err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to delete tag")
	}

	return c.NoContent(http.StatusNoContent)
}

func (h *Handler) Create(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	var req CreateTagRequest
	if err := web.BindAndValidate(c, &req); err != nil {
		return err
	}

	tag, err := h.svc.Create(c.Request().Context(), userID, req.Name)
	if err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to create tag")
	}

	return c.JSON(http.StatusCreated, tag)
}
