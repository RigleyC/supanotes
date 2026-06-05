package agent

import (
	"net/http"

	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/auth"
)

type ChatRequest struct {
	SessionID string `json:"session_id" validate:"required"`
	Message   string `json:"message" validate:"required"`
}

type ChatResponse struct {
	Response string `json:"response"`
}

type Handler struct {
	loop *Loop
	repo Repository
}

func NewHandler(loop *Loop, repo Repository) *Handler {
	return &Handler{loop: loop, repo: repo}
}

func (h *Handler) Chat(c echo.Context) error {
	userID, err := auth.UUIDFromString(c.Get("user_id").(string))
	if err != nil {
		return c.JSON(http.StatusUnauthorized, map[string]string{"error": "invalid user"})
	}

	var req ChatRequest
	if err := c.Bind(&req); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid request body"})
	}

	resp, err := h.loop.Chat(c.Request().Context(), userID, req.SessionID, req.Message)
	if err != nil {
		c.Logger().Error(err)
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": err.Error()})
	}

	return c.JSON(http.StatusOK, ChatResponse{Response: resp})
}

func (h *Handler) ListMessages(c echo.Context) error {
	userID, err := auth.UUIDFromString(c.Get("user_id").(string))
	if err != nil {
		return c.JSON(http.StatusUnauthorized, map[string]string{"error": "invalid user"})
	}

	sessionIDStr := c.QueryParam("session_id")
	if sessionIDStr == "" {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "session_id is required"})
	}

	sessionUUID, err := auth.UUIDFromString(sessionIDStr)
	if err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid session_id"})
	}

	messages, err := h.repo.GetMessages(c.Request().Context(), userID, sessionUUID, 50, 0)
	if err != nil {
		c.Logger().Error(err)
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to list messages"})
	}

	return c.JSON(http.StatusOK, messages)
}

func (h *Handler) DeleteMessages(c echo.Context) error {
	userID, err := auth.UUIDFromString(c.Get("user_id").(string))
	if err != nil {
		return c.JSON(http.StatusUnauthorized, map[string]string{"error": "invalid user"})
	}

	sessionIDStr := c.QueryParam("session_id")
	if sessionIDStr == "" {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "session_id is required"})
	}

	sessionUUID, err := auth.UUIDFromString(sessionIDStr)
	if err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid session_id"})
	}

	err = h.repo.DeleteSessionMessages(c.Request().Context(), userID, sessionUUID)
	if err != nil {
		c.Logger().Error(err)
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to clear history"})
	}

	return c.NoContent(http.StatusNoContent)
}
