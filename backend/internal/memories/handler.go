package memories

import (
	"net/http"
	"strconv"
	"time"

	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/web"
	"github.com/RigleyC/supanotes/pkg/uid"
)

type CreateMemoryRequest struct {
	Content string `json:"content" validate:"required"`
}

type MemoryResponse struct {
	ID        string `json:"id"`
	Content   string `json:"content"`
	CreatedAt string `json:"created_at"`
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

	limit := int32(50)
	if l := c.QueryParam("limit"); l != "" {
		if parsed, err := strconv.ParseInt(l, 10, 32); err == nil && parsed > 0 && parsed <= 100 {
			limit = int32(parsed)
		}
	}
	offset := int32(0)
	if o := c.QueryParam("offset"); o != "" {
		if parsed, err := strconv.ParseInt(o, 10, 32); err == nil && parsed >= 0 {
			offset = int32(parsed)
		}
	}

	memories, err := h.svc.GetMemories(c.Request().Context(), userID, limit, offset)
	if err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to list memories")
	}

	res := make([]MemoryResponse, 0, len(memories))
	for _, m := range memories {
		res = append(res, MemoryResponse{
			ID:        uid.UUIDToString(m.ID),
			Content:   m.Content,
			CreatedAt: m.CreatedAt.Time.Format(time.RFC3339),
		})
	}
	return c.JSON(http.StatusOK, res)
}

func (h *Handler) Create(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	var req CreateMemoryRequest
	if err := web.BindAndValidate(c, &req); err != nil {
		return err
	}

	memory, err := h.svc.CreateMemory(c.Request().Context(), userID, req.Content)
	if err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to create memory")
	}

	return c.JSON(http.StatusCreated, MemoryResponse{
		ID:        uid.UUIDToString(memory.ID),
		Content:   memory.Content,
		CreatedAt: memory.CreatedAt.Time.Format(time.RFC3339),
	})
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

	if err := h.svc.DeleteMemory(c.Request().Context(), id, userID); err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to delete memory")
	}

	return c.NoContent(http.StatusNoContent)
}
