//go:build integration

package sync

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/labstack/echo/v4"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestWSHandler_FlyReplay(t *testing.T) {
	pool := setupTestDB(t)
	ctx := context.Background()

	noteID := "00000000-0000-0000-0000-000000000099"
	insertNoteForTest(t, ctx, pool, noteID)

	// Simulate lease held by another machine
	otherMachine := "machine-other"
	_, err := pool.Exec(ctx,
		"INSERT INTO note_ws_leases (note_id, machine_id, expires_at) VALUES ($1, $2, NOW() + INTERVAL '10 seconds') ON CONFLICT (note_id) DO UPDATE SET machine_id = $2, expires_at = NOW() + INTERVAL '10 seconds'",
		noteID, otherMachine,
	)
	require.NoError(t, err)

	e := echo.New()
	req := httptest.NewRequest(http.MethodGet, "/api/v1/sync/"+noteID+"/ws", nil)
	rec := httptest.NewRecorder()
	c := e.NewContext(req, rec)
	c.SetPath("/api/v1/sync/:note_id/ws")
	c.SetParamNames("note_id")
	c.SetParamValues(noteID)

	// Set authorized user context
	c.Set("user_id", "00000000-0000-0000-0000-000000000000")

	roomMgr := NewRoomManager(newMockLeaseManager(), NewYDocService(pool, nil, nil, "test"), pool)
	handler := NewWSHandler(ctx, roomMgr, pool, "machine-local")

	err = handler.HandleConnect(c)
	require.NoError(t, err)

	// Should redirect with 503 Service Unavailable and fly-replay header
	assert.Equal(t, http.StatusServiceUnavailable, rec.Code)
	assert.Equal(t, "instance="+otherMachine, rec.Header().Get("fly-replay"))
}

func TestWSHandler_AccessDenied(t *testing.T) {
	pool := setupTestDB(t)
	ctx := context.Background()

	noteID := "00000000-0000-0000-0000-000000000088"
	// Do NOT insert note or permissions for this note, or insert it for a different user.
	// We'll create a different user first
	_, err := pool.Exec(ctx,
		`INSERT INTO users (id, email, name, password_hash, created_at, updated_at) 
		 VALUES ('00000000-0000-0000-0000-000000000009', 'other@test.com', 'Other', '', NOW(), NOW()) 
		 ON CONFLICT (id) DO NOTHING`,
	)
	require.NoError(t, err)

	_, err = pool.Exec(ctx,
		`INSERT INTO notes (id, user_id, content, created_at, updated_at) 
		 VALUES ($1, '00000000-0000-0000-0000-000000000009', '', NOW(), NOW()) 
		 ON CONFLICT (id) DO NOTHING`,
		noteID,
	)
	require.NoError(t, err)
	defer func() {
		_, _ = pool.Exec(ctx, "DELETE FROM notes WHERE id = $1", noteID)
	}()

	e := echo.New()
	req := httptest.NewRequest(http.MethodGet, "/api/v1/sync/"+noteID+"/ws", nil)
	rec := httptest.NewRecorder()
	c := e.NewContext(req, rec)
	c.SetPath("/api/v1/sync/:note_id/ws")
	c.SetParamNames("note_id")
	c.SetParamValues(noteID)

	// User trying to access has ID 0000-0000, but note belongs to 0000-0009
	c.Set("user_id", "00000000-0000-0000-0000-000000000000")

	roomMgr := NewRoomManager(newMockLeaseManager(), NewYDocService(pool, nil, nil, "test"), pool)
	handler := NewWSHandler(ctx, roomMgr, pool, "machine-local")

	err = handler.HandleConnect(c)
	require.NoError(t, err)

	// Should return 403 Forbidden
	assert.Equal(t, http.StatusForbidden, rec.Code)
}

func TestWSHandler_RateBucket(t *testing.T) {
	// Test Rate Limiter logic directly
	tb := newTokenBucket(3, 10) // capacity 3, refill 10 per sec
	assert.True(t, tb.Allow())
	assert.True(t, tb.Allow())
	assert.True(t, tb.Allow())
	assert.False(t, tb.Allow()) // capacity exhausted

	time.Sleep(150 * time.Millisecond) // wait for 1.5 tokens to refill
	assert.True(t, tb.Allow())
}
