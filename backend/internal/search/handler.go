package search

import (
	"net/http"

	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/web"
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

type SearchRequest struct {
	Query string `json:"query" validate:"required"`
	Mode  string `json:"mode"`
	Limit int32  `json:"limit"`
}

func (h *Handler) HandleSearch(c echo.Context) error {
	userID, err := web.UserID(c)
	if err != nil {
		return err
	}

	var req SearchRequest
	if err := web.BindAndValidate(c, &req); err != nil {
		return err
	}

	mode := req.Mode
	if mode == "" {
		mode = "hybrid"
	}
	limit := req.Limit
	if limit <= 0 {
		limit = 10
	}

	results, err := h.svc.Search(c.Request().Context(), userID, req.Query, mode, limit)
	if err != nil {
		return web.JSONError(c, http.StatusInternalServerError, err.Error())
	}

	return c.JSON(http.StatusOK, results)
}

func RegisterRoutes(g *echo.Group, h *Handler) {
	g.POST("/search", h.HandleSearch)
}
