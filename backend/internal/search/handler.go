package search

import (
	"net/http"

	"github.com/RigleyC/supanotes/pkg/uid"
	"github.com/labstack/echo/v4"
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
	userID, err := uid.UUIDFromString(c.Get("user_id").(string))
	if err != nil {
		return echo.NewHTTPError(http.StatusUnauthorized, "missing or invalid user token")
	}

	var req SearchRequest
	if err := c.Bind(&req); err != nil {
		return echo.NewHTTPError(http.StatusBadRequest, err.Error())
	}
	if err := c.Validate(&req); err != nil {
		return echo.NewHTTPError(http.StatusBadRequest, err.Error())
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
		return echo.NewHTTPError(http.StatusInternalServerError, err.Error())
	}

	return c.JSON(http.StatusOK, results)
}

func RegisterRoutes(g *echo.Group, h *Handler) {
	g.POST("/search", h.HandleSearch)
}
