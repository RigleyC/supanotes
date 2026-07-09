package sync

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/web"
	"github.com/RigleyC/supanotes/pkg/uid"
)

type permissionSub struct {
	noteID string
	userID string
	connID string
}

type PermissionListener struct {
	mu     sync.RWMutex
	subs   map[permissionSub]func()
	log    *slog.Logger
	nextID int64
}

type permissionEvent struct {
	NoteID string `json:"note_id"`
	UserID string `json:"user_id"`
}

func NewPermissionListener(ctx context.Context, pool *pgxpool.Pool, log *slog.Logger) *PermissionListener {
	pl := &PermissionListener{subs: make(map[permissionSub]func()), log: log}
	go pl.listen(ctx, pool)
	return pl
}

func (pl *PermissionListener) listen(ctx context.Context, pool *pgxpool.Pool) {
	for {
		if err := pl.listenOnce(ctx, pool); err != nil {
			if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
				return
			}
			pl.log.Error("permission listener: disconnected, retrying in 5s", "error", err)
			time.Sleep(5 * time.Second)
		}
	}
}

func (pl *PermissionListener) listenOnce(ctx context.Context, pool *pgxpool.Pool) error {
	poolConn, err := pool.Acquire(ctx)
	if err != nil {
		return fmt.Errorf("acquire: %w", err)
	}
	conn := poolConn.Hijack()
	done := make(chan struct{})
	defer close(done)
	go func() {
		select {
		case <-ctx.Done():
			conn.Close(context.Background())
		case <-done:
		}
	}()
	defer conn.Close(context.Background())
	if _, err := conn.Exec(ctx, "LISTEN permission_revoked"); err != nil {
		return fmt.Errorf("listen: %w", err)
	}
	pl.log.Info("permission listener: started")
	for {
		notification, err := conn.WaitForNotification(ctx)
		if err != nil {
			return fmt.Errorf("wait: %w", err)
		}
		var ev permissionEvent
		if err := json.Unmarshal([]byte(notification.Payload), &ev); err != nil {
			pl.log.Warn("permission listener: bad payload", "payload", notification.Payload)
			continue
		}
		pl.mu.RLock()
		for sub, closeFn := range pl.subs {
			if sub.noteID == ev.NoteID && sub.userID == ev.UserID {
				closeFn()
			}
		}
		pl.mu.RUnlock()
	}
}

func (pl *PermissionListener) Register(noteID, userID string, closeFn func()) func() {
	pl.mu.Lock()
	pl.nextID++
	sub := permissionSub{noteID: noteID, userID: userID, connID: fmt.Sprintf("%s_%d", userID, pl.nextID)}
	pl.subs[sub] = closeFn
	pl.mu.Unlock()
	return func() {
		pl.mu.Lock()
		delete(pl.subs, sub)
		pl.mu.Unlock()
	}
}

type tokenBucket struct {
	mu           sync.Mutex
	tokens       float64
	max          float64
	refillPerSec float64
	lastRefill   time.Time
}

func newTokenBucket(max, refillPerSec int) *tokenBucket {
	return &tokenBucket{tokens: float64(max), max: float64(max), refillPerSec: float64(refillPerSec), lastRefill: time.Now()}
}

func (tb *tokenBucket) Allow() bool {
	tb.mu.Lock()
	defer tb.mu.Unlock()
	now := time.Now()
	elapsed := now.Sub(tb.lastRefill).Seconds()
	tb.tokens = min(tb.max, tb.tokens+elapsed*tb.refillPerSec)
	tb.lastRefill = now
	if tb.tokens >= 1 {
		tb.tokens--
		return true
	}
	return false
}

type WSHandler struct {
	roomMgr     *RoomManager
	pool        *pgxpool.Pool
	upgrader    websocket.Upgrader
	machineID   string
	perm        *PermissionListener
	log         *slog.Logger
	shutdownCtx context.Context
}

func NewWSHandler(shutdownCtx context.Context, roomMgr *RoomManager, pool *pgxpool.Pool, machineID string) *WSHandler {
	log := slog.With("component", "ws_handler")
	return &WSHandler{
		roomMgr:     roomMgr,
		pool:        pool,
		machineID:   machineID,
		shutdownCtx: shutdownCtx,
		perm:        NewPermissionListener(shutdownCtx, pool, log),
		log:         log,
		upgrader: websocket.Upgrader{
			CheckOrigin:     func(r *http.Request) bool { return true },
			ReadBufferSize:  1024,
			WriteBufferSize: 1024,
		},
	}
}

