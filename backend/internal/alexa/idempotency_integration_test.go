package alexa

import (
	"context"
	"os"
	"path/filepath"
	"runtime"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/require"

	"github.com/RigleyC/supanotes/pkg/migrate"
)

// This opt-in test uses two independent pools to exercise the same persistent
// reservation as separate handler processes would. Set
// SUPANOTES_ALEXA_TEST_DATABASE_URL to a disposable PostgreSQL database.
func TestPostgresIdempotencyReplayConcurrencyAndRecovery(t *testing.T) {
	databaseURL := os.Getenv("SUPANOTES_ALEXA_TEST_DATABASE_URL")
	if databaseURL == "" {
		t.Skip("SUPANOTES_ALEXA_TEST_DATABASE_URL is not configured")
	}

	_, currentFile, _, ok := runtime.Caller(0)
	require.True(t, ok)
	migrationPath := filepath.ToSlash(filepath.Join(filepath.Dir(currentFile), "../../db/migrations"))
	require.NoError(t, migrate.Up(databaseURL, migrationPath))

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	pool1, err := pgxpool.New(ctx, databaseURL)
	require.NoError(t, err)
	defer pool1.Close()
	pool2, err := pgxpool.New(ctx, databaseURL)
	require.NoError(t, err)
	defer pool2.Close()

	const applicationID = "alexa-idempotency-integration-test"
	_, err = pool1.Exec(ctx, "DELETE FROM alexa_request_idempotency WHERE application_id = $1", applicationID)
	require.NoError(t, err)
	defer func() {
		_, _ = pool1.Exec(context.Background(), "DELETE FROM alexa_request_idempotency WHERE application_id = $1", applicationID)
	}()

	store1 := NewPostgresIdempotencyStore(pool1)
	store2 := NewPostgresIdempotencyStore(pool2)

	first, err := store1.Acquire(ctx, applicationID, "replay", "fingerprint-a")
	require.NoError(t, err)

	var waitGroup sync.WaitGroup
	waitGroup.Add(1)
	concurrent := make(chan idempotencyDecision, 1)
	concurrentErr := make(chan error, 1)
	go func() {
		defer waitGroup.Done()
		decision, acquireErr := store2.Acquire(ctx, applicationID, "replay", "fingerprint-a")
		concurrent <- decision
		concurrentErr <- acquireErr
	}()
	waitGroup.Wait()
	require.NoError(t, <-concurrentErr)
	require.True(t, (<-concurrent).pending)

	want := speak("replayed result")
	require.NoError(t, store1.Complete(ctx, first.reservation, want))
	replay, err := store2.Acquire(ctx, applicationID, "replay", "fingerprint-a")
	require.NoError(t, err)
	require.NotNil(t, replay.response)
	require.Equal(t, want, *replay.response)

	_, err = store2.Acquire(ctx, applicationID, "replay", "fingerprint-b")
	require.ErrorIs(t, err, errRequestIDPayloadMismatch)

	// A new store instance sees the completed result, simulating a process restart.
	restarted := NewPostgresIdempotencyStore(pool2)
	restartedReplay, err := restarted.Acquire(ctx, applicationID, "replay", "fingerprint-a")
	require.NoError(t, err)
	require.NotNil(t, restartedReplay.response)
	require.Equal(t, want, *restartedReplay.response)

	// An abandoned pending reservation remains recoverable after its lease.
	store1.leaseTTL = 50 * time.Millisecond
	store2.leaseTTL = 50 * time.Millisecond
	pending, err := store1.Acquire(ctx, applicationID, "recovery", "fingerprint-c")
	require.NoError(t, err)
	time.Sleep(100 * time.Millisecond)
	recovered, err := store2.Acquire(ctx, applicationID, "recovery", "fingerprint-c")
	require.NoError(t, err)
	require.False(t, recovered.pending)
	require.NotEqual(t, pending.reservation.ownerToken, recovered.reservation.ownerToken)
	require.NoError(t, store2.Complete(ctx, recovered.reservation, speak("recovered result")))
}
