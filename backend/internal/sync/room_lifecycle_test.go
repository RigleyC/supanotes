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

func TestRoomLifecycle_MultiClientBroadcast(t *testing.T) {
	// Tests 1 & 2: Two clients connect and receive updates from each other in <1s
	clientACh := make(chan []byte, 4)
	clientBCh := make(chan []byte, 4)

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		upgrader := websocket.Upgrader{}
		conn, err := upgrader.Upgrade(w, r, nil)
		require.NoError(t, err)

		clientID := r.Header.Get("X-Client-Id")
		go func() {
			for {
				_, msg, err := conn.ReadMessage()
				if err != nil {
					return
				}
				var ch chan []byte
				if clientID == "client-A" {
					ch = clientACh
				} else {
					ch = clientBCh
				}
				select {
				case ch <- msg:
				default:
				}
			}
		}()
		select {}
	}))
	defer server.Close()

	url := "ws" + strings.TrimPrefix(server.URL, "http")

	// Connect Client A
	hdrA := http.Header{}
	hdrA.Set("X-Client-Id", "client-A")
	connA, _, err := websocket.DefaultDialer.Dial(url, hdrA)
	require.NoError(t, err)
	defer connA.Close()

	// Connect Client B
	hdrB := http.Header{}
	hdrB.Set("X-Client-Id", "client-B")
	connB, _, err := websocket.DefaultDialer.Dial(url, hdrB)
	require.NoError(t, err)
	defer connB.Close()

	room := &Room{
		NoteID:    "note-lifecycle-1",
		clients:   make(map[*wsConn]struct{}),
		stopHeart: make(chan struct{}),
		leaseMgr:  newMockLeaseManager(),
		ydocSvc:   NewYDocService(nil, nil, nil, "test"),
	}

	wsA := &wsConn{conn: connA}
	wsB := &wsConn{conn: connB}
	room.AddClient(wsA)
	room.AddClient(wsB)

	// Send update from Client A
	updateA := makeTestUpdate(t)
	framedA := ygsync.EncodeUpdate(updateA)
	
	start := time.Now()
	room.HandleIncomingUpdate(framedA, wsA)

	select {
	case msg := <-clientBCh:
		elapsed := time.Since(start)
		assert.Less(t, elapsed, 1*time.Second, "Test 2: broadcast should take less than 1s")
		assert.Equal(t, byte(ygsync.MsgUpdate), msg[0])
	case <-time.After(2 * time.Second):
		t.Fatal("Client B did not receive Client A's broadcast")
	}

	// Send update from Client B
	updateB := makeTestUpdate(t)
	framedB := ygsync.EncodeUpdate(updateB)
	room.HandleIncomingUpdate(framedB, wsB)

	select {
	case msg := <-clientACh:
		assert.Equal(t, byte(ygsync.MsgUpdate), msg[0])
	case <-time.After(2 * time.Second):
		t.Fatal("Client A did not receive Client B's broadcast")
	}
}

func TestRoomLifecycle_QuickReconnect(t *testing.T) {
	// Test 5: A client connects, edits, disconnects, and reconnects quickly
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
	defer server.Close()

	url := "ws" + strings.TrimPrefix(server.URL, "http")

	room := &Room{
		NoteID:    "note-lifecycle-5",
		clients:   make(map[*wsConn]struct{}),
		stopHeart: make(chan struct{}),
		leaseMgr:  newMockLeaseManager(),
		ydocSvc:   NewYDocService(nil, nil, nil, "test"),
	}

	// 1. Initial connect
	conn1, _, err := websocket.DefaultDialer.Dial(url, nil)
	require.NoError(t, err)
	ws1 := &wsConn{conn: conn1}
	room.AddClient(ws1)

	// 2. Make edit
	doc := crdt.New(crdt.WithGC(false))
	text := doc.GetText("content")
	doc.Transact(func(txn *crdt.Transaction) {
		text.Insert(txn, 0, "hello world", nil)
	})
	update := crdt.EncodeStateAsUpdateV1(doc, nil)
	room.HandleIncomingUpdate(ygsync.EncodeUpdate(update), ws1)

	// 3. Disconnect
	room.RemoveClient(ws1)
	conn1.Close()

	// 4. Quick Reconnect
	conn2, _, err := websocket.DefaultDialer.Dial(url, nil)
	require.NoError(t, err)
	defer conn2.Close()
	ws2 := &wsConn{conn: conn2}
	room.AddClient(ws2)

	// Verify room state is preserved in YDoc
	err = room.ydocSvc.WithDoc(context.Background(), room.NoteID, func(roomDoc *crdt.Doc) error {
		val := roomDoc.GetText("content").ToString()
		assert.Equal(t, "hello world", val)
		return nil
	})
	require.NoError(t, err)
}

func TestRoomLifecycle_ThreeClientsOneDisconnects(t *testing.T) {
	// Test 6: Three clients connected, one disconnects, other two continue broadcasting
	clientACh := make(chan []byte, 4)
	clientBCh := make(chan []byte, 4)
	clientCCh := make(chan []byte, 4)

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		upgrader := websocket.Upgrader{}
		conn, err := upgrader.Upgrade(w, r, nil)
		require.NoError(t, err)

		clientID := r.Header.Get("X-Client-Id")
		go func() {
			for {
				_, msg, err := conn.ReadMessage()
				if err != nil {
					return
				}
				var ch chan []byte
				if clientID == "client-A" {
					ch = clientACh
				} else if clientID == "client-B" {
					ch = clientBCh
				} else {
					ch = clientCCh
				}
				select {
				case ch <- msg:
				default:
				}
			}
		}()
		select {}
	}))
	defer server.Close()

	url := "ws" + strings.TrimPrefix(server.URL, "http")

	connA, _, _ := websocket.DefaultDialer.Dial(url, http.Header{"X-Client-Id": []string{"client-A"}})
	connB, _, _ := websocket.DefaultDialer.Dial(url, http.Header{"X-Client-Id": []string{"client-B"}})
	connC, _, _ := websocket.DefaultDialer.Dial(url, http.Header{"X-Client-Id": []string{"client-C"}})

	room := &Room{
		NoteID:    "note-lifecycle-6",
		clients:   make(map[*wsConn]struct{}),
		stopHeart: make(chan struct{}),
		leaseMgr:  newMockLeaseManager(),
		ydocSvc:   NewYDocService(nil, nil, nil, "test"),
	}

	wsA := &wsConn{conn: connA}
	wsB := &wsConn{conn: connB}
	wsC := &wsConn{conn: connC}

	room.AddClient(wsA)
	room.AddClient(wsB)
	room.AddClient(wsC)

	// Disconnect client C
	room.RemoveClient(wsC)
	connC.Close()

	// Verify A and B still work
	updateA := makeTestUpdate(t)
	room.HandleIncomingUpdate(ygsync.EncodeUpdate(updateA), wsA)

	select {
	case msg := <-clientBCh:
		assert.Equal(t, byte(ygsync.MsgUpdate), msg[0])
	case <-time.After(1 * time.Second):
		t.Fatal("Client B should have received Client A's broadcast")
	}

	select {
	case <-clientCCh:
		t.Fatal("Client C should NOT receive updates since it is disconnected")
	case <-time.After(100 * time.Millisecond):
		// Expected
	}
}
