package sync

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"github.com/jackc/pgx/v5/pgxpool"
	ygsync "github.com/reearth/ygo/sync"
	"golang.org/x/sync/singleflight"
)

type Room struct {
	NoteID    string
	ydocSvc   *YDocService
	clients   map[*wsConn]struct{}
	leaseMgr  LeaseManager
	machineID string
	stopHeart chan struct{}
	manager   *RoomManager
	mu        sync.Mutex
}

type wsConn struct {
	conn *websocket.Conn
	wmu  sync.Mutex
}

func (w *wsConn) writeBinary(data []byte) error {
	w.wmu.Lock()
	defer w.wmu.Unlock()
	return w.conn.WriteMessage(websocket.BinaryMessage, data)
}

type RoomManager struct {
	rooms    map[string]*Room
	mu       sync.Mutex
	leaseMgr LeaseManager
	ydocSvc  *YDocService
	pool     *pgxpool.Pool
	sg       singleflight.Group
}

func NewRoomManager(leaseMgr LeaseManager, ydocSvc *YDocService, pool *pgxpool.Pool) *RoomManager {
	return &RoomManager{
		rooms:    make(map[string]*Room),
		leaseMgr: leaseMgr,
		ydocSvc:  ydocSvc,
		pool:     pool,
	}
}

func (m *RoomManager) GetOrCreateRoom(ctx context.Context, noteID string, machineID string) (*Room, error) {
	m.mu.Lock()
	if r, ok := m.rooms[noteID]; ok {
		m.mu.Unlock()
		return r, nil
	}
	m.mu.Unlock()

	result, err, _ := m.sg.Do(noteID, func() (interface{}, error) {
		m.mu.Lock()
		if r, ok := m.rooms[noteID]; ok {
			m.mu.Unlock()
			return r, nil
		}
		m.mu.Unlock()

		// Acquire lease BEFORE loading doc (rollback if lease fails)
		acquired, err := m.leaseMgr.AcquireLease(ctx, noteID, machineID)
		if err != nil {
			return nil, err
		}
		if !acquired {
			return nil, fmt.Errorf("lease already held for note %s", noteID)
		}

		// Pre-load canonical doc into YDocService cache
		_, err = m.ydocSvc.DocFor(ctx, noteID)
		if err != nil {
			_ = m.leaseMgr.ReleaseLease(ctx, noteID, machineID)
			return nil, fmt.Errorf("load canonical doc: %w", err)
		}

		r := &Room{
			NoteID:    noteID,
			ydocSvc:   m.ydocSvc,
			clients:   make(map[*wsConn]struct{}),
			leaseMgr:  m.leaseMgr,
			machineID: machineID,
			stopHeart: make(chan struct{}),
			manager:   m,
		}

		m.mu.Lock()
		m.rooms[noteID] = r
		m.mu.Unlock()
		return r, nil
	})
	if err != nil {
		return nil, err
	}
	return result.(*Room), nil
}

func (m *RoomManager) BroadcastIfActive(noteID string, update []byte) bool {
	m.mu.Lock()
	room, ok := m.rooms[noteID]
	m.mu.Unlock()
	if !ok {
		return false
	}
	// Ensure YDoc cache warm (room was active)
	if _, err := m.ydocSvc.DocFor(context.Background(), noteID); err != nil {
		return false
	}
	framed := ygsync.EncodeUpdate(update)
	room.mu.Lock()
	clients := make([]*wsConn, 0, len(room.clients))
	for c := range room.clients {
		clients = append(clients, c)
	}
	room.mu.Unlock()
	for _, c := range clients {
		_ = c.writeBinary(framed)
	}
	return true
}

func (m *RoomManager) RemoveRoom(noteID string) {
	m.mu.Lock()
	room, ok := m.rooms[noteID]
	if ok {
		close(room.stopHeart)
		delete(m.rooms, noteID)
	}
	m.mu.Unlock()
}

func (r *Room) AddClient(c *wsConn) {
	r.mu.Lock()
	r.clients[c] = struct{}{}
	needHeart := len(r.clients) == 1
	r.mu.Unlock()
	if needHeart {
		go r.startHeartbeat(context.Background())
	}
}

func (r *Room) RemoveClient(c *wsConn) {
	r.mu.Lock()
	delete(r.clients, c)
	count := len(r.clients)
	r.mu.Unlock()
	if count > 0 {
		return
	}
	// Last client left — release lease and remove room.
	ctx := context.Background()
	_ = r.leaseMgr.ReleaseLease(ctx, r.NoteID, r.machineID)
	if r.manager != nil {
		r.manager.RemoveRoom(r.NoteID)
	}
}

func (r *Room) HandleIncomingUpdate(framedMsg []byte, sender *wsConn) {
	doc, err := r.ydocSvc.DocFor(context.Background(), r.NoteID)
	if err != nil {
		return
	}
	msgType, payload, err := ygsync.ReadSyncMessage(framedMsg)
	if err != nil {
		return
	}

	switch msgType {
	case ygsync.MsgSyncStep1:
		reply, err := ygsync.EncodeSyncStep2(doc, framedMsg)
		if err != nil {
			return
		}
		_ = sender.writeBinary(reply)
		return
	case ygsync.MsgSyncStep2, ygsync.MsgUpdate:
	default:
		return
	}

	_, err = ygsync.ApplySyncMessage(doc, framedMsg, "remote")
	if err != nil {
		return
	}

	// Forward the underlying payload (unwrapped) to other clients.
	_ = r.ydocSvc.ApplyNodeMutation(context.Background(), r.NoteID, payload)

	r.mu.Lock()
	recipients := make([]*wsConn, 0, len(r.clients))
	for c := range r.clients {
		if c != sender {
			recipients = append(recipients, c)
		}
	}
	r.mu.Unlock()

	framed := ygsync.EncodeUpdate(payload)
	for _, c := range recipients {
		_ = c.writeBinary(framed)
	}
}

func (r *Room) HandleHandshake(c *wsConn) error {
	doc, err := r.ydocSvc.DocFor(context.Background(), r.NoteID)
	if err != nil {
		return err
	}
	// Send server Step1
	step1Server := ygsync.EncodeSyncStep1(doc)
	if err := c.writeBinary(step1Server); err != nil {
		return err
	}
	// Read client Step1
	_, raw, err := c.conn.ReadMessage()
	if err != nil {
		return err
	}
	mt, _, err := ygsync.ReadSyncMessage(raw)
	if err != nil {
		return err
	}
	if mt != ygsync.MsgSyncStep1 {
		return fmt.Errorf("expected SyncStep1 from client, got type %d", mt)
	}
	// Reply with Step2 diff
	step2, err := ygsync.EncodeSyncStep2(doc, raw)
	if err != nil {
		return err
	}
	return c.writeBinary(step2)
}

func (r *Room) startHeartbeat(ctx context.Context) {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-r.stopHeart:
			return
		case <-ticker.C:
			_ = r.leaseMgr.RenewLease(ctx, r.NoteID, r.machineID)
		}
	}
}
