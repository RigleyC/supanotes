//go:build integration

package sync

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gorilla/websocket"
	"github.com/reearth/ygo/crdt"
	ygsync "github.com/reearth/ygo/sync"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)





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
		clients:   make(map[*wsConn]struct{}),
		stopHeart: make(chan struct{}),
		leaseMgr:  newMockLeaseManager(),
		manager:   NewRoomManager(newMockLeaseManager(), NewYDocService(nil, nil), nil),
		ydocSvc:   NewYDocService(nil, nil),
	}

	conn1 := newTestWSConn(t)
	conn2 := newTestWSConn(t)
	wsA := &wsConn{conn: conn1}
	wsB := &wsConn{conn: conn2}

	room.AddClient(wsA)
	room.mu.Lock()
	assert.Equal(t, 1, len(room.clients), "should have 1 client after first AddClient")
	_, ok := room.clients[wsA]
	assert.True(t, ok, "wsA should be in clients")
	room.mu.Unlock()

	room.AddClient(wsB)
	room.mu.Lock()
	assert.Equal(t, 2, len(room.clients), "should have 2 clients after second AddClient")
	_, ok = room.clients[wsB]
	assert.True(t, ok, "wsB should be in clients")
	room.mu.Unlock()

	room.RemoveClient(wsA)
	room.mu.Lock()
	assert.Equal(t, 1, len(room.clients), "should have 1 client after removing wsA")
	_, ok = room.clients[wsA]
	assert.False(t, ok, "wsA should be removed")
	room.mu.Unlock()

	room.RemoveClient(wsB)
	room.mu.Lock()
	assert.Equal(t, 0, len(room.clients), "should have 0 clients after removing wsB")
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
	wsA := &wsConn{conn: conn1}
	wsB := &wsConn{conn: conn2}
	room.AddClient(wsA)
	room.AddClient(wsB)

	room.RemoveClient(wsA)
	// Lease should still be held (one client remains)
	machine, err = leaseMgr.GetLeaseMachine(context.Background(), "note-lease")
	require.NoError(t, err)
	assert.Equal(t, "machine-a", machine)

	room.RemoveClient(wsB)
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
		clients:   make(map[*wsConn]struct{}),
		stopHeart: make(chan struct{}),
		leaseMgr:  newMockLeaseManager(),
		ydocSvc:   NewYDocService(nil, nil),
	}

	wsSender := &wsConn{conn: sender}
	wsRecipient := &wsConn{conn: recipient}
	room.AddClient(wsSender)
	room.AddClient(wsRecipient)

	update := makeTestUpdate(t)
	require.NotEmpty(t, update)

	framed := ygsync.EncodeUpdate(update)
	room.HandleIncomingUpdate(framed, wsSender)

	select {
	case msg := <-recipientCh:
		assert.GreaterOrEqual(t, len(msg), 1, "message should have type byte prefix")
		assert.Equal(t, byte(ygsync.MsgUpdate), msg[0], "broadcast should use Update framing")
	case <-time.After(200 * time.Millisecond):
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
		clients:   make(map[*wsConn]struct{}),
		stopHeart: make(chan struct{}),
		leaseMgr:  newMockLeaseManager(),
		ydocSvc:   NewYDocService(nil, nil),
	}

	wsSender := &wsConn{conn: sender}
	wsRecipient := &wsConn{conn: recipient}
	room.AddClient(wsSender)
	room.AddClient(wsRecipient)
	room.AddClient(wsSender)

	update := makeTestUpdate(t)

	framed := ygsync.EncodeUpdate(update)
	room.HandleIncomingUpdate(framed, wsSender)

	select {
	case <-senderCh:
		t.Fatal("sender should NOT receive its own update")
	case <-time.After(50 * time.Millisecond):
		// Expected - sender got nothing
	}

	select {
	case <-recipientCh:
		// expected — recipient got the broadcast
	case <-time.After(200 * time.Millisecond):
		t.Fatal("expected recipient to receive a broadcast message")
	}
}

func TestRoomHandleHandshake(t *testing.T) {
	serverCh := make(chan []byte, 4)

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		upgrader := websocket.Upgrader{}
		conn, err := upgrader.Upgrade(w, r, nil)
		require.NoError(t, err)

		// Read the Step1 from the room
		_, raw, err := conn.ReadMessage()
		if err != nil {
			return
		}
		select {
		case serverCh <- raw:
		default:
		}

		// Send back a Step1 message with an empty doc (as the "client")
		roomDoc := crdt.New(crdt.WithGC(false))
		clientStep1 := ygsync.EncodeSyncStep1(roomDoc)
		_ = conn.WriteMessage(websocket.BinaryMessage, clientStep1)

		// Read the Step2 response
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
		clients:   make(map[*wsConn]struct{}),
		stopHeart: make(chan struct{}),
		ydocSvc:   NewYDocService(nil, nil),
	}

	err = room.HandleHandshake(&wsConn{conn: conn})
	require.NoError(t, err)

	svMsg := <-serverCh
	assert.GreaterOrEqual(t, len(svMsg), 1)
	assert.Equal(t, byte(ygsync.MsgSyncStep1), svMsg[0], "first message should be SyncStep1")

	diffMsg := <-serverCh
	assert.GreaterOrEqual(t, len(diffMsg), 1)
	assert.Equal(t, byte(ygsync.MsgSyncStep2), diffMsg[0], "second message should be SyncStep2")
}
