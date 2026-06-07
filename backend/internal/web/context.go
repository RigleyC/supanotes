package web

import (
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/labstack/echo/v4"
)

const userIDContextKey = "user_id"

func UserID(c echo.Context) (pgtype.UUID, error) {
	raw, ok := c.Get(userIDContextKey).(string)
	if !ok || raw == "" {
		return pgtype.UUID{}, echo.NewHTTPError(echo.ErrUnauthorized.Code, "invalid or missing user token")
	}
	var id pgtype.UUID
	if err := id.Scan(raw); err != nil {
		return pgtype.UUID{}, echo.NewHTTPError(echo.ErrUnauthorized.Code, "invalid or missing user token")
	}
	return id, nil
}
