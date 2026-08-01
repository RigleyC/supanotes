package auth

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"runtime"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/require"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/pkg/config"
	"github.com/RigleyC/supanotes/pkg/migrate"
)

// This opt-in test exercises refresh-family revocation through a real
// PostgreSQL transaction. Set SUPANOTES_AUTH_TEST_DATABASE_URL to a disposable
// database to run it.
func TestRefreshReuseCommitsFamilyRevocation(t *testing.T) {
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
		JWTSecret:   "integration-secret-at-least-32-characters-long",
		JWTIssuer:   "supanotes-api",
		JWTAudience: "supanotes-client",
	}
	service := NewService(queries, cfg, pool)
	email := "refresh-reuse-" + uuid.NewString() + "@example.com"
	session, _, originalRefresh, err := service.Register(ctx, email, "correct-horse-battery", "Refresh Test")
	require.NoError(t, err)
	defer func() {
		_, _ = pool.Exec(ctx, "DELETE FROM users WHERE id = $1", session.User.ID)
	}()

	type refreshResult struct {
		refreshToken string
		err          error
	}
	results := make(chan refreshResult, 2)
	var waitGroup sync.WaitGroup
	waitGroup.Add(2)
	for range 2 {
		go func() {
			defer waitGroup.Done()
			_, refreshToken, refreshErr := service.Refresh(ctx, originalRefresh)
			results <- refreshResult{refreshToken: refreshToken, err: refreshErr}
		}()
	}
	waitGroup.Wait()
	close(results)

	var childRefresh string
	var successCount, reuseCount int
	for result := range results {
		if result.err == nil {
			successCount++
			childRefresh = result.refreshToken
			continue
		}
		if errors.Is(result.err, ErrRefreshTokenReuse) {
			reuseCount++
			continue
		}
		t.Fatalf("unexpected concurrent refresh error: %v", result.err)
	}
	require.Equal(t, 1, successCount)
	require.Equal(t, 1, reuseCount)

	_, _, err = service.Refresh(ctx, childRefresh)
	require.ErrorIs(t, err, ErrInvalidRefreshToken)

	var revokedCount int
	err = pool.QueryRow(ctx, "SELECT COUNT(*) FROM refresh_tokens WHERE user_id = $1 AND revoked_at IS NOT NULL", session.User.ID).Scan(&revokedCount)
	require.NoError(t, err)
	require.Equal(t, 2, revokedCount)
}
