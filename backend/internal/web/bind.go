package web

import (
	"net/http"

	"github.com/labstack/echo/v4"
)

func BindAndValidate(c echo.Context, req any) error {
	if err := c.Bind(req); err != nil {
		return echo.NewHTTPError(http.StatusBadRequest, "invalid request body")
	}
	if err := c.Validate(req); err != nil {
		JSONValidationError(c, err)
		return echo.ErrBadRequest
	}
	return nil
}
