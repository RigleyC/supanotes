package mcpapp

import (
	"context"
	"errors"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/web"
	"github.com/RigleyC/supanotes/pkg/auth"
	"github.com/RigleyC/supanotes/pkg/config"
	"github.com/RigleyC/supanotes/pkg/uid"
)

type contextKey string

const userContextKey contextKey = "user_id"

// ErrNoUserInContext is returned when the user ID is not found in the context.
var ErrNoUserInContext = errors.New("mcpapp: no user id in context")

// GenerateMCPTokenHandler generates a long-lived JWT token for the authenticated user.
func GenerateMCPTokenHandler(cfg *config.Config) echo.HandlerFunc {
	return func(c echo.Context) error {
		userID, err := web.UserID(c)
		if err != nil {
			return c.JSON(http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		}

		token, err := auth.GenerateAccessToken(uid.UUIDToString(userID), cfg.JWTSecret, 365*24*time.Hour)
		if err != nil {
			return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to generate token"})
		}

		return c.JSON(http.StatusOK, map[string]string{"mcp_token": token})
	}
}

// PropagateUserContext extracts the user ID from the Echo context and places it in the standard HTTP context.
func PropagateUserContext(next http.Handler) echo.HandlerFunc {
	return func(c echo.Context) error {
		userID, err := web.UserID(c)
		if err != nil {
			return c.JSON(http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		}

		ctx := context.WithValue(c.Request().Context(), userContextKey, userID)
		c.SetRequest(c.Request().WithContext(ctx))

		next.ServeHTTP(c.Response(), c.Request())
		return nil
	}
}

// UserIDFromContext retrieves the user's UUID from the standard context.
func UserIDFromContext(ctx context.Context) (pgtype.UUID, error) {
	v, ok := ctx.Value(userContextKey).(pgtype.UUID)
	if !ok {
		return pgtype.UUID{}, ErrNoUserInContext
	}
	return v, nil
}
