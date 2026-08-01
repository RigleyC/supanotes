package alexa

import (
	"context"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/labstack/echo/v4"
	"github.com/stretchr/testify/require"

	internalauth "github.com/RigleyC/supanotes/internal/auth"
	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/pkg/config"
	"github.com/RigleyC/supanotes/pkg/migrate"
)

// This opt-in test exercises Alexa refresh-family revocation through the real
// PostgreSQL update race. Set SUPANOTES_AUTH_TEST_DATABASE_URL to a disposable
// database to run it.
func TestOAuthRefreshReuseRevokesFamily(t *testing.T) {
	databaseURL := os.Getenv("SUPANOTES_AUTH_TEST_DATABASE_URL")
	if databaseURL == "" {
		t.Skip("SUPANOTES_AUTH_TEST_DATABASE_URL is not configured")
	}

	_, currentFile, _, ok := runtime.Caller(0)
	require.True(t, ok)
	migrationPath := filepath.ToSlash(filepath.Join(filepath.Dir(currentFile), "../../db/migrations"))
	require.NoError(t, migrate.Up(databaseURL, migrationPath))

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	pool, err := pgxpool.New(ctx, databaseURL)
	require.NoError(t, err)
	defer pool.Close()

	queries := sqlcgen.New(pool)
	cfg := &config.Config{
		JWTSecret:         "integration-secret-at-least-32-characters-long",
		JWTIssuer:         "supanotes-api",
		JWTAudience:       "supanotes-client",
		AlexaClientID:     "alexa-client",
		AlexaClientSecret: "alexa-secret",
		AlexaRedirectURIs: []string{"https://example.com/alexa/callback"},
	}
	authService := internalauth.NewService(queries, cfg, pool)
	email := "alexa-refresh-" + time.Now().UTC().Format("20060102150405.000000000") + "@example.com"
	session, _, _, err := authService.Register(ctx, email, "correct-horse-battery", "Alexa Test")
	require.NoError(t, err)
	defer func() {
		_, _ = pool.Exec(ctx, "DELETE FROM users WHERE id = $1", session.User.ID)
	}()

	originalRefresh, err := randomCode()
	require.NoError(t, err)
	_, err = pool.Exec(ctx, `
		INSERT INTO alexa_authorization_codes
		(code_hash,user_id,client_id,redirect_uri,expires_at,refresh_token_hash,refresh_expires_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7)`,
		hashCode("authorization-code"),
		session.User.ID,
		cfg.AlexaClientID,
		cfg.AlexaRedirectURIs[0],
		time.Now().Add(5*time.Minute),
		hashCode(originalRefresh),
		time.Now().Add(90*24*time.Hour),
	)
	require.NoError(t, err)

	handler := NewOAuthHandler(authService, pool, cfg)
	statuses := make(chan int, 2)
	errors := make(chan error, 2)
	var waitGroup sync.WaitGroup
	waitGroup.Add(2)
	for range 2 {
		go func() {
			defer waitGroup.Done()
			form := url.Values{
				"refresh_token": {originalRefresh},
			}
			req := httptest.NewRequest(
				http.MethodPost,
				"/oauth/token",
				strings.NewReader(form.Encode()),
			)
			req.Header.Set(echo.HeaderContentType, echo.MIMEApplicationForm)
			recorder := httptest.NewRecorder()
			err := handler.refresh(echo.New().NewContext(req, recorder))
			errors <- err
			statuses <- recorder.Code
		}()
	}
	waitGroup.Wait()
	close(statuses)
	close(errors)
	for handlerErr := range errors {
		require.NoError(t, handlerErr)
	}

	counts := map[int]int{}
	for status := range statuses {
		counts[status]++
	}
	require.Equal(t, 1, counts[http.StatusOK])
	require.Equal(t, 1, counts[http.StatusBadRequest])

	var revokedAt pgtype.Timestamptz
	err = pool.QueryRow(ctx, `
		SELECT refresh_revoked_at
		FROM alexa_authorization_codes
		WHERE code_hash=$1`, hashCode("authorization-code")).Scan(&revokedAt)
	require.NoError(t, err)
	require.True(t, revokedAt.Valid)
}
