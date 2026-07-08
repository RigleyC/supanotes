package sync

import (
	"fmt"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/web"
	"github.com/RigleyC/supanotes/pkg/uid"
)

type rateLimiter struct {
	mu         sync.Mutex
	timestamps []time.Time
}

func newRateLimiter() *rateLimiter {
	return &rateLimiter{}
}

func (rl *rateLimiter) Allow() bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	now := time.Now()
	window := now.Add(-1 * time.Second)

	filtered := rl.timestamps[:0]
	for _, t := range rl.timestamps {
		if t.After(window) {
			filtered = append(filtered, t)
		}
	}
	rl.timestamps = filtered

	if len(rl.timestamps) >= 50 {
		return false
	}

	rl.timestamps = append(rl.timestamps, now)
	return true
}

type WSHandler struct {
	roomMgr   *RoomManager
	pool      *pgxpool.Pool
	upgrader  websocket.Upgrader
	machineID string
}

func NewWSHandler(roomMgr *RoomManager, pool *pgxpool.Pool, machineID string) *WSHandler {
	return &WSHandler{
		roomMgr:   roomMgr,
		pool:      pool,
		machineID: machineID,
		upgrader: websocket.Upgrader{
			CheckOrigin:     func(r *http.Request) bool { return true },
			ReadBufferSize:  1024,
			WriteBufferSize: 1024,
		},
	}
}

func (h *WSHandler) HandleConnect(c echo.Context) error {
	noteID := c.Param("note_id")

	userIDStr, ok := web.UserIDFromContext(c)
	if !ok {
		return web.JSONError(c, http.StatusUnauthorized, "unauthorized")
	}

	userID, err := uid.UUIDFromString(userIDStr)
	if err != nil {
		return web.JSONError(c, http.StatusBadRequest, "invalid user id")
	}

	ctx := c.Request().Context()

	// Check read permission via fly-replay redirect
	var hasAccess bool
	err = h.pool.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM notes WHERE id = $1 AND user_id = $2
			UNION ALL
			SELECT 1 FROM note_shares WHERE note_id = $1 AND user_id = $2
		)
	`, noteID, userID).Scan(&hasAccess)
	if err != nil {
		c.Logger().Errorf("permission check failed: %v", err)
		return web.JSONError(c, http.StatusInternalServerError, "permission check failed")
	}
	if !hasAccess {
		return web.JSONError(c, http.StatusForbidden, "access denied")
	}

	// Check lease for fly-replay routing
	var leaseMachine string
	err = h.pool.QueryRow(ctx, "SELECT machine_id FROM note_ws_leases WHERE note_id = $1 AND expires_at > NOW()", noteID).Scan(&leaseMachine)
	if err == nil && leaseMachine != "" && leaseMachine != h.machineID {
		c.Response().Header().Set("fly-replay", leaseMachine)
		return c.NoContent(http.StatusServiceUnavailable)
	}

	conn, err := h.upgrader.Upgrade(c.Response(), c.Request(), nil)
	if err != nil {
		return fmt.Errorf("websocket upgrade: %w", err)
	}

	room, err := h.roomMgr.GetOrCreateRoom(ctx, noteID, h.machineID)
	if err != nil {
		conn.Close()
		return fmt.Errorf("get or create room: %w", err)
	}

	if err := room.HandleHandshake(conn); err != nil {
		conn.Close()
		return fmt.Errorf("handshake: %w", err)
	}

	rl := newRateLimiter()

	// Cache edit permission at connection time
	var canEdit bool
	err = h.pool.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM notes WHERE id = $1 AND user_id = $2
			UNION ALL
			SELECT 1 FROM note_shares WHERE note_id = $1 AND user_id = $2 AND permission = 'edit'
		)
	`, noteID, userID).Scan(&canEdit)
	if err != nil {
		c.Logger().Errorf("edit permission check failed: %v", err)
	}

	defer func() {
		room.RemoveClient(conn)
		conn.Close()
	}()

	for {
		_, msg, err := conn.ReadMessage()
		if err != nil {
			break
		}

		if !rl.Allow() {
			continue
		}

		if !canEdit {
			continue
		}

		room.HandleIncomingUpdate(msg, conn)
	}

	return nil
}
