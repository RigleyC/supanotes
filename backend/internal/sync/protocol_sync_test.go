package sync

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gorilla/websocket"
	"github.com/reearth/ygo/crdt"
	ygsync "github.com/reearth/ygo/sync"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestProtocolSync_HandshakeVectors(t *testing.T) {
	// Test 7: Handshake with empty vs containing state vectors
	clientCh := make(chan []byte, 4)

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Log("Mock Server: Connection upgraded.")
		upgrader := websocket.Upgrader{}
		conn, err := upgrader.Upgrade(w, r, nil)
		require.NoError(t, err)

		// 1. Read Server's Step 1
		t.Log("Mock Server: Reading Step 1...")
		_, rawStep1, err := conn.ReadMessage()
		if err != nil {
			t.Log("Mock Server: Read Step 1 error:", err.Error())
		} else {
			t.Log("Mock Server: Read Step 1 success.")
			clientCh <- rawStep1
		}

		// 2. Write client Step 1 back (empty)
		t.Log("Mock Server: Writing client Step 1...")
		emptyDoc := crdt.New(crdt.WithGC(false))
		clientStep1 := ygsync.EncodeSyncStep1(emptyDoc)
		err = conn.WriteMessage(websocket.BinaryMessage, clientStep1)
		if err != nil {
			t.Log("Mock Server: Write client Step 1 error:", err.Error())
		} else {
			t.Log("Mock Server: Write client Step 1 success.")
		}

		// 3. Read Server's Step 2
		t.Log("Mock Server: Reading Step 2...")
		_, rawStep2, err := conn.ReadMessage()
		if err != nil {
			t.Log("Mock Server: Read Step 2 error:", err.Error())
		} else {
			t.Log("Mock Server: Read Step 2 success.")
			clientCh <- rawStep2
		}

		t.Log("Mock Server: Handler loop idle.")
		select {}
	}))
	defer server.Close()

	url := "ws" + strings.TrimPrefix(server.URL, "http")

	room := &Room{
		NoteID:    "00000000-0000-0000-0000-000000000007",
		clients:   make(map[*wsConn]struct{}),
		stopHeart: make(chan struct{}),
		leaseMgr:  newMockLeaseManager(),
		ydocSvc:   NewYDocService(nil, nil, nil),
	}

	// Add previous content to Room's YDoc
	err := room.ydocSvc.WithDoc(context.Background(), room.NoteID, func(doc *crdt.Doc) error {
		text := doc.GetText("content")
		doc.Transact(func(txn *crdt.Transaction) {
			text.Insert(txn, 0, "previous content", nil)
		})
		return nil
	})
	require.NoError(t, err)

	t.Log("Dialing...")
	conn, _, err := websocket.DefaultDialer.Dial(url, nil)
	require.NoError(t, err)
	defer conn.Close()
	t.Log("Dialed.")

	ws := &wsConn{conn: conn}
	room.AddClient(ws)

	// Execute handshake synchronously
	t.Log("Starting HandleHandshake...")
	err = room.HandleHandshake(ws)
	t.Log("HandleHandshake done. Error:", err)
	require.NoError(t, err)

	// Verify Step 1 received by mock server (client side)
	t.Log("Reading rawStep1 from channel...")
	rawStep1 := <-clientCh
	t.Log("rawStep1 read.")
	assert.Equal(t, byte(ygsync.MsgSyncStep1), rawStep1[0])

	// Verify Step 2 received by mock server (client side)
	t.Log("Reading rawStep2 from channel...")
	rawStep2 := <-clientCh
	t.Log("rawStep2 read.")
	assert.Equal(t, byte(ygsync.MsgSyncStep2), rawStep2[0])

	// Verify that applying rawStep2 to an empty client doc yields the "previous content"
	clientDoc := crdt.New(crdt.WithGC(false))
	clientDoc.GetText("content") // register type
	_, err = ygsync.ApplySyncMessage(clientDoc, rawStep2, "remote")
	require.NoError(t, err)
	assert.Equal(t, "previous content", clientDoc.GetText("content").ToString())
}

func TestProtocolSync_UnexpectedMessageType(t *testing.T) {
	// Test 8: Unexpected message tag/type sent mid-session must not corrupt or crash
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
		NoteID:    "note-protocol-8",
		clients:   make(map[*wsConn]struct{}),
		stopHeart: make(chan struct{}),
		leaseMgr:  newMockLeaseManager(),
		ydocSvc:   NewYDocService(nil, nil, nil),
	}

	conn, _, err := websocket.DefaultDialer.Dial(url, nil)
	require.NoError(t, err)
	defer conn.Close()

	ws := &wsConn{conn: conn}
	room.AddClient(ws)

	// Send an unexpected message tag (e.g. tag 99)
	badMsg := []byte{99, 1, 2, 3, 4}
	
	// HandleIncomingUpdate should handle it gracefully without crashing
	assert.NotPanics(t, func() {
		room.HandleIncomingUpdate(badMsg, ws)
	})

	// Doc should still be valid
	err = room.ydocSvc.WithDoc(context.Background(), room.NoteID, func(doc *crdt.Doc) error {
		assert.NotNil(t, doc)
		return nil
	})
	require.NoError(t, err)
}

func TestProtocolSync_MalformedUpdate(t *testing.T) {
	// Test 9: Malformed or truncated updates should be rejected safely
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
		NoteID:    "note-protocol-9",
		clients:   make(map[*wsConn]struct{}),
		stopHeart: make(chan struct{}),
		leaseMgr:  newMockLeaseManager(),
		ydocSvc:   NewYDocService(nil, nil, nil),
	}

	conn, _, err := websocket.DefaultDialer.Dial(url, nil)
	require.NoError(t, err)
	defer conn.Close()

	ws := &wsConn{conn: conn}
	room.AddClient(ws)

	// MsgUpdate message with truncated/malformed payload
	// The prefix is MsgUpdate (type 2), but payload is corrupt
	badUpdateMsg := []byte{byte(ygsync.MsgUpdate), 255, 255, 255}

	assert.NotPanics(t, func() {
		room.HandleIncomingUpdate(badUpdateMsg, ws)
	})

	// Doc state remains uncorrupted
	err = room.ydocSvc.WithDoc(context.Background(), room.NoteID, func(doc *crdt.Doc) error {
		assert.NotNil(t, doc)
		return nil
	})
	require.NoError(t, err)
}
