package mcpapp

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/web"
	"github.com/RigleyC/supanotes/pkg/uid"
)

type contextKey string

const (
	userContextKey contextKey = "user_id"
	mcpScopesKey   contextKey = "mcp_scopes"
	mcpTokenIDKey  contextKey = "mcp_token_id"
)

var ErrNoUserInContext = errors.New("mcpapp: no user id in context")
var ErrMCPTokenInvalid = errors.New("mcpapp: invalid or revoked MCP token")
var ErrConfirmationDenied = errors.New("MCP confirmation is missing, expired, already consumed, or does not match the requested action")

const mcpTokenLifetime = 30 * 24 * time.Hour
const mcpConfirmationLifetime = 5 * time.Minute

type AuditEvent struct {
	TokenID  pgtype.UUID
	UserID   pgtype.UUID
	Agent    string
	ToolName string
	Resource string
	Result   string
}

type Confirmation struct {
	ID        pgtype.UUID
	ExpiresAt time.Time
}

// SecurityStore persists MCP audit events and one-time confirmations.
// The interface keeps tool handlers testable without bypassing production controls.
type SecurityStore interface {
	Audit(context.Context, AuditEvent) error
	CreateConfirmation(context.Context, pgtype.UUID, string, string, json.RawMessage) (Confirmation, error)
	ConsumeConfirmation(context.Context, pgtype.UUID, pgtype.UUID, string, string, json.RawMessage) error
}

type databaseSecurityStore struct{ pool *pgxpool.Pool }

type mcpTokenQuerier interface {
	QueryRow(context.Context, string, ...any) pgx.Row
}

func NewSecurityStore(pool *pgxpool.Pool) SecurityStore {
	if pool == nil {
		return nil
	}
	return &databaseSecurityStore{pool: pool}
}

func (s *databaseSecurityStore) Audit(ctx context.Context, event AuditEvent) error {
	var tokenID any
	if event.TokenID.Valid {
		tokenID = event.TokenID
	}
	_, err := s.pool.Exec(ctx, `
		INSERT INTO mcp_audit_log (token_id, user_id, agent, tool_name, resource, result)
		VALUES ($1, $2, $3, $4, $5, $6)`,
		tokenID, event.UserID, event.Agent, event.ToolName, event.Resource, event.Result)
	return err
}

func (s *databaseSecurityStore) CreateConfirmation(ctx context.Context, userID pgtype.UUID, toolName, resource string, arguments json.RawMessage) (Confirmation, error) {
	var confirmation Confirmation
	err := s.pool.QueryRow(ctx, `
		INSERT INTO mcp_confirmations (user_id, tool_name, resource, arguments, expires_at)
		VALUES ($1, $2, $3, $4::jsonb, $5)
		RETURNING id, expires_at`, userID, toolName, resource, arguments, time.Now().UTC().Add(mcpConfirmationLifetime)).Scan(&confirmation.ID, &confirmation.ExpiresAt)
	return confirmation, err
}

func (s *databaseSecurityStore) ConsumeConfirmation(ctx context.Context, userID, confirmationID pgtype.UUID, toolName, resource string, arguments json.RawMessage) error {
	var consumedID pgtype.UUID
	err := s.pool.QueryRow(ctx, `
		UPDATE mcp_confirmations
		SET consumed_at = NOW()
		WHERE id = $1 AND user_id = $2 AND tool_name = $3 AND resource = $4
		  AND arguments = $5::jsonb AND consumed_at IS NULL AND expires_at > NOW()
		RETURNING id`, confirmationID, userID, toolName, resource, arguments).Scan(&consumedID)
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrConfirmationDenied
	}
	return err
}

func issueMCPToken(ctx context.Context, db interface {
	QueryRow(context.Context, string, ...any) pgx.Row
}, userID pgtype.UUID, name string, scopes []string) (map[string]any, error) {
	tokenBytes := make([]byte, 32)
	if _, err := rand.Read(tokenBytes); err != nil {
		return nil, err
	}
	token := "sn_mcp_" + hex.EncodeToString(tokenBytes)
	expiresAt := time.Now().UTC().Add(mcpTokenLifetime)
	var tokenID pgtype.UUID
	if err := db.QueryRow(ctx, `
		INSERT INTO mcp_tokens (user_id, token_hash, name, scopes, expires_at)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING id`, userID, hashToken(token), name, scopes, expiresAt).Scan(&tokenID); err != nil {
		return nil, err
	}
	return map[string]any{
		"id":         tokenID.String(),
		"token":      token,
		"name":       name,
		"scopes":     scopes,
		"expires_at": expiresAt,
	}, nil
}

