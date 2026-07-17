package sync

import (
	"context"
	"fmt"
	"log/slog"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/reearth/ygo/crdt"
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

func (w *wsConn) ReadMessage() (int, []byte, error) {
	return w.conn.ReadMessage()
}

func (w *wsConn) writeBinary(data []byte) error {
	w.wmu.Lock()
	defer w.wmu.Unlock()
	_ = w.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
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
	startTotal := time.Now()
	m.mu.Lock()
	if r, ok := m.rooms[noteID]; ok {
		m.mu.Unlock()
		slog.Info("GetOrCreateRoom: cache hit", "note_id", noteID, "elapsed_ms", time.Since(startTotal).Milliseconds())
		return r, nil
	}
	m.mu.Unlock()

	result, err, _ := m.sg.Do(noteID, func() (interface{}, error) {

		startLease := time.Now()
		m.mu.Lock()
		if r, ok := m.rooms[noteID]; ok {
			m.mu.Unlock()
			return r, nil
		}
		m.mu.Unlock()

		// Acquire lease BEFORE loading doc (rollback if lease fails)
		_, acquired, err := m.leaseMgr.AcquireLease(ctx, noteID, machineID)
		if err != nil {
			slog.Error("GetOrCreateRoom: AcquireLease failed", "note_id", noteID, "error", err, "elapsed_ms", time.Since(startLease).Milliseconds())
			return nil, err
		}
		if !acquired {
			slog.Error("GetOrCreateRoom: lease not acquired", "note_id", noteID, "elapsed_ms", time.Since(startLease).Milliseconds())
			return nil, fmt.Errorf("lease already held for note %s", noteID)
		}
		slog.Info("GetOrCreateRoom: lease acquired", "note_id", noteID, "elapsed_ms", time.Since(startLease).Milliseconds())

		// Pre-load canonical doc into YDocService cache
		startDoc := time.Now()
		_, err = m.ydocSvc.DocFor(ctx, noteID)
		if err != nil {
			_ = m.leaseMgr.ReleaseLease(ctx, noteID, machineID)
			slog.Error("GetOrCreateRoom: DocFor failed", "note_id", noteID, "error", err, "elapsed_ms", time.Since(startDoc).Milliseconds())
			return nil, fmt.Errorf("load canonical doc: %w", err)
		}
		slog.Info("GetOrCreateRoom: doc loaded", "note_id", noteID, "elapsed_ms", time.Since(startDoc).Milliseconds())

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
		slog.Info("GetOrCreateRoom: room created", "note_id", noteID, "total_ms", time.Since(startTotal).Milliseconds())
		return r, nil
	})
	if err != nil {
		return nil, err
	}
	return result.(*Room), nil
}

func (m *RoomManager) HasActiveRoom(noteID string) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	room, ok := m.rooms[noteID]
	if !ok {
		return false
	}
	room.mu.Lock()
	hasClients := len(room.clients) > 0
	room.mu.Unlock()
	return hasClients
}

func (m *RoomManager) BroadcastIfActive(noteID string, update []byte) bool {
	startTotal := time.Now()
	m.mu.Lock()
	room, ok := m.rooms[noteID]
	m.mu.Unlock()
	if !ok {
		slog.Debug("BroadcastIfActive: no active room", "note_id", noteID)
		return false
	}
	framed := ygsync.EncodeUpdate(update)
	room.mu.Lock()
	clients := make([]*wsConn, 0, len(room.clients))
	for c := range room.clients {
		clients = append(clients, c)
	}
	room.mu.Unlock()
	slog.Info("BroadcastIfActive: broadcasting", "note_id", noteID, "clients", len(clients), "update_bytes", len(update))
	for _, c := range clients {
		if err := c.writeBinary(framed); err != nil {
			slog.Error("BroadcastIfActive: write failed", "note_id", noteID, "error", err)
		}
	}
	slog.Debug("BroadcastIfActive: done", "note_id", noteID, "elapsed_ms", time.Since(startTotal).Milliseconds())
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
	startTotal := time.Now()
	msgType, payload, err := ygsync.ReadSyncMessage(framedMsg)
	if err != nil {
		slog.Error("HandleIncomingUpdate: ReadSyncMessage failed", "note_id", r.NoteID, "error", err)
		return
	}
	slog.Debug("HandleIncomingUpdate: message read", "note_id", r.NoteID, "msg_type", msgType, "payload_bytes", len(payload))

	var step2Reply []byte
	err = r.ydocSvc.WithDoc(context.Background(), r.NoteID, func(doc *crdt.Doc) error {
		switch msgType {
		case ygsync.MsgSyncStep1:
			startStep2 := time.Now()
			reply, err := ygsync.EncodeSyncStep2(doc, framedMsg)
			if err != nil {
				slog.Error("HandleIncomingUpdate: EncodeSyncStep2 failed", "note_id", r.NoteID, "error", err)
				return err
			}
			step2Reply = reply
			slog.Info("HandleIncomingUpdate: SyncStep2 reply generated", "note_id", r.NoteID, "elapsed_ms", time.Since(startStep2).Milliseconds())
			return nil
		case ygsync.MsgSyncStep2, ygsync.MsgUpdate:
		default:
			return nil
		}

		startApply := time.Now()
		_, err = ygsync.ApplySyncMessage(doc, framedMsg, "remote")
		applyElapsed := time.Since(startApply)
		if err != nil {
			slog.Error("HandleIncomingUpdate: ApplySyncMessage failed", "note_id", r.NoteID, "error", err, "elapsed_ms", applyElapsed.Milliseconds())
			return err
		}
		slog.Debug("HandleIncomingUpdate: ApplySyncMessage done", "note_id", r.NoteID, "elapsed_ms", applyElapsed.Milliseconds())

		startMutation := time.Now()
		_ = r.ydocSvc.ApplyNodeMutationLocked(context.Background(), doc, r.NoteID, payload)
		slog.Debug("HandleIncomingUpdate: ApplyNodeMutationLocked done", "note_id", r.NoteID, "elapsed_ms", time.Since(startMutation).Milliseconds())
		return nil
	})
	if err != nil {
		slog.Error("HandleIncomingUpdate: WithDoc failed", "note_id", r.NoteID, "error", err, "total_elapsed_ms", time.Since(startTotal).Milliseconds())
		return
	}

	if step2Reply != nil {
		_ = sender.writeBinary(step2Reply)
		return
	}

	startBroadcast := time.Now()
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
	slog.Debug("HandleIncomingUpdate: broadcast done", "note_id", r.NoteID, "recipients", len(recipients), "broadcast_ms", time.Since(startBroadcast).Milliseconds(), "total_ms", time.Since(startTotal).Milliseconds())
}

