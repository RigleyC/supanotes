package sync

import (
	"context"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func setupTestDB(t *testing.T) *pgxpool.Pool {
	t.Helper()
	pool, err := pgxpool.New(context.Background(), "postgres://supanotes:supanotes@localhost:5432/supanotes?sslmode=disable")
	require.NoError(t, err)
	t.Cleanup(pool.Close)
	return pool
}

func TestLeaseAcquireAndGet(t *testing.T) {
	pool := setupTestDB(t)
	mgr := NewLeaseManager(pool)
	ctx := context.Background()

	noteID := "00000000-0000-0000-0000-000000000001"
	machineID := "machine-a"

	_, acquired, err := mgr.AcquireLease(ctx, noteID, machineID)
	require.NoError(t, err)
	assert.True(t, acquired)

	got, err := mgr.GetLeaseMachine(ctx, noteID)
	require.NoError(t, err)
	assert.Equal(t, machineID, got)

	t.Cleanup(func() {
		mgr.ReleaseLease(ctx, noteID, machineID)
	})
}

func TestLeaseConflict(t *testing.T) {
	pool := setupTestDB(t)
	mgr := NewLeaseManager(pool)
	ctx := context.Background()

	noteID := "00000000-0000-0000-0000-000000000002"
	machineA := "machine-a"
	machineB := "machine-b"

	_, acquired, err := mgr.AcquireLease(ctx, noteID, machineA)
	require.NoError(t, err)
	assert.True(t, acquired)

	_, acquired, err = mgr.AcquireLease(ctx, noteID, machineB)
	require.NoError(t, err)
	assert.False(t, acquired)

	t.Cleanup(func() {
		mgr.ReleaseLease(ctx, noteID, machineA)
	})
}

func TestLeaseAcquireReturnsWinnerMachineID(t *testing.T) {
	pool := setupTestDB(t)
	mgr := NewLeaseManager(pool)
	ctx := context.Background()
	noteID := "00000000-0000-0000-0000-000000000100"
	machineID := "machine-a"

	winner, acquired, err := mgr.AcquireLease(ctx, noteID, machineID)
	require.NoError(t, err)
	assert.True(t, acquired)
	assert.Equal(t, machineID, winner)

	// A second machine contesting the lease must NOT get its own id.
	_, acquiredB, errB := mgr.AcquireLease(ctx, noteID, "machine-b")
	require.NoError(t, errB)
	assert.False(t, acquiredB)

	t.Cleanup(func() { mgr.ReleaseLease(ctx, noteID, machineID) })
}

func TestLeaseRelease(t *testing.T) {
	pool := setupTestDB(t)
	mgr := NewLeaseManager(pool)
	ctx := context.Background()

	noteID := "00000000-0000-0000-0000-000000000003"
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
	machineID := "machine-a"

	_, _, err := mgr.AcquireLease(ctx, noteID, machineID)
	require.NoError(t, err)

	err = mgr.RenewLease(ctx, noteID, machineID)
	require.NoError(t, err)

	_, err = mgr.GetLeaseMachine(ctx, noteID)
	require.NoError(t, err)

	t.Cleanup(func() {
		mgr.ReleaseLease(ctx, noteID, machineID)
	})
}

func TestLeaseExpiry(t *testing.T) {
	pool := setupTestDB(t)
	mgr := NewLeaseManager(pool)
	ctx := context.Background()

	noteID := "00000000-0000-0000-0000-000000000005"
	machineID := "machine-a"

	_, _, err := mgr.AcquireLease(ctx, noteID, machineID)
	require.NoError(t, err)

	// Shorten the lease to force expiry — we use raw SQL to set a past expires_at
	_, err = pool.Exec(ctx, "UPDATE note_ws_leases SET expires_at = NOW() - INTERVAL '1 second' WHERE note_id = $1", noteID)
	require.NoError(t, err)

	got, err := mgr.GetLeaseMachine(ctx, noteID)
	assert.Error(t, err)
	assert.Equal(t, "", got)

	t.Cleanup(func() {
		mgr.ReleaseLease(ctx, noteID, machineID)
	})
}
