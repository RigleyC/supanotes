package noteoperations

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/web"
	"github.com/RigleyC/supanotes/pkg/uid"
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

func (h *Handler) RegisterRoutes(router *echo.Group) {
	router.GET("/notes/:noteId/document", h.GetDocument)
	router.GET("/notes/:noteId/operations", h.ListOperations)
	router.POST("/notes/:noteId/operations:sync", h.SyncOperations)
}

func (h *Handler) GetDocument(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	noteID, err := uid.UUIDFromString(c.Param("noteId"))
	if err != nil {
		return web.JSONError(c, http.StatusBadRequest, "invalid note_id")
	}

	resp, err := h.svc.GetDocument(c.Request().Context(), noteID, userID)
	if err != nil {
		if errors.Is(err, ErrNoteNotFound) {
			return web.JSONError(c, http.StatusNotFound, "NOTE_NOT_FOUND")
		}
		if errors.Is(err, ErrNoPermission) {
			return web.JSONError(c, http.StatusForbidden, "FORBIDDEN")
		}
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "INTERNAL_ERROR")
	}

	return c.JSON(http.StatusOK, resp)
}

func (h *Handler) ListOperations(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	noteID, err := uid.UUIDFromString(c.Param("noteId"))
	if err != nil {
		return web.JSONError(c, http.StatusBadRequest, "invalid note_id")
	}

	afterRevision := int64(0)
	if afterStr := c.QueryParam("afterRevision"); afterStr != "" {
		parsed, err := strconv.ParseInt(afterStr, 10, 64)
		if err != nil {
			return web.JSONError(c, http.StatusBadRequest, "invalid after_revision")
		}
		afterRevision = parsed
	}

	resp, err := h.svc.GetOperationsSince(c.Request().Context(), noteID, userID, afterRevision)
	if err != nil {
		if errors.Is(err, ErrNoteNotFound) {
			return web.JSONError(c, http.StatusNotFound, "NOTE_NOT_FOUND")
		}
		if errors.Is(err, ErrNoPermission) {
			return web.JSONError(c, http.StatusForbidden, "FORBIDDEN")
		}
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "INTERNAL_ERROR")
	}

	return c.JSON(http.StatusOK, resp)
}

func (h *Handler) SyncOperations(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	noteID, err := uid.UUIDFromString(c.Param("noteId"))
	if err != nil {
		return web.JSONError(c, http.StatusBadRequest, "invalid note_id")
	}

	var req SyncRequest
	if err := web.BindAndValidate(c, &req); err != nil {
		return err
	}

	resp, err := h.svc.SyncOperations(c.Request().Context(), noteID, userID, req)
	if err != nil {
		if errors.Is(err, ErrNoteNotFound) {
			return web.JSONError(c, http.StatusNotFound, "NOTE_NOT_FOUND")
		}
		if errors.Is(err, ErrNoPermission) {
			return web.JSONError(c, http.StatusForbidden, "FORBIDDEN")
		}
		if valErr, ok := err.(*ValidationError); ok {
			return web.JSONError(c, http.StatusBadRequest, valErr.Code)
		}
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "INTERNAL_ERROR")
	}

	return c.JSON(http.StatusOK, resp)
}
