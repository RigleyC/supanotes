//go:build integration

package sync

import (
	"context"
	"os"
	"sync"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

var (
	testPool   *pgxpool.Pool
	testPoolMu sync.Once
)

func setupTestDB(t *testing.T) *pgxpool.Pool {
	t.Helper()
	testPoolMu.Do(func() {
		url := os.Getenv("TEST_DATABASE_URL")
		if url == "" {
			url = "postgres://supanotes:supanotes@localhost:5432/supanotes?sslmode=disable"
		}
		config, err := pgxpool.ParseConfig(url)
		if err != nil {
			t.Fatalf("failed to parse config: %v", err)
		}
		config.MaxConns = 10
		testPool, err = pgxpool.NewWithConfig(context.Background(), config)
		if err != nil {
			t.Fatalf("failed to create pool: %v", err)
		}
	})
	return testPool
}

func insertNoteForTest(t *testing.T, ctx context.Context, pool *pgxpool.Pool, noteID string) {
	t.Helper()
	_, err := pool.Exec(ctx,
		`INSERT INTO users (id, email, name, password_hash, created_at, updated_at) 
		 VALUES ('00000000-0000-0000-0000-000000000000', 'system@test.com', 'System', '', NOW(), NOW()) 
		 ON CONFLICT (id) DO NOTHING`,
	)
	require.NoError(t, err)

	_, err = pool.Exec(ctx,
		`INSERT INTO notes (id, user_id, content, created_at, updated_at) 
		 VALUES ($1, '00000000-0000-0000-0000-000000000000', '', NOW(), NOW()) 
		 ON CONFLICT (id) DO NOTHING`,
		noteID,
	)
	require.NoError(t, err)
	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, "DELETE FROM note_ws_leases WHERE note_id = $1", noteID)
		_, _ = pool.Exec(ctx, "DELETE FROM notes WHERE id = $1", noteID)
	})
}

func TestLeaseAcquireAndGet(t *testing.T) {
	pool := setupTestDB(t)
	mgr := NewLeaseManager(pool)
	ctx := context.Background()

	noteID := "00000000-0000-0000-0000-000000000001"
	insertNoteForTest(t, ctx, pool, noteID)
	machineID := "machine-a"

	_, acquired, err := mgr.AcquireLease(ctx, noteID, machineID)
	require.NoError(t, err)
	assert.True(t, acquired)

	got, err := mgr.GetLeaseMachine(ctx, noteID)
	require.NoError(t, err)
	assert.Equal(t, machineID, got)
}

func TestLeaseConflict(t *testing.T) {
	pool := setupTestDB(t)
	mgr := NewLeaseManager(pool)
	ctx := context.Background()

	noteID := "00000000-0000-0000-0000-000000000002"
	insertNoteForTest(t, ctx, pool, noteID)
	machineA := "machine-a"
	machineB := "machine-b"

	_, acquired, err := mgr.AcquireLease(ctx, noteID, machineA)
	require.NoError(t, err)
	assert.True(t, acquired)

	_, acquired, err = mgr.AcquireLease(ctx, noteID, machineB)
	require.NoError(t, err)
	assert.False(t, acquired)
}

func TestLeaseAcquireReturnsWinnerMachineID(t *testing.T) {
	pool := setupTestDB(t)
	mgr := NewLeaseManager(pool)
	ctx := context.Background()
	noteID := "00000000-0000-0000-0000-000000000100"
	insertNoteForTest(t, ctx, pool, noteID)
	machineID := "machine-a"

	winner, acquired, err := mgr.AcquireLease(ctx, noteID, machineID)
	require.NoError(t, err)
	assert.True(t, acquired)
	assert.Equal(t, machineID, winner)

	// A second machine contesting the lease must NOT get its own id.
	_, acquiredB, errB := mgr.AcquireLease(ctx, noteID, "machine-b")
	require.NoError(t, errB)
	assert.False(t, acquiredB)
}

func TestLeaseRelease(t *testing.T) {
	pool := setupTestDB(t)
	mgr := NewLeaseManager(pool)
	ctx := context.Background()

	noteID := "00000000-0000-0000-0000-000000000003"
	insertNoteForTest(t, ctx, pool, noteID)
	machineID := "machine-a"

	_, _, err := mgr.AcquireLease(ctx, noteID, machineID)
	require.NoError(t, err)

	err = mgr.ReleaseLease(ctx, noteID, machineID)
	require.NoError(t, err)

	got, err := mgr.GetLeaseMachine(ctx, noteID)
	assert.Error(t, err)
	assert.Equal(t, "", got)
}

func TestLeaseRenew(t *testing.T) {
	pool := setupTestDB(t)
	mgr := NewLeaseManager(pool)
	ctx := context.Background()

	noteID := "00000000-0000-0000-0000-000000000004"
	insertNoteForTest(t, ctx, pool, noteID)
	machineID := "machine-a"

	_, _, err := mgr.AcquireLease(ctx, noteID, machineID)
	require.NoError(t, err)

	err = mgr.RenewLease(ctx, noteID, machineID)
	require.NoError(t, err)

	_, err = mgr.GetLeaseMachine(ctx, noteID)
	require.NoError(t, err)
}

func TestLeaseExpiry(t *testing.T) {
	pool := setupTestDB(t)
	mgr := NewLeaseManager(pool)
	ctx := context.Background()

	noteID := "00000000-0000-0000-0000-000000000005"
	insertNoteForTest(t, ctx, pool, noteID)
	machineID := "machine-a"

	_, _, err := mgr.AcquireLease(ctx, noteID, machineID)
	require.NoError(t, err)

	// Shorten the lease to force expiry — we use raw SQL to set a past expires_at
	_, err = pool.Exec(ctx, "UPDATE note_ws_leases SET expires_at = NOW() - INTERVAL '1 second' WHERE note_id = $1", noteID)
	require.NoError(t, err)

	got, err := mgr.GetLeaseMachine(ctx, noteID)
	assert.Error(t, err)
	assert.Equal(t, "", got)
}
