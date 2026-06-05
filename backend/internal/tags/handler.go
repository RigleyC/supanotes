package tags

import (
	"net/http"

	"github.com/go-playground/validator/v10"

	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/auth"
	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

type CreateTagRequest struct {
	Name string `json:"name" validate:"required,min=1,max=50"`
}

type TagResponse struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	CreatedAt string `json:"created_at"`
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

	var req CreateTagRequest
	if err := c.Bind(&req); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid request body"})
	}
	if err := h.v.Struct(req); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "validation failed"})
	}

	tag, err := h.q.CreateTag(c.Request().Context(), sqlcgen.CreateTagParams{
		UserID: userID,
		Name:   req.Name,
	})
	if err != nil {
		c.Logger().Error(err)
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to create tag"})
	}

	return c.JSON(http.StatusCreated, TagResponse{
		ID:        auth.UUIDToString(tag.ID),
		Name:      tag.Name,
		CreatedAt: tag.CreatedAt.Time.Format("2006-01-02T15:04:05Z07:00"),
	})
}

func (h *Handler) List(c echo.Context) error {
	userID, err := auth.UUIDFromString(c.Get("user_id").(string))
	if err != nil {
		return c.JSON(http.StatusUnauthorized, map[string]string{"error": "invalid user"})
	}

	tags, err := h.q.GetTags(c.Request().Context(), userID)
	if err != nil {
		c.Logger().Error(err)
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to get tags"})
	}

	res := make([]TagResponse, 0, len(tags))
	for _, t := range tags {
		res = append(res, TagResponse{
			ID:        auth.UUIDToString(t.ID),
			Name:      t.Name,
			CreatedAt: t.CreatedAt.Time.Format("2006-01-02T15:04:05Z07:00"),
		})
	}

	return c.JSON(http.StatusOK, res)
}
