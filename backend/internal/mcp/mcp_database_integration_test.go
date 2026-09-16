package mcpapp

import (
	"context"
	"encoding/json"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/RigleyC/supanotes/pkg/uid"
)

// This opt-in test exercises the production confirmation SQL against PostgreSQL.
// Set SUPANOTES_MCP_TEST_DATABASE_URL to a disposable test database to run it.
func TestDatabaseConfirmationExecution_reclaimsExpiredLeaseReplaysAndFences(t *testing.T) {
	databaseURL := os.Getenv("SUPANOTES_MCP_TEST_DATABASE_URL")
	if databaseURL == "" {
		t.Skip("SUPANOTES_MCP_TEST_DATABASE_URL is not configured")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	config, err := pgxpool.ParseConfig(databaseURL)
	require.NoError(t, err)
	config.MaxConns = 1
	pool, err := pgxpool.NewWithConfig(ctx, config)
	require.NoError(t, err)
	defer pool.Close()
	require.NoError(t, pool.Ping(ctx))

	connection, err := pool.Acquire(ctx)
	require.NoError(t, err)
	_, err = connection.Exec(ctx, `
		CREATE TEMP TABLE mcp_confirmations (
			id UUID PRIMARY KEY,
			user_id UUID NOT NULL,
			tool_name TEXT NOT NULL,
			resource TEXT NOT NULL,
			arguments JSONB NOT NULL,
			expires_at TIMESTAMPTZ NOT NULL,
			consumed_at TIMESTAMPTZ,
			reserved_at TIMESTAMPTZ,
			execution_status TEXT NOT NULL DEFAULT 'available',
			result JSONB,
			execution_owner_token TEXT,
			execution_lease_until TIMESTAMPTZ,
			created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)`)
	require.NoError(t, err)
	connection.Release()

	store := &databaseSecurityStore{pool: pool}
	userID, err := uid.UUIDFromString("123e4567-e89b-12d3-a456-426614174000")
	require.NoError(t, err)
	arguments := json.RawMessage(`{"id":"note-1"}`)
	confirmation, err := store.CreateConfirmation(ctx, userID, toolDeleteNote, "note:note-1", arguments)
	require.NoError(t, err)

	lease, err := store.ReserveConfirmation(ctx, userID, confirmation.ID, toolDeleteNote, "note:note-1", arguments)
	require.NoError(t, err)
	require.NoError(t, lease.Commit(ctx, json.RawMessage(`{"deleted":true}`)))
	replay, err := store.ReserveConfirmation(ctx, userID, confirmation.ID, toolDeleteNote, "note:note-1", arguments)
	require.NoError(t, err)
	replayed, ok := replay.ReplayResult()
	require.True(t, ok)
	assert.JSONEq(t, `{"deleted":true}`, string(replayed))

	second, err := store.CreateConfirmation(ctx, userID, toolDeleteNote, "note:note-1", arguments)
	require.NoError(t, err)
	released, err := store.ReserveConfirmation(ctx, userID, second.ID, toolDeleteNote, "note:note-1", arguments)
	require.NoError(t, err)
	require.NoError(t, released.Release(ctx))
	reusable, err := store.ReserveConfirmation(ctx, userID, second.ID, toolDeleteNote, "note:note-1", arguments)
	require.NoError(t, err)
	require.NoError(t, reusable.Commit(ctx, json.RawMessage(`"deleted"`)))

	stale, err := store.CreateConfirmation(ctx, userID, toolDeleteNote, "note:note-1", arguments)
	require.NoError(t, err)
	first, err := store.ReserveConfirmation(ctx, userID, stale.ID, toolDeleteNote, "note:note-1", arguments)
	require.NoError(t, err)
	_, err = pool.Exec(ctx, `UPDATE mcp_confirmations SET execution_lease_until = NOW() - INTERVAL '10 minutes' WHERE id = $1`, stale.ID)
	require.NoError(t, err)
	secondLease, err := store.ReserveConfirmation(ctx, userID, stale.ID, toolDeleteNote, "note:note-1", arguments)
	require.NoError(t, err)
	assert.ErrorIs(t, first.Commit(ctx, json.RawMessage(`"stale"`)), ErrConfirmationDenied)
	require.NoError(t, secondLease.Commit(ctx, json.RawMessage(`"deleted"`)))
	replay, err = store.ReserveConfirmation(ctx, userID, stale.ID, toolDeleteNote, "note:note-1", arguments)
	require.NoError(t, err)
	replayed, ok = replay.ReplayResult()
	require.True(t, ok)
	assert.JSONEq(t, `"deleted"`, string(replayed))
}
