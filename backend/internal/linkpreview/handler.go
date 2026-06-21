package linkpreview

import (
	"net/http"

	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/web"
)

type Handler struct {
	svc Service
}

func NewHandler(svc Service) *Handler {
	return &Handler{svc: svc}
}

func (h *Handler) Preview(c echo.Context) error {
	rawURL := c.QueryParam("url")
	if rawURL == "" {
		return web.JSONError(c, http.StatusBadRequest, "url query param required")
	}

	preview, err := h.svc.Fetch(c.Request().Context(), rawURL)
	if err != nil {
		c.Logger().Warnf("link preview failed for %q: %v", rawURL, err)
		return web.JSONError(c, http.StatusUnprocessableEntity, "could not fetch preview")
	}

	return c.JSON(http.StatusOK, preview)
}
