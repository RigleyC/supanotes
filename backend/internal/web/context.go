package web

import (
	"errors"

	"github.com/labstack/echo/v4"
)

const userIDContextKey = "user_id"

var ErrNoUserID = errors.New("web: no authenticated user")

// SetUserID stores the authenticated user id into the Echo context.
// Designed to be called by the JWT middleware.
func SetUserID(c echo.Context, userID string) {
	c.Set(userIDContextKey, userID)
}

// UserIDFromContext returns the authenticated user id set by the JWT
// middleware. The string is a canonical hyphenated UUID.
func UserIDFromContext(c echo.Context) (string, bool) {
	v, ok := c.Get(userIDContextKey).(string)
	if !ok || v == "" {
		return "", false
	}
	return v, true
}
