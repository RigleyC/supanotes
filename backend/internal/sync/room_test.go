package sync

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"

	"github.com/gorilla/websocket"
	"github.com/reearth/ygo/crdt"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type mockLeaseManager struct {
	mu         sync.Mutex
	leases     map[string]string
	acquireErr error
}

func newMockLeaseManager() *mockLeaseManager {
	return &mockLeaseManager{leases: make(map[string]string)}
}

func (m *mockLeaseManager) AcquireLease(_ context.Context, noteID, machineID string) (bool, error) {
	if m.acquireErr != nil {
		return false, m.acquireErr
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	if _, ok := m.leases[noteID]; ok {
		return false, nil
	}
	m.leases[noteID] = machineID
	return true, nil
}

func (m *mockLeaseManager) ReleaseLease(_ context.Context, noteID, _ string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.leases, noteID)
	return nil
}

func (m *mockLeaseManager) RenewLease(_ context.Context, _, _ string) error {
	return nil
}

func (m *mockLeaseManager) GetLeaseMachine(_ context.Context, noteID string) (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	machine, ok := m.leases[noteID]
	if !ok {
		return "", assert.AnError
	}
	return machine, nil
}

func newTestWSConn(t *testing.T) *websocket.Conn {
	t.Helper()

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		upgrader := websocket.Upgrader{}
		conn, err := upgrader.Upgrade(w, r, nil)
		require.NoError(t, err)

		go func() {
			for {
				if _, _, err := conn.ReadMessage(); err != nil {
					return
				}
			}
		}()

		select {}
	}))
	t.Cleanup(server.Close)

	url := "ws" + strings.TrimPrefix(server.URL, "http")
	conn, _, err := websocket.DefaultDialer.Dial(url, nil)
	require.NoError(t, err)
	t.Cleanup(func() { conn.Close() })
	return conn
}

func newTestWSPair(t *testing.T) (*websocket.Conn, *websocket.Conn) {
	t.Helper()

	recipientCh := make(chan []byte, 1)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		upgrader := websocket.Upgrader{}
		conn, err := upgrader.Upgrade(w, r, nil)
		require.NoError(t, err)

		go func() {
			for {
				_, msg, err := conn.ReadMessage()
				if err != nil {
					return
				}
				select {
				case recipientCh <- msg:
				default:
				}
			}
		}()

		select {}
	}))
	t.Cleanup(server.Close)

	url := "ws" + strings.TrimPrefix(server.URL, "http")
	sender, _, err := websocket.DefaultDialer.Dial(url, nil)
	require.NoError(t, err)
	t.Cleanup(func() { sender.Close() })

	recipientConn2, _, err := websocket.DefaultDialer.Dial(url, nil)
	require.NoError(t, err)
	t.Cleanup(func() { recipientConn2.Close() })

	return sender, recipientConn2
}

func makeTestUpdate(t *testing.T) []byte {
	t.Helper()
	doc := crdt.New(crdt.WithGC(false))
	text := doc.GetText("content")
	doc.Transact(func(txn *crdt.Transaction) {
		text.Insert(txn, 0, "test", nil)
	})
	return crdt.EncodeStateAsUpdateV1(doc, nil)
}

func TestRoomManagerGetOrCreateRoom(t *testing.T) {
	mgr := NewRoomManager(
		newMockLeaseManager(),
		NewYDocService(nil, nil),
		nil,
	)

	room1, err := mgr.GetOrCreateRoom(context.Background(), "note-1", "machine-a")
	require.NoError(t, err)
	require.NotNil(t, room1)

	room2, err := mgr.GetOrCreateRoom(context.Background(), "note-1", "machine-a")
	require.NoError(t, err)
	require.NotNil(t, room2)

	assert.Same(t, room1, room2, "GetOrCreateRoom should return the same room for the same noteID")
}

func TestRoomManagerGetOrCreateRoomDifferentNotes(t *testing.T) {
	mgr := NewRoomManager(
		newMockLeaseManager(),
		NewYDocService(nil, nil),
		nil,
	)

	room1, err := mgr.GetOrCreateRoom(context.Background(), "note-1", "machine-a")
	require.NoError(t, err)

	room2, err := mgr.GetOrCreateRoom(context.Background(), "note-2", "machine-a")
	require.NoError(t, err)

	assert.NotSame(t, room1, room2, "different noteIDs should get different rooms")
}