func (r *Room) HandleHandshake(c *wsConn) error {
	startTotal := time.Now()
	slog.Info("HandleHandshake: starting", "note_id", r.NoteID)

	// Step 1: server sends its sync step 1
	startStep1 := time.Now()
	var step1Server []byte
	err := r.ydocSvc.WithDoc(context.Background(), r.NoteID, func(doc *crdt.Doc) error {
		step1Server = ygsync.EncodeSyncStep1(doc)
		return nil
	})
	if err != nil {
		slog.Error("HandleHandshake: WithDoc Step1 failed", "note_id", r.NoteID, "error", err, "elapsed_ms", time.Since(startStep1).Milliseconds())
		return err
	}
	slog.Info("HandleHandshake: Step1 encoded", "note_id", r.NoteID, "bytes", len(step1Server), "elapsed_ms", time.Since(startStep1).Milliseconds())

	if err := c.writeBinary(step1Server); err != nil {
		slog.Error("HandleHandshake: write Step1 failed", "note_id", r.NoteID, "error", err)
		return err
	}

	// Read client Step1
	startRead := time.Now()
	_, raw, err := c.ReadMessage()
	if err != nil {
		slog.Error("HandleHandshake: read client Step1 failed", "note_id", r.NoteID, "error", err, "elapsed_ms", time.Since(startRead).Milliseconds())
		return err
	}
	slog.Info("HandleHandshake: client Step1 received", "note_id", r.NoteID, "bytes", len(raw), "elapsed_ms", time.Since(startRead).Milliseconds())

	mt, _, err := ygsync.ReadSyncMessage(raw)
	if err != nil {
		slog.Error("HandleHandshake: ReadSyncMessage failed", "note_id", r.NoteID, "error", err)
		return err
	}
	if mt != ygsync.MsgSyncStep1 {
		slog.Error("HandleHandshake: unexpected msg type", "note_id", r.NoteID, "got", mt, "expected", ygsync.MsgSyncStep1)
		return fmt.Errorf("expected SyncStep1 from client, got type %d", mt)
	}

	// Reply with Step2 diff
	startStep2 := time.Now()
	var step2 []byte
	err = r.ydocSvc.WithDoc(context.Background(), r.NoteID, func(doc *crdt.Doc) error {
		var err error
		step2, err = ygsync.EncodeSyncStep2(doc, raw)
		return err
	})
	if err != nil {
		slog.Error("HandleHandshake: WithDoc Step2 failed", "note_id", r.NoteID, "error", err, "elapsed_ms", time.Since(startStep2).Milliseconds())
		return err
	}
	slog.Info("HandleHandshake: Step2 encoded", "note_id", r.NoteID, "bytes", len(step2), "elapsed_ms", time.Since(startStep2).Milliseconds())

	if err := c.writeBinary(step2); err != nil {
		slog.Error("HandleHandshake: write Step2 failed", "note_id", r.NoteID, "error", err)
		return err
	}
	slog.Info("HandleHandshake: done", "note_id", r.NoteID, "total_ms", time.Since(startTotal).Milliseconds())
	return nil
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
