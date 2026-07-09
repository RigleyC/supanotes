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

func (m *mockLeaseManager) AcquireLease(_ context.Context, noteID, machineID string) (string, bool, error) {
	if m.acquireErr != nil {
		return "", false, m.acquireErr
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	if _, ok := m.leases[noteID]; ok {
		return m.leases[noteID], false, nil
	}
	m.leases[noteID] = machineID
	return machineID, true, nil
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
		return "", assertErrorStub{}
	}
	return machine, nil
}

type assertErrorStub struct{}
func (assertErrorStub) Error() string { return "assert error stub" }

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

func makeTestUpdate(t *testing.T) []byte {
	t.Helper()
	doc := crdt.New(crdt.WithGC(false))
	text := doc.GetText("content")
	doc.Transact(func(txn *crdt.Transaction) {
		text.Insert(txn, 0, "test", nil)
	})
	return crdt.EncodeStateAsUpdateV1(doc, nil)
}