func (h *WSHandler) HandleConnect(c echo.Context) error {
	startTotal := time.Now()
	noteID := c.Param("note_id")
	userIDStr, ok := web.UserIDFromContext(c)
	if !ok {
		return web.JSONError(c, http.StatusUnauthorized, "unauthorized")
	}
	userID, err := uid.UUIDFromString(userIDStr)
	if err != nil {
		return web.JSONError(c, http.StatusBadRequest, "invalid user id")
	}

	slog.Info("WS HandleConnect: starting", "note_id", noteID, "user_id", userIDStr)
	ctx := c.Request().Context()

	startPerm := time.Now()
	var hasAccess bool
	err = h.pool.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM notes WHERE id = $1 AND user_id = $2
			UNION ALL
			SELECT 1 FROM note_shares WHERE note_id = $1 AND user_id = $2
		)
	`, noteID, userID).Scan(&hasAccess)
	if err != nil {
		slog.Error("WS HandleConnect: permission check failed", "note_id", noteID, "error", err, "elapsed_ms", time.Since(startPerm).Milliseconds())
		return web.JSONError(c, http.StatusInternalServerError, "permission check failed")
	}
	if !hasAccess {
		slog.Error("WS HandleConnect: access denied", "note_id", noteID, "user_id", userIDStr, "elapsed_ms", time.Since(startPerm).Milliseconds())
		return web.JSONError(c, http.StatusForbidden, "access denied")
	}
	slog.Info("WS HandleConnect: permission OK", "note_id", noteID, "elapsed_ms", time.Since(startPerm).Milliseconds())

	// Pre-upgrade fly-replay redirect: read lease without acquiring.
	startLease := time.Now()
	var leaseMachine string
	err = h.pool.QueryRow(ctx, "SELECT machine_id FROM note_ws_leases WHERE note_id = $1 AND expires_at > NOW()", noteID).Scan(&leaseMachine)
	if err == nil && leaseMachine != "" && leaseMachine != h.machineID {
		slog.Info("WS HandleConnect: fly-replay redirect", "note_id", noteID, "target_machine", leaseMachine, "elapsed_ms", time.Since(startLease).Milliseconds())
		c.Response().Header().Set("fly-replay", "instance="+leaseMachine)
		return c.NoContent(http.StatusServiceUnavailable)
	}
	slog.Info("WS HandleConnect: lease check done", "note_id", noteID, "elapsed_ms", time.Since(startLease).Milliseconds())

	startUpgrade := time.Now()
	conn, err := h.upgrader.Upgrade(c.Response(), c.Request(), nil)
	if err != nil {
		slog.Error("WS HandleConnect: upgrade failed", "note_id", noteID, "error", err, "elapsed_ms", time.Since(startUpgrade).Milliseconds())
		return fmt.Errorf("websocket upgrade: %w", err)
	}
	slog.Info("WS HandleConnect: upgraded", "note_id", noteID, "elapsed_ms", time.Since(startUpgrade).Milliseconds())
	wsC := &wsConn{conn: conn}

	startRoom := time.Now()
	room, err := h.roomMgr.GetOrCreateRoom(ctx, noteID, h.machineID)
	if err != nil {
		slog.Error("WS HandleConnect: GetOrCreateRoom failed", "note_id", noteID, "error", err, "elapsed_ms", time.Since(startRoom).Milliseconds())
		conn.Close()
		return fmt.Errorf("get or create room: %w", err)
	}
	slog.Info("WS HandleConnect: room ready", "note_id", noteID, "elapsed_ms", time.Since(startRoom).Milliseconds())

	startHandshake := time.Now()
	if err := room.HandleHandshake(wsC); err != nil {
		slog.Error("WS HandleConnect: handshake failed", "note_id", noteID, "error", err, "elapsed_ms", time.Since(startHandshake).Milliseconds())
		conn.Close()
		room.RemoveClient(wsC)
		return fmt.Errorf("handshake: %w", err)
	}
	slog.Info("WS HandleConnect: handshake done", "note_id", noteID, "elapsed_ms", time.Since(startHandshake).Milliseconds())
	room.AddClient(wsC)

	canEdit := true
	err = h.pool.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM notes WHERE id = $1 AND user_id = $2
			UNION ALL
			SELECT 1 FROM note_shares WHERE note_id = $1 AND user_id = $2 AND permission = 'edit'
		)
	`, noteID, userID).Scan(&canEdit)
	if err != nil {
		canEdit = false
	}

	slog.Info("WS HandleConnect: connected", "note_id", noteID, "can_edit", canEdit, "total_ms", time.Since(startTotal).Milliseconds())

	var closeOnce sync.Once
	unregister := h.perm.Register(noteID, userIDStr, func() {
		h.log.Info("revoking WS connection due to permission change", "note_id", noteID, "user_id", userIDStr)
		closeOnce.Do(func() { conn.Close() })
	})

	rl := newTokenBucket(50, 50)
	for {
		_, msg, rerr := conn.ReadMessage()
		if rerr != nil {
			slog.Info("WS HandleConnect: connection closed", "note_id", noteID, "error", rerr)
			break
		}
		if !rl.Allow() {
			continue
		}
		if !canEdit {
			continue
		}
		room.HandleIncomingUpdate(msg, wsC)
	}
	unregister()
	room.RemoveClient(wsC)
	slog.Info("WS HandleConnect: disconnected", "note_id", noteID)
	return nil
}
