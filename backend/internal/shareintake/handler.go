package shareintake

import (
	"errors"
	"net/http"

	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/noteoperations"
	"github.com/RigleyC/supanotes/internal/web"
	"github.com/RigleyC/supanotes/pkg/uid"
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

func (h *Handler) Append(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}
	noteID, err := uid.UUIDFromString(c.Param("noteId"))
	if err != nil {
		return web.JSONError(c, http.StatusBadRequest, "invalid note_id")
	}

	var req Request
	if err := web.BindAndValidate(c, &req); err != nil {
		return err
	}
	result, err := h.svc.Append(c.Request().Context(), noteID, userID, req)
	if err != nil {
		switch {
		case errors.Is(err, ErrInvalidShareID), errors.Is(err, ErrInvalidURL):
			return web.JSONError(c, http.StatusBadRequest, err.Error())
		case errors.Is(err, noteoperations.ErrNoteNotFound):
			return web.JSONError(c, http.StatusNotFound, "NOTE_NOT_FOUND")
		case errors.Is(err, noteoperations.ErrNoPermission):
			return web.JSONError(c, http.StatusForbidden, "FORBIDDEN")
		default:
			c.Logger().Error(err)
			return web.JSONError(c, http.StatusInternalServerError, "INTERNAL_ERROR")
		}
	}

	return c.JSON(http.StatusOK, map[string]any{
		"revision": result.Revision,
		"document": result.Document,
	})
}
