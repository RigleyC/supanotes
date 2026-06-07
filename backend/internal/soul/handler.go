package soul

import (
	"net/http"

	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/web"
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
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	s, err := h.q.GetSoul(c.Request().Context(), userID)
	if err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to get soul")
	}

	return c.JSON(http.StatusOK, SoulResponse{Personality: s.Personality})
}

func (h *Handler) Update(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	var req PutSoulRequest
	if err := web.BindAndValidate(c, &req); err != nil {
		return err
	}

	s, err := h.q.UpsertSoul(c.Request().Context(), sqlcgen.UpsertSoulParams{
		UserID:      userID,
		Personality: req.Personality,
	})
	if err != nil {
		c.Logger().Error(err)
		return web.JSONError(c, http.StatusInternalServerError, "failed to update soul")
	}

	return c.JSON(http.StatusOK, SoulResponse{Personality: s.Personality})
}
