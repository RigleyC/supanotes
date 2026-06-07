package contexts

import (
	"net/http"

	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/auth"
	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/web"
)

type CreateContextRequest struct {
	Slug string `json:"slug" validate:"required,min=1,max=50"`
	Name string `json:"name" validate:"required,min=1,max=100"`
}

type ContextResponse struct {
	ID        string `json:"id"`
	Slug      string `json:"slug"`
	Name      string `json:"name"`
	CreatedAt string `json:"created_at"`
	UpdatedAt string `json:"updated_at"`
}

type Handler struct {
	q sqlcgen.Querier
}

func NewHandler(q sqlcgen.Querier) *Handler {
	return &Handler{q: q}
}

func (h *Handler) Create(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	var req CreateContextRequest
	if err := web.BindAndValidate(c, &req); err != nil {
		return err
	}

	ctxResult, err := h.q.CreateContext(c.Request().Context(), sqlcgen.CreateContextParams{
		UserID: userID,
		Slug:   req.Slug,
		Name:   req.Name,
	})
	if err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to create context")
	}

	return c.JSON(http.StatusCreated, ContextResponse{
		ID:        auth.UUIDToString(ctxResult.ID),
		Slug:      ctxResult.Slug,
		Name:      ctxResult.Name,
		CreatedAt: ctxResult.CreatedAt.Time.Format("2006-01-02T15:04:05Z07:00"),
		UpdatedAt: ctxResult.UpdatedAt.Time.Format("2006-01-02T15:04:05Z07:00"),
	})
}

func (h *Handler) List(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	ctxs, err := h.q.GetContexts(c.Request().Context(), userID)
	if err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to get contexts")
	}

	res := make([]ContextResponse, 0, len(ctxs))
	for _, ctxResult := range ctxs {
		res = append(res, ContextResponse{
			ID:        auth.UUIDToString(ctxResult.ID),
			Slug:      ctxResult.Slug,
			Name:      ctxResult.Name,
			CreatedAt: ctxResult.CreatedAt.Time.Format("2006-01-02T15:04:05Z07:00"),
			UpdatedAt: ctxResult.UpdatedAt.Time.Format("2006-01-02T15:04:05Z07:00"),
		})
	}

	return c.JSON(http.StatusOK, res)
}

func (h *Handler) Delete(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	id, err := auth.UUIDFromString(c.Param("id"))
	if err != nil {
		return web.JSONError(c, http.StatusBadRequest, "invalid id format")
	}

	err = h.q.DeleteContext(c.Request().Context(), sqlcgen.DeleteContextParams{
		ID:     id,
		UserID: userID,
	})
	if err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to delete context")
	}

	return c.NoContent(http.StatusNoContent)
}