func TestRoomAddRemoveClient(t *testing.T) {
	room := &Room{
		NoteID:    "note-1",
		Doc:       crdt.New(crdt.WithGC(false)),
		clients:   make(map[*websocket.Conn]bool),
		stopHeart: make(chan struct{}),
		leaseMgr:  newMockLeaseManager(),
		manager:   NewRoomManager(newMockLeaseManager(), NewYDocService(nil, nil), nil),
		ydocSvc:   NewYDocService(nil, nil),
	}

	conn1 := newTestWSConn(t)
	conn2 := newTestWSConn(t)

	room.AddClient(conn1)
	room.mu.Lock()
	assert.Equal(t, 1, len(room.clients), "should have 1 client after first AddClient")
	assert.True(t, room.clients[conn1], "conn1 should be in clients")
	room.mu.Unlock()

	room.AddClient(conn2)
	room.mu.Lock()
	assert.Equal(t, 2, len(room.clients), "should have 2 clients after second AddClient")
	assert.True(t, room.clients[conn2], "conn2 should be in clients")
	room.mu.Unlock()

	room.RemoveClient(conn1)
	room.mu.Lock()
	assert.Equal(t, 1, len(room.clients), "should have 1 client after removing conn1")
	_, ok := room.clients[conn1]
	assert.False(t, ok, "conn1 should be removed")
	room.mu.Unlock()

	room.RemoveClient(conn2)
	room.mu.Lock()
	assert.Equal(t, 0, len(room.clients), "should have 0 clients after removing conn2")
	room.mu.Unlock()
}

func TestRoomRemoveClientLastReleasesLease(t *testing.T) {
	leaseMgr := newMockLeaseManager()
	rm := NewRoomManager(leaseMgr, NewYDocService(nil, nil), nil)

	room, err := rm.GetOrCreateRoom(context.Background(), "note-lease", "machine-a")
	require.NoError(t, err)
	// Replace the room's leaseMgr with our mock, but the room already has the real one from GetOrCreateRoom
	// The lease was acquired in GetOrCreateRoom via the mock, so it's fine

	machine, err := leaseMgr.GetLeaseMachine(context.Background(), "note-lease")
	require.NoError(t, err)
	assert.Equal(t, "machine-a", machine)

	conn1 := newTestWSConn(t)
	conn2 := newTestWSConn(t)
	room.AddClient(conn1)
	room.AddClient(conn2)

	room.RemoveClient(conn1)
	// Lease should still be held (one client remains)
	machine, err = leaseMgr.GetLeaseMachine(context.Background(), "note-lease")
	require.NoError(t, err)
	assert.Equal(t, "machine-a", machine)

	room.RemoveClient(conn2)
	// Lease should be released (no clients remain)
	_, err = leaseMgr.GetLeaseMachine(context.Background(), "note-lease")
	assert.Error(t, err, "lease should be released after last client disconnects")
}

func TestRoomHandleIncomingUpdateBroadcasts(t *testing.T) {
	recipientCh := make(chan []byte, 4)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		upgrader := websocket.Upgrader{}
		conn, err := upgrader.Upgrade(w, r, nil)
		require.NoError(t, err)

		go func() {
			for {
				_, msg, err := conn.ReadMessage()
				if err != nil {
					return
				}
				select {
				case recipientCh <- msg:
				default:
				}
			}
		}()

		select {}
	}))
	t.Cleanup(server.Close)

	url := "ws" + strings.TrimPrefix(server.URL, "http")
	sender, _, err := websocket.DefaultDialer.Dial(url, nil)
	require.NoError(t, err)
	t.Cleanup(func() { sender.Close() })

	recipient, _, err := websocket.DefaultDialer.Dial(url, nil)
	require.NoError(t, err)
	t.Cleanup(func() { recipient.Close() })

	room := &Room{
		NoteID:    "note-broadcast",
		Doc:       crdt.New(crdt.WithGC(false)),
		clients:   make(map[*websocket.Conn]bool),
		stopHeart: make(chan struct{}),
		leaseMgr:  newMockLeaseManager(),
		ydocSvc:   NewYDocService(nil, nil),
	}

	room.AddClient(sender)
	room.AddClient(recipient)

	update := makeTestUpdate(t)
	require.NotEmpty(t, update)

	room.HandleIncomingUpdate(update, sender)

	select {
	case msg := <-recipientCh:
		assert.GreaterOrEqual(t, len(msg), 1, "message should have type byte prefix")
		assert.Equal(t, byte(0), msg[0], "broadcast message should start with type byte 0")
		assert.Equal(t, update, msg[1:], "broadcast message body should match the update")
	default:
		t.Fatal("expected recipient to receive a broadcast message")
	}
}

