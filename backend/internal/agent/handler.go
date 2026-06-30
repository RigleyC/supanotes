package agent

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"strconv"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/web"
	"github.com/RigleyC/supanotes/pkg/llm"
	"github.com/RigleyC/supanotes/pkg/uid"
)

type ResolveToolConfirmationRequest struct {
	Approved bool `json:"approved"`
}

type ResolveToolConfirmationResponse struct {
	ConfirmationID string `json:"confirmation_id"`
	Status         string `json:"status"`
	Message        string `json:"message"`
}

func parseInt32(s string) (int32, error) {
	n, err := strconv.ParseInt(s, 10, 32)
	if err != nil {
		return 0, err
	}
	return int32(n), nil
}

type ChatRequest struct {
	SessionID string `json:"session_id" validate:"required"`
	Content   string `json:"content" validate:"required"`
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

	ch, err := h.loop.Chat(c.Request().Context(), userID, req.SessionID, req.Content)
	if err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, err.Error())
	}

	resp := ""
	for chunk := range ch {
		resp = chunk
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

	slog.Info("agent chat stream started", "session_id", req.SessionID)

	c.Response().Header().Set(echo.HeaderContentType, "text/event-stream")
	c.Response().Header().Set(echo.HeaderCacheControl, "no-cache")
	c.Response().Header().Set(echo.HeaderConnection, "keep-alive")

	events := make(chan StreamEvent, 10)
	go func() {
		defer func() {
			if r := recover(); r != nil {
				slog.Error("panic in ChatStream", "recover", r)
			}
			close(events)
		}()
		if err := h.loop.ChatStream(c.Request().Context(), userID, req.SessionID, req.Content, events); err != nil {
			slog.Error("agent chat stream failed", "session_id", req.SessionID, "error", err)
			writer := NewStreamEventWriter(req.SessionID, "")
			sendStreamEvent(c.Request().Context(), events, writer.Event(EventError, ErrorPayload{Message: err.Error()}))
		}
	}()

	flusher, ok := c.Response().Writer.(http.Flusher)
	if !ok {
		return web.JSONError(c, http.StatusInternalServerError, "streaming not supported")
	}

	for event := range events {
		data, err := json.Marshal(event)
		if err != nil {
			slog.Error("marshal stream event", "error", err)
			break
		}
		_, err = fmt.Fprintf(c.Response().Writer, "data: %s\n\n", data)
		if err != nil {
			slog.Error("agent chat stream write failed", "session_id", req.SessionID, "error", err)
			break
		}
		flusher.Flush()
	}
	slog.Info("agent chat stream closed", "session_id", req.SessionID)
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

	limit := int32(50)
	if l := c.QueryParam("limit"); l != "" {
		if parsed, err := parseInt32(l); err == nil && parsed > 0 {
			limit = parsed
		}
	}

	messages, err := h.repo.GetMessages(c.Request().Context(), userID, sessionUUID, limit, 0)
	if err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to list messages")
	}

	return c.JSON(http.StatusOK, messages)
}

func (h *Handler) resolveToolConfirmation(ctx context.Context, userID pgtype.UUID, confirmationIDStr string, approved bool) (ResolveToolConfirmationResponse, int, error) {
	confirmationID, err := uid.UUIDFromString(confirmationIDStr)
	if err != nil {
		return ResolveToolConfirmationResponse{}, http.StatusBadRequest, fmt.Errorf("invalid confirmation_id")
	}

	pending, err := h.repo.GetPendingToolConfirmation(ctx, confirmationID, userID)
	if err != nil {
		return ResolveToolConfirmationResponse{}, http.StatusNotFound, fmt.Errorf("confirmation not found")
	}
	if pending.Status != "pending" {
		return ResolveToolConfirmationResponse{}, http.StatusConflict, fmt.Errorf("confirmation already resolved")
	}

	if !approved {
		resolved, err := h.repo.ResolvePendingToolConfirmation(ctx, confirmationID, userID, "cancelled")
		if err != nil {
			return ResolveToolConfirmationResponse{}, http.StatusConflict, fmt.Errorf("confirmation already resolved")
		}
		return ResolveToolConfirmationResponse{
			ConfirmationID: uid.UUIDToString(resolved.ID),
			Status:         "cancelled",
			Message:        "Ação cancelada.",
		}, http.StatusOK, nil
	}

	resolved, err := h.repo.ResolvePendingToolConfirmation(ctx, confirmationID, userID, "approved")
	if err != nil {
		return ResolveToolConfirmationResponse{}, http.StatusConflict, fmt.Errorf("confirmation already resolved")
	}

	result, err := h.loop.ExecuteTool(ctx, userID, uid.UUIDToString(resolved.SessionID), resolved.ToolName, string(resolved.ArgsJson))
	if err != nil {
		return ResolveToolConfirmationResponse{}, http.StatusInternalServerError, fmt.Errorf("execute confirmed tool: %w", err)
	}

	if _, err := h.repo.CreateMessage(ctx, userID, resolved.SessionID, string(llm.RoleTool), result, nil, nil); err != nil {
		return ResolveToolConfirmationResponse{}, http.StatusInternalServerError, fmt.Errorf("save tool result: %w", err)
	}

	return ResolveToolConfirmationResponse{
		ConfirmationID: uid.UUIDToString(resolved.ID),
		Status:         "approved",
		Message:        result,
	}, http.StatusOK, nil
}

func (h *Handler) ResolveToolConfirmation(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	var req ResolveToolConfirmationRequest
	if err := web.BindAndValidate(c, &req); err != nil {
		return err
	}

	resp, status, err := h.resolveToolConfirmation(c.Request().Context(), userID, c.Param("id"), req.Approved)
	if err != nil {
		return web.JSONError(c, status, err.Error())
	}
	return c.JSON(status, resp)
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

func (h *Handler) GetSessionTraces(c echo.Context) error {
	sessionID := c.Param("id")
	if sessionID == "" {
		return web.JSONError(c, http.StatusBadRequest, "session id is required")
	}
	traces := GlobalTraceStore.GetTraces(sessionID)
	return c.JSON(http.StatusOK, traces)
}

