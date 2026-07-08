package sync

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"github.com/reearth/ygo/crdt"
)

type Room struct {
	NoteID    string
	Doc       *crdt.Doc
	clients   map[*websocket.Conn]bool
	mu        sync.Mutex
	leaseMgr  LeaseManager
	machineID string
	stopHeart chan struct{}
	ydocSvc   *YDocService
	manager   *RoomManager
}

type RoomManager struct {
	rooms         map[string]*Room
	mu            sync.Mutex
	leaseMgr      LeaseManager
	ydocSvc       *YDocService
	reconstructFn func(ctx context.Context, noteID string) ([]byte, error)
}

func NewRoomManager(leaseMgr LeaseManager, ydocSvc *YDocService, reconstructFn func(ctx context.Context, noteID string) ([]byte, error)) *RoomManager {
	return &RoomManager{
		rooms:         make(map[string]*Room),
		leaseMgr:      leaseMgr,
		ydocSvc:       ydocSvc,
		reconstructFn: reconstructFn,
	}
}

func (m *RoomManager) GetOrCreateRoom(ctx context.Context, noteID string, machineID string) (*Room, error) {
	m.mu.Lock()
	if room, ok := m.rooms[noteID]; ok {
		m.mu.Unlock()
		return room, nil
	}
	m.mu.Unlock()

	doc := crdt.New(crdt.WithGC(false))

	room := &Room{
		NoteID:    noteID,
		Doc:       doc,
		clients:   make(map[*websocket.Conn]bool),
		leaseMgr:  m.leaseMgr,
		machineID: machineID,
		stopHeart: make(chan struct{}),
		ydocSvc:   m.ydocSvc,
		manager:   m,
	}

	if _, err := m.leaseMgr.AcquireLease(ctx, noteID, machineID); err != nil {
		return nil, err
	}

	stateBytes, err := m.reconstructFn(ctx, noteID)
	if err != nil {
		return nil, err
	}
	if len(stateBytes) > 0 {
		if err := crdt.ApplyUpdateV1(doc, stateBytes, nil); err != nil {
			return nil, err
		}
	}

	m.mu.Lock()
	m.rooms[noteID] = room
	m.mu.Unlock()

	return room, nil
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

func (r *Room) AddClient(conn *websocket.Conn) {
	r.mu.Lock()
	r.clients[conn] = true
	first := len(r.clients) == 1
	r.mu.Unlock()

	if first {
		go r.startHeartbeat(context.Background())
	}
}

func (r *Room) RemoveClient(conn *websocket.Conn) {
	r.mu.Lock()
	delete(r.clients, conn)
	count := len(r.clients)
	r.mu.Unlock()

	if count > 0 {
		return
	}

	ctx := context.Background()
	_ = r.leaseMgr.ReleaseLease(ctx, r.NoteID, r.machineID)
	if r.manager != nil {
		r.manager.RemoveRoom(r.NoteID)
	}
}

func (r *Room) HandleIncomingUpdate(update []byte, senderConn *websocket.Conn) {
	r.mu.Lock()
	if err := crdt.ApplyUpdateV1(r.Doc, update, nil); err != nil {
		r.mu.Unlock()
		return
	}

	recipients := make([]*websocket.Conn, 0, len(r.clients))
	for conn := range r.clients {
		if conn != senderConn {
			recipients = append(recipients, conn)
		}
	}
	r.mu.Unlock()

	msg := append([]byte{0}, update...)
	for _, conn := range recipients {
		_ = conn.WriteMessage(websocket.BinaryMessage, msg)
	}

	_ = r.ydocSvc.ApplyNodeMutation(context.Background(), r.NoteID, update)
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

func (r *Room) HandleHandshake(conn *websocket.Conn) error {
	sv := crdt.EncodeStateVectorV1(r.Doc)
	if err := conn.WriteMessage(websocket.BinaryMessage, append([]byte{0}, sv...)); err != nil {
		return err
	}

	_, raw, err := conn.ReadMessage()
	if err != nil {
		return err
	}
	if len(raw) < 1 || raw[0] != 0 {
		return fmt.Errorf("unexpected message type: %d", raw[0])
	}

	clientSV, err := crdt.DecodeStateVectorV1(raw[1:])
	if err != nil {
		return err
	}
	diff := crdt.EncodeStateAsUpdateV1(r.Doc, clientSV)
	return conn.WriteMessage(websocket.BinaryMessage, append([]byte{0}, diff...))
}
