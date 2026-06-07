package sync

import (
	"net/http"
	"time"

	"errors"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/labstack/echo/v4"
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
	userIDStr := c.Get("user_id").(string)
	var userID pgtype.UUID
	if err := userID.Scan(userIDStr); err != nil {
		return c.JSON(http.StatusUnauthorized, map[string]string{"error": "invalid user id"})
	}

	var req PullRequest
	if err := c.Bind(&req); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid request body"})
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
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": err.Error()})
	}

	return c.JSON(http.StatusOK, payload)
}

func (h *Handler) Push(c echo.Context) error {
	userIDStr := c.Get("user_id").(string)
	var userID pgtype.UUID
	if err := userID.Scan(userIDStr); err != nil {
		return c.JSON(http.StatusUnauthorized, map[string]string{"error": "invalid user id"})
	}

	var payload SyncPayload
	if err := c.Bind(&payload); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid request body"})
	}

	if err := h.service.Push(c.Request().Context(), userID, &payload); err != nil {
		if errors.Is(err, ErrSyncConflict) {
			return c.JSON(http.StatusConflict, map[string]string{"error": "sync conflict"})
		}
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": err.Error()})
	}

	return c.JSON(http.StatusOK, map[string]string{"status": "ok"})
}
