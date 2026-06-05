package contexts

import (
	"net/http"

	"github.com/go-playground/validator/v10"

	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/auth"
	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
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
	v *validator.Validate
}

func NewHandler(q sqlcgen.Querier) *Handler {
	return &Handler{q: q, v: validator.New(validator.WithRequiredStructEnabled())}
}

func (h *Handler) Create(c echo.Context) error {
	userID, err := auth.UUIDFromString(c.Get("user_id").(string))
	if err != nil {
		return c.JSON(http.StatusUnauthorized, map[string]string{"error": "invalid user"})
	}

	var req CreateContextRequest
	if err := c.Bind(&req); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid request body"})
	}
	if err := h.v.Struct(req); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "validation failed"})
	}

	ctxResult, err := h.q.CreateContext(c.Request().Context(), sqlcgen.CreateContextParams{
		UserID: userID,
		Slug:   req.Slug,
		Name:   req.Name,
	})
	if err != nil {
		c.Logger().Error(err)
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to create context"})
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
	userID, err := auth.UUIDFromString(c.Get("user_id").(string))
	if err != nil {
		return c.JSON(http.StatusUnauthorized, map[string]string{"error": "invalid user"})
	}

	ctxs, err := h.q.GetContexts(c.Request().Context(), userID)
	if err != nil {
		c.Logger().Error(err)
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to get contexts"})
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
	userID, err := auth.UUIDFromString(c.Get("user_id").(string))
	if err != nil {
		return c.JSON(http.StatusUnauthorized, map[string]string{"error": "invalid user"})
	}

	id, err := auth.UUIDFromString(c.Param("id"))
	if err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid id format"})
	}

	err = h.q.DeleteContext(c.Request().Context(), sqlcgen.DeleteContextParams{
		ID:     id,
		UserID: userID,
	})
	if err != nil {
		c.Logger().Error(err)
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to delete context"})
	}

	return c.NoContent(http.StatusNoContent)
}
