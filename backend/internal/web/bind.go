package web

import (
	"github.com/labstack/echo/v4"
)

func BindAndValidate(c echo.Context, req any) error {
	if err := c.Bind(req); err != nil {
		JSONError(c, 400, "invalid request body")
		return echo.ErrBadRequest
	}
	if err := c.Validate(req); err != nil {
		JSONValidationError(c, err)
		return echo.ErrBadRequest
	}
	return nil
}
