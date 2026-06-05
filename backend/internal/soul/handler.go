package soul

import (
	"net/http"

	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/auth"
	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

type PutSoulRequest struct {
	Personality string `json:"personality" validate:"required"`
}

type SoulResponse struct {
	Personality string `json:"personality"`
}

type Handler struct {
	q sqlcgen.Querier
}

func NewHandler(q sqlcgen.Querier) *Handler {
	return &Handler{q: q}
}

func (h *Handler) Get(c echo.Context) error {
	userID, err := auth.UUIDFromString(c.Get("user_id").(string))
	if err != nil {
		return c.JSON(http.StatusUnauthorized, map[string]string{"error": "invalid user"})
	}

	s, err := h.q.GetSoul(c.Request().Context(), userID)
	if err != nil {
		c.Logger().Error(err)
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to get soul"})
	}

	return c.JSON(http.StatusOK, SoulResponse{Personality: s.Personality})
}

func (h *Handler) Update(c echo.Context) error {
	userID, err := auth.UUIDFromString(c.Get("user_id").(string))
	if err != nil {
		return c.JSON(http.StatusUnauthorized, map[string]string{"error": "invalid user"})
	}

	var req PutSoulRequest
	if err := c.Bind(&req); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid request body"})
	}

	s, err := h.q.UpsertSoul(c.Request().Context(), sqlcgen.UpsertSoulParams{
		UserID:      userID,
		Personality: req.Personality,
	})
	if err != nil {
		c.Logger().Error(err)
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to update soul"})
	}

	return c.JSON(http.StatusOK, SoulResponse{Personality: s.Personality})
}