func TestRoomHandleIncomingUpdateSkipsSender(t *testing.T) {
	senderCh := make(chan []byte, 4)
	recipientCh := make(chan []byte, 4)

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		upgrader := websocket.Upgrader{}
		conn, err := upgrader.Upgrade(w, r, nil)
		require.NoError(t, err)

		connID := r.Header.Get("X-Conn-Id")
		go func() {
			for {
				_, msg, err := conn.ReadMessage()
				if err != nil {
					return
				}
				ch := recipientCh
				if connID == "sender" {
					ch = senderCh
				}
				select {
				case ch <- msg:
				default:
				}
			}
		}()

		select {}
	}))
	t.Cleanup(server.Close)

	url := "ws" + strings.TrimPrefix(server.URL, "http")

	hdr := http.Header{}
	hdr.Set("X-Conn-Id", "sender")
	sender, _, err := websocket.DefaultDialer.Dial(url, hdr)
	require.NoError(t, err)
	t.Cleanup(func() { sender.Close() })

	recipient, _, err := websocket.DefaultDialer.Dial(url, nil)
	require.NoError(t, err)
	t.Cleanup(func() { recipient.Close() })

	room := &Room{
		NoteID:    "note-skip-sender",
		Doc:       crdt.New(crdt.WithGC(false)),
		clients:   make(map[*websocket.Conn]bool),
		stopHeart: make(chan struct{}),
		leaseMgr:  newMockLeaseManager(),
		ydocSvc:   NewYDocService(nil, nil),
	}

	room.AddClient(sender)
	room.AddClient(recipient)
	room.AddClient(sender)

	update := makeTestUpdate(t)

	room.HandleIncomingUpdate(update, sender)

	select {
	case <-senderCh:
		t.Fatal("sender should NOT receive its own update")
	default:
	}

	select {
	case <-recipientCh:
		// expected — recipient got the broadcast
	default:
		t.Fatal("expected recipient to receive a broadcast message")
	}
}

func TestRoomHandleHandshake(t *testing.T) {
	serverCh := make(chan []byte, 4)

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		upgrader := websocket.Upgrader{}
		conn, err := upgrader.Upgrade(w, r, nil)
		require.NoError(t, err)

		// Read the SV from the room
		_, raw, err := conn.ReadMessage()
		if err != nil {
			return
		}
		select {
		case serverCh <- raw:
		default:
		}

		// Send back the room's own encoded SV as the "client SV"
		roomDoc := crdt.New(crdt.WithGC(false))
		clientSV := crdt.EncodeStateVectorV1(roomDoc)
		_ = conn.WriteMessage(websocket.BinaryMessage, append([]byte{0}, clientSV...))

		// Read the diff response
		_, diffRaw, err := conn.ReadMessage()
		if err != nil {
			return
		}
		select {
		case serverCh <- diffRaw:
		default:
		}

		select {}
	}))
	t.Cleanup(server.Close)

	url := "ws" + strings.TrimPrefix(server.URL, "http")
	conn, _, err := websocket.DefaultDialer.Dial(url, nil)
	require.NoError(t, err)
	t.Cleanup(func() { conn.Close() })

	room := &Room{
		NoteID:    "note-handshake",
		Doc:       crdt.New(crdt.WithGC(false)),
		clients:   make(map[*websocket.Conn]bool),
		stopHeart: make(chan struct{}),
		ydocSvc:   NewYDocService(nil, nil),
	}

	err = room.HandleHandshake(conn)
	require.NoError(t, err)

	svMsg := <-serverCh
	assert.GreaterOrEqual(t, len(svMsg), 1)
	assert.Equal(t, byte(0), svMsg[0], "SV message should start with type byte 0")

	diffMsg := <-serverCh
	assert.GreaterOrEqual(t, len(diffMsg), 1)
	assert.Equal(t, byte(0), diffMsg[0], "diff message should start with type byte 0")
}
