package otvalidation

import (
	"encoding/json"
	"math/rand"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync"
	"testing"
	"time"

	prodsync "github.com/RigleyC/supanotes/internal/sync"
	"github.com/fmpwizard/go-quilljs-delta/delta"
	"github.com/gorilla/websocket"
	"github.com/stretchr/testify/assert"
)

type NoteRoom struct {
	mu           sync.Mutex
	Version      int
	History      []delta.Delta
	State        *delta.Delta
	clients      map[string]*websocket.Conn // client_id -> connection
	ProcessedMsg int
	Cond         *sync.Cond
}

type WSMessage struct {
	Type        string      `json:"type"`
	SenderID    string      `json:"sender_id"`
	BaseVersion int         `json:"base_version,omitempty"`
	Version     int         `json:"version,omitempty"`
	Delta       delta.Delta `json:"delta,omitempty"`
}

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

func startTestWSServer(t *testing.T, room *NoteRoom) *httptest.Server {
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			t.Errorf("Failed to upgrade websocket: %v", err)
			return
		}
		defer conn.Close()

		clientID := r.URL.Query().Get("client_id")
		if clientID == "" {
			t.Error("Missing client_id parameter")
			return
		}

		room.mu.Lock()
		room.clients[clientID] = conn
		room.mu.Unlock()

		defer func() {
			room.mu.Lock()
			delete(room.clients, clientID)
			room.mu.Unlock()
		}()

		for {
			_, messageBytes, err := conn.ReadMessage()
			if err != nil {
				break
			}

			var msg WSMessage
			if err := json.Unmarshal(messageBytes, &msg); err != nil {
				t.Errorf("Failed to unmarshal WS message: %v", err)
				continue
			}

			if msg.Type == "edit" {
				room.mu.Lock()
				clientDelta := msg.Delta
				baseVer := msg.BaseVersion

				if baseVer < room.Version {
					for _, histDelta := range room.History[baseVer:] {
						// Safe transform to prevent memory corruption/aliasing
						clientDelta = *prodsync.SafeTransform(&clientDelta, &histDelta, false)
					}
				}

				// Safe compose to prevent memory corruption/aliasing
				room.State = prodsync.SafeCompose(room.State, &clientDelta)
				room.History = append(room.History, clientDelta)
				room.Version++
				currentVersion := room.Version

				resp := WSMessage{
					Type:     "update",
					SenderID: msg.SenderID,
					Version:  currentVersion,
					Delta:    clientDelta,
				}
				respBytes, _ := json.Marshal(resp)

				for _, c := range room.clients {
					_ = c.WriteMessage(websocket.TextMessage, respBytes)
				}

				room.ProcessedMsg++
				room.Cond.Broadcast()
				room.mu.Unlock()
			}
		}
	}))
}

