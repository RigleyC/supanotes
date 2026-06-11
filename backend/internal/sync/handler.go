package sync

import (
	"net/http"
	"time"

	"errors"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/web"
)

type PullRequest struct {
	LastSyncedAt time.Time `json:"last_synced_at"`
	Limit        int32     `json:"limit"`
}

type Handler struct {
	service Service
}

func NewHandler(service Service) *Handler {
	return &Handler{service: service}
}

func (h *Handler) Pull(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	var req PullRequest
	if err := c.Bind(&req); err != nil {
		return web.JSONError(c, http.StatusBadRequest, "invalid request body")
	}

	if req.Limit <= 0 || req.Limit > 1000 {
		req.Limit = 100
	}

	lastSyncedAt := pgtype.Timestamptz{
		Time:  req.LastSyncedAt,
		Valid: true,
	}

	payload, err := h.service.Pull(c.Request().Context(), userID, lastSyncedAt, req.Limit)
	if err != nil {
		c.Logger().Errorf("sync.Pull failed: %v", err)
		return web.JSONError(c, http.StatusInternalServerError, "sync failed: "+err.Error())
	}

	return c.JSON(http.StatusOK, payload)
}

func (h *Handler) Push(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	var payload SyncPayload
	if err := c.Bind(&payload); err != nil {
		return web.JSONError(c, http.StatusBadRequest, "invalid request body")
	}

	if err := h.service.Push(c.Request().Context(), userID, &payload); err != nil {
		if errors.Is(err, ErrSyncConflict) {
			return web.JSONError(c, http.StatusConflict, "sync conflict")
		}
		if errors.Is(err, ErrEmptyNote) {
			return web.JSONError(c, http.StatusBadRequest, "empty notes cannot be synced")
		}
		return web.JSONError(c, http.StatusInternalServerError, "sync failed")
	}

	return c.JSON(http.StatusOK, map[string]string{"status": "ok"})
}
