package handler

import (
	"net/http"

	"github.com/labstack/echo/v4"
)

// Health handles GET /api/v1/health.
func Health(c echo.Context) error {
	return c.JSON(http.StatusOK, map[string]string{"status": "ok"})
}
