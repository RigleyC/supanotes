package shares

import (
	"errors"
	"net/http"

	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/web"
	"github.com/RigleyC/supanotes/pkg/uid"
)

type ShareNoteRequest struct {
	Email      string `json:"email" validate:"required,email"`
	Permission string `json:"permission" validate:"required,oneof=view edit"`
}

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

func (h *Handler) ShareNote(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	noteID, err := uid.UUIDFromString(c.Param("id"))
	if err != nil {
		return web.JSONError(c, http.StatusBadRequest, "invalid note id")
	}

	var req ShareNoteRequest
	if err := web.BindAndValidate(c, &req); err != nil {
		return err
	}

	share, err := h.svc.ShareNote(c.Request().Context(), userID, noteID, req.Email, req.Permission)
	if err != nil {
		switch {
		case errors.Is(err, ErrNoteNotFound):
			return web.JSONError(c, http.StatusNotFound, "note not found")
		case errors.Is(err, ErrNotOwner):
			return web.JSONError(c, http.StatusForbidden, "only the note owner can share")
		case errors.Is(err, ErrUserNotFound):
			return web.JSONError(c, http.StatusNotFound, "user not found")
		case errors.Is(err, ErrCannotShareWithSelf):
			return web.JSONError(c, http.StatusBadRequest, "cannot share with yourself")
		default:
			c.Logger().Error(err)
			return web.JSONError(c, http.StatusInternalServerError, "failed to share note")
		}
	}

	return c.JSON(http.StatusCreated, share)
}

func (h *Handler) ListNoteShares(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	noteID, err := uid.UUIDFromString(c.Param("id"))
	if err != nil {
		return web.JSONError(c, http.StatusBadRequest, "invalid note id")
	}

	shares, err := h.svc.ListNoteShares(c.Request().Context(), userID, noteID)
	if err != nil {
		switch {
		case errors.Is(err, ErrNoteNotFound):
			return web.JSONError(c, http.StatusNotFound, "note not found")
		case errors.Is(err, ErrNotOwner):
			return web.JSONError(c, http.StatusForbidden, "only the note owner can list shares")
		default:
			c.Logger().Error(err)
			return web.JSONError(c, http.StatusInternalServerError, "failed to list shares")
		}
	}

	return c.JSON(http.StatusOK, shares)
}

func (h *Handler) DeleteNoteShare(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	noteID, err := uid.UUIDFromString(c.Param("id"))
	if err != nil {
		return web.JSONError(c, http.StatusBadRequest, "invalid note id")
	}

	targetUserID, err := uid.UUIDFromString(c.Param("user_id"))
	if err != nil {
		return web.JSONError(c, http.StatusBadRequest, "invalid user id")
	}

	if err := h.svc.DeleteNoteShare(c.Request().Context(), userID, noteID, targetUserID); err != nil {
		switch {
		case errors.Is(err, ErrNoteNotFound):
			return web.JSONError(c, http.StatusNotFound, "note not found")
		case errors.Is(err, ErrNotOwner):
			return web.JSONError(c, http.StatusForbidden, "only the note owner can remove shares")
		default:
			c.Logger().Error(err)
			return web.JSONError(c, http.StatusInternalServerError, "failed to remove share")
		}
	}

	return c.NoContent(http.StatusNoContent)
}