func TestWS_SequencingAndConvergence(t *testing.T) {
	baseText := "Hello"
	room := &NoteRoom{
		Version: 0,
		History: make([]delta.Delta, 0),
		State:   delta.New(nil).Insert(baseText, nil),
		clients: make(map[string]*websocket.Conn),
	}
	room.Cond = sync.NewCond(&room.mu)

	server := startTestWSServer(t, room)
	defer server.Close()

	u, _ := url.Parse(server.URL)
	u.Scheme = "ws"

	numClients := 5
	editsPerClient := 10
	expectedTotalProcessed := numClients * editsPerClient

	var wg sync.WaitGroup
	wg.Add(numClients)

	clientStates := make([]*delta.Delta, numClients)
	clientVersions := make([]int, numClients)
	clientMus := make([]sync.Mutex, numClients)
	clientAckConds := make([]*sync.Cond, numClients)
	clientOutstanding := make([]*delta.Delta, numClients)
	clientConns := make([]*websocket.Conn, numClients)

	defer func() {
		for _, conn := range clientConns {
			if conn != nil {
				conn.Close()
			}
		}
	}()

	for i := 0; i < numClients; i++ {
		clientStates[i] = delta.New(nil).Insert(baseText, nil)
		clientVersions[i] = 0
		clientAckConds[i] = sync.NewCond(&clientMus[i])
		clientOutstanding[i] = nil
	}

	for i := 0; i < numClients; i++ {
		go func(clientId int) {
			defer wg.Done()

			clientIDStr := string(rune('0' + clientId))
			wsURL := u.String() + "?client_id=" + clientIDStr

			c, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
			if err != nil {
				t.Errorf("Client %d failed to connect: %v", clientId, err)
				return
			}
			clientMus[clientId].Lock()
			clientConns[clientId] = c
			clientMus[clientId].Unlock()

			// Listen loop
			go func() {
				for {
					_, msgBytes, err := c.ReadMessage()
					if err != nil {
						break
					}
					var msg WSMessage
					_ = json.Unmarshal(msgBytes, &msg)

					if msg.Type == "update" {
						clientMus[clientId].Lock()
						if msg.SenderID == clientIDStr {
							// Ack of our own edit
							clientOutstanding[clientId] = nil
							clientVersions[clientId] = msg.Version
							clientAckConds[clientId].Broadcast()
						} else {
							// Edit from another client.
							if clientOutstanding[clientId] != nil {
								// Transform incoming delta against our outstanding delta
								// The server-side edit has priority (priority = true)
								serverEdit := msg.Delta
								serverEditPrime := prodsync.SafeTransform(&serverEdit, clientOutstanding[clientId], true)
								clientStates[clientId] = prodsync.SafeCompose(clientStates[clientId], serverEditPrime)

								// Update our outstanding delta for future messages (priority = false)
								clientOutstanding[clientId] = prodsync.SafeTransform(clientOutstanding[clientId], &serverEdit, false)
							} else {
								clientStates[clientId] = prodsync.SafeCompose(clientStates[clientId], &msg.Delta)
							}
							clientVersions[clientId] = msg.Version
						}
						clientMus[clientId].Unlock()
					}
				}
			}()

			rng := rand.New(rand.NewSource(time.Now().UnixNano() + int64(clientId)))
			for j := 0; j < editsPerClient; j++ {
				// Jitter
				time.Sleep(time.Duration(rng.Intn(15)) * time.Millisecond)

				clientMus[clientId].Lock()
				// Wait for previous edit to be acknowledged
				for clientOutstanding[clientId] != nil {
					clientAckConds[clientId].Wait()
				}

				baseVersion := clientVersions[clientId]
				editString := string(rune('A' + clientId)) + strings.Repeat(string(rune('a'+clientId)), rng.Intn(2))
				editDelta := delta.New(nil).Retain(rng.Intn(5), nil).Insert(editString, nil)

				// Apply locally first (instant UI feedback)
				clientStates[clientId] = prodsync.SafeCompose(clientStates[clientId], editDelta)
				clientOutstanding[clientId] = editDelta

				msg := WSMessage{
					Type:        "edit",
					SenderID:    clientIDStr,
					BaseVersion: baseVersion,
					Delta:       *editDelta,
				}
				msgBytes, _ := json.Marshal(msg)
				_ = c.WriteMessage(websocket.TextMessage, msgBytes)
				clientMus[clientId].Unlock()
			}
		}(i)
	}

	// Wait for edit threads to finish transmitting
	wg.Wait()

	// Wait deterministically for the server to process all expected edits
	room.mu.Lock()
	for room.ProcessedMsg < expectedTotalProcessed {
		room.Cond.Wait()
	}
	serverJSON, _ := json.Marshal(room.State.Ops)
	room.mu.Unlock()

	// Small padding to let client socket listener loops process the final broadcast
	time.Sleep(50 * time.Millisecond)

	// Validate convergence
	for i := 0; i < numClients; i++ {
		clientMus[i].Lock()
		clientJSON, _ := json.Marshal(clientStates[i].Ops)
		clientMus[i].Unlock()

		assert.JSONEq(t, string(serverJSON), string(clientJSON), "Client %d state did not converge with server state", i)
	}
}
