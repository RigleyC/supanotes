package auth

import (
	"net/http"
	"strings"

	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/web"
	authpkg "github.com/RigleyC/supanotes/pkg/auth"
	"github.com/RigleyC/supanotes/pkg/config"
)

// JWT returns middleware that extracts and validates a Bearer token,
// then stuffs the user ID into the Echo context via web.SetUserID.
func JWT(cfg *config.Config) echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			header := c.Request().Header.Get(echo.HeaderAuthorization)
			if header == "" {
				// Fallback for WebSocket connections: mobile platforms (Android/iOS)
				// cannot send custom headers during WS handshake, so the token is
				// passed as a query param instead.
				if q := c.QueryParam("token"); q != "" {
					header = "Bearer " + q
				}
			}
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

			web.SetUserID(c, claims.UserID)
			return next(c)
		}
	}
}
