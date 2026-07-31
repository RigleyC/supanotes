package mcpapp

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/web"
)

type contextKey string

const (
	userContextKey contextKey = "user_id"
	mcpScopesKey   contextKey = "mcp_scopes"
)

var ErrNoUserInContext = errors.New("mcpapp: no user id in context")
var ErrMCPTokenInvalid = errors.New("mcpapp: invalid or revoked token")

func GenerateMCPTokenHandler(pool *pgxpool.Pool) echo.HandlerFunc {
	return func(c echo.Context) error {
		userID, err := web.UserID(c)
		if err != nil {
			return c.JSON(http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		}
		if pool == nil {
			return c.JSON(http.StatusInternalServerError, map[string]string{"error": "database unavailable"})
		}
		name := strings.TrimSpace(c.QueryParam("name"))
		if name == "" {
			name = "SupaNotes MCP"
		}
		tokenBytes := make([]byte, 32)
		if _, err := rand.Read(tokenBytes); err != nil {
			return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to generate token"})
		}
		token := "sn_mcp_" + hex.EncodeToString(tokenBytes)
		hash := hashToken(token)
		_, err = pool.Exec(c.Request().Context(), `INSERT INTO mcp_tokens (user_id, token_hash, name, scopes, expires_at) VALUES ($1,$2,$3,$4,$5)`, userID, hash, name, []string{"read", "write"}, time.Now().UTC().Add(30*24*time.Hour))
		if err != nil {
			return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to persist token"})
		}
		return c.JSON(http.StatusCreated, map[string]any{"token": token, "name": name, "scopes": []string{"read", "write"}, "expires_at": time.Now().UTC().Add(30 * 24 * time.Hour)})
	}
}

func MCPAuth(pool *pgxpool.Pool) echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			header := c.Request().Header.Get(echo.HeaderAuthorization)
			if !strings.HasPrefix(header, "Bearer ") {
				return c.JSON(http.StatusUnauthorized, map[string]string{"error": "missing MCP bearer token"})
			}
			token := strings.TrimSpace(strings.TrimPrefix(header, "Bearer "))
			if pool == nil || token == "" {
				return c.JSON(http.StatusUnauthorized, map[string]string{"error": "invalid MCP token"})
			}
			var userID pgtype.UUID
			var scopes []string
			err := pool.QueryRow(c.Request().Context(), `UPDATE mcp_tokens SET last_used_at = NOW() WHERE token_hash = $1 AND revoked_at IS NULL AND expires_at > NOW() RETURNING user_id, scopes`, hashToken(token)).Scan(&userID, &scopes)
			if errors.Is(err, pgx.ErrNoRows) {
				return c.JSON(http.StatusUnauthorized, map[string]string{"error": "invalid or revoked MCP token"})
			}
			if err != nil {
				return c.JSON(http.StatusInternalServerError, map[string]string{"error": "MCP authentication failed"})
			}
			ctx := context.WithValue(c.Request().Context(), userContextKey, userID)
			ctx = context.WithValue(ctx, mcpScopesKey, scopes)
			c.SetRequest(c.Request().WithContext(ctx))
			return next(c)
		}
	}
}

func hashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

func UserIDFromContext(ctx context.Context) (pgtype.UUID, error) {
	v, ok := ctx.Value(userContextKey).(pgtype.UUID)
	if !ok {
		return pgtype.UUID{}, ErrNoUserInContext
	}
	return v, nil
}
func HasScope(ctx context.Context, scope string) bool {
	scopes, _ := ctx.Value(mcpScopesKey).([]string)
	for _, value := range scopes {
		if value == scope {
			return true
		}
	}
	return false
}

func requireWriteScope(ctx context.Context) error {
	if !HasScope(ctx, "write") {
		return errors.New("MCP token lacks write scope")
	}
	return nil
}
func PropagateUserContext(next http.Handler) echo.HandlerFunc {
	return func(c echo.Context) error { next.ServeHTTP(c.Response(), c.Request()); return nil }
}