func requestedMCPScopes(raw string) ([]string, error) {
	if strings.TrimSpace(raw) == "" {
		return []string{"read", "write"}, nil
	}
	seen := map[string]bool{}
	var scopes []string
	for _, item := range strings.Split(raw, ",") {
		scope := strings.TrimSpace(item)
		if scope != "read" && scope != "write" {
			return nil, errors.New("MCP scopes must be read and/or write")
		}
		if !seen[scope] {
			seen[scope] = true
			scopes = append(scopes, scope)
		}
	}
	if len(scopes) == 0 {
		return nil, errors.New("at least one MCP scope is required")
	}
	return scopes, nil
}

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
		scopes, err := requestedMCPScopes(c.QueryParam("scopes"))
		if err != nil {
			return c.JSON(http.StatusBadRequest, map[string]string{"error": err.Error()})
		}
		result, err := issueMCPToken(c.Request().Context(), pool, userID, name, scopes)
		if err != nil {
			return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to persist token"})
		}
		return c.JSON(http.StatusCreated, result)
	}
}

func RevokeMCPTokenHandler(pool *pgxpool.Pool) echo.HandlerFunc {
	return func(c echo.Context) error {
		userID, err := web.UserID(c)
		if err != nil {
			return c.JSON(http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		}
		tokenID, err := uid.UUIDFromString(c.Param("id"))
		if err != nil || pool == nil {
			return c.JSON(http.StatusNotFound, map[string]string{"error": "MCP token not found"})
		}
		result, err := pool.Exec(c.Request().Context(), `UPDATE mcp_tokens SET revoked_at = NOW() WHERE id = $1 AND user_id = $2 AND revoked_at IS NULL`, tokenID, userID)
		if err != nil {
			return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to revoke MCP token"})
		}
		if result.RowsAffected() == 0 {
			return c.JSON(http.StatusNotFound, map[string]string{"error": "MCP token not found"})
		}
		return c.NoContent(http.StatusNoContent)
	}
}

func RotateMCPTokenHandler(pool *pgxpool.Pool) echo.HandlerFunc {
	return func(c echo.Context) error {
		userID, err := web.UserID(c)
		if err != nil {
			return c.JSON(http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		}
		oldID, err := uid.UUIDFromString(c.Param("id"))
		if err != nil || pool == nil {
			return c.JSON(http.StatusNotFound, map[string]string{"error": "MCP token not found"})
		}
		name := strings.TrimSpace(c.QueryParam("name"))
		if name == "" {
			name = "SupaNotes MCP"
		}
		tx, err := pool.Begin(c.Request().Context())
		if err != nil {
			return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to rotate MCP token"})
		}
		defer tx.Rollback(c.Request().Context())
		result, err := tx.Exec(c.Request().Context(), `UPDATE mcp_tokens SET revoked_at = NOW() WHERE id = $1 AND user_id = $2 AND revoked_at IS NULL`, oldID, userID)
		if err != nil || result.RowsAffected() == 0 {
			return c.JSON(http.StatusNotFound, map[string]string{"error": "MCP token not found"})
		}
		scopes, err := requestedMCPScopes(c.QueryParam("scopes"))
		if err != nil {
			return c.JSON(http.StatusBadRequest, map[string]string{"error": err.Error()})
		}
		newToken, err := issueMCPToken(c.Request().Context(), tx, userID, name, scopes)
		if err != nil {
			return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to rotate MCP token"})
		}
		if err := tx.Commit(c.Request().Context()); err != nil {
			return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to rotate MCP token"})
		}
		return c.JSON(http.StatusCreated, newToken)
	}
}

func authenticateMCPToken(ctx context.Context, db mcpTokenQuerier, token string) (pgtype.UUID, pgtype.UUID, []string, error) {
	if db == nil || token == "" {
		return pgtype.UUID{}, pgtype.UUID{}, nil, ErrMCPTokenInvalid
	}
	var tokenID, userID pgtype.UUID
	var scopes []string
	err := db.QueryRow(ctx, `UPDATE mcp_tokens SET last_used_at = NOW() WHERE token_hash = $1 AND revoked_at IS NULL AND expires_at > NOW() RETURNING id, user_id, scopes`, hashToken(token)).Scan(&tokenID, &userID, &scopes)
	if errors.Is(err, pgx.ErrNoRows) {
		return pgtype.UUID{}, pgtype.UUID{}, nil, ErrMCPTokenInvalid
	}
	if err != nil {
		return pgtype.UUID{}, pgtype.UUID{}, nil, err
	}
	return tokenID, userID, scopes, nil
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
			tokenID, userID, scopes, err := authenticateMCPToken(c.Request().Context(), pool, token)
			if errors.Is(err, ErrMCPTokenInvalid) {
				return c.JSON(http.StatusUnauthorized, map[string]string{"error": "invalid or revoked MCP token"})
			}
			if err != nil {
				return c.JSON(http.StatusInternalServerError, map[string]string{"error": "MCP authentication failed"})
			}
			ctx := context.WithValue(c.Request().Context(), userContextKey, userID)
			ctx = context.WithValue(ctx, mcpScopesKey, scopes)
			ctx = context.WithValue(ctx, mcpTokenIDKey, tokenID)
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

func TokenIDFromContext(ctx context.Context) pgtype.UUID {
	v, _ := ctx.Value(mcpTokenIDKey).(pgtype.UUID)
	return v
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

func requireReadScope(ctx context.Context) error {
	if !HasScope(ctx, "read") {
		return errors.New("MCP token lacks read scope")
	}
	return nil
}
