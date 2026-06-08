package agent

import (
	"encoding/json"
	"fmt"
	"net/http"

	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/web"
	"github.com/RigleyC/supanotes/pkg/uid"
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
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	var req ChatRequest
	if err := web.BindAndValidate(c, &req); err != nil {
		return err
	}

	resp, err := h.loop.Chat(c.Request().Context(), userID, req.SessionID, req.Message)
	if err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, err.Error())
	}

	return c.JSON(http.StatusOK, ChatResponse{Response: resp})
}

func (h *Handler) ChatSSE(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	var req ChatRequest
	if err := web.BindAndValidate(c, &req); err != nil {
		return err
	}

	c.Response().Header().Set(echo.HeaderContentType, "text/event-stream")
	c.Response().Header().Set(echo.HeaderCacheControl, "no-cache")
	c.Response().Header().Set(echo.HeaderConnection, "keep-alive")

	events := make(chan SSEEvent, 10)
	go func() {
		if err := h.loop.ChatStream(c.Request().Context(), userID, req.SessionID, req.Message, events); err != nil {
			events <- SSEEvent{Type: "error", Data: err.Error()}
		}
	}()

	flusher, ok := c.Response().Writer.(http.Flusher)
	if !ok {
		return web.JSONError(c, http.StatusInternalServerError, "streaming not supported")
	}

	for event := range events {
		data, _ := json.Marshal(map[string]string{"type": event.Type, "data": event.Data})
		_, err := fmt.Fprintf(c.Response().Writer, "data: %s\n\n", data)
		if err != nil {
			break
		}
		flusher.Flush()
	}
	return nil
}

func (h *Handler) ListMessages(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	sessionIDStr := c.QueryParam("session_id")
	if sessionIDStr == "" {
		return web.JSONError(c, http.StatusBadRequest, "session_id is required")
	}

	sessionUUID, err := uid.UUIDFromString(sessionIDStr)
	if err != nil {
		return web.JSONError(c, http.StatusBadRequest, "invalid session_id")
	}

	messages, err := h.repo.GetMessages(c.Request().Context(), userID, sessionUUID, 50, 0)
	if err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to list messages")
	}

	return c.JSON(http.StatusOK, messages)
}

func (h *Handler) DeleteMessages(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	sessionIDStr := c.QueryParam("session_id")
	if sessionIDStr == "" {
		return web.JSONError(c, http.StatusBadRequest, "session_id is required")
	}

	sessionUUID, err := uid.UUIDFromString(sessionIDStr)
	if err != nil {
		return web.JSONError(c, http.StatusBadRequest, "invalid session_id")
	}

	err = h.repo.DeleteSessionMessages(c.Request().Context(), userID, sessionUUID)
	if err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to clear history")
	}

	return c.NoContent(http.StatusNoContent)
}
