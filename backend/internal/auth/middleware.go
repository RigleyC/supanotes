package auth

import (
	"net/http"
	"strings"

	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/web"
	authpkg "github.com/RigleyC/supanotes/pkg/auth"
	"github.com/RigleyC/supanotes/pkg/config"
)

const userIDContextKey = "user_id"

// JWT returns middleware that extracts and validates a Bearer token,
// then stuffs the user ID into the Echo context under userIDContextKey.
func JWT(cfg *config.Config) echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			header := c.Request().Header.Get(echo.HeaderAuthorization)
			if header == "" {
				return web.JSONError(c, http.StatusUnauthorized, "missing authorization header")
			}

			const prefix = "Bearer "
			if !strings.HasPrefix(header, prefix) {
				return web.JSONError(c, http.StatusUnauthorized, "invalid authorization scheme")
			}

			token := strings.TrimSpace(strings.TrimPrefix(header, prefix))
			if token == "" {
				return web.JSONError(c, http.StatusUnauthorized, "empty bearer token")
			}

			claims, err := authpkg.ParseAccessToken(token, cfg.JWTSecret)
			if err != nil {
				return web.JSONError(c, http.StatusUnauthorized, "invalid or expired token")
			}

			c.Set(userIDContextKey, claims.UserID)
			return next(c)
		}
	}
}

// UserIDFromContext returns the authenticated user ID set by the JWT
// middleware. Use only inside handlers behind JWT().
func UserIDFromContext(c echo.Context) (string, bool) {
	v, ok := c.Get(userIDContextKey).(string)
	if !ok || v == "" {
		return "", false
	}
	return v, true
}
