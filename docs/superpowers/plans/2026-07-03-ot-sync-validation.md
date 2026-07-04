# Plan 001: OT Sync Validation (Etapa 1 & 2)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` (create it if not present).
>
> **Drift check (run first)**: `git diff --stat master -- backend/internal/sync/`
> If any file in this package has changed since the plan was written, compare the
> "Current state" excerpts against the live code before proceeding.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: tests
- **Planned at**: commit `master`, 2026-07-03

## Why this matters

Before committing to a complex collaborative rich-text synchronization architecture in production, we must validate:
1. That the third-party Go Operational Transformation (OT) library (`go-quilljs-delta`) converges deterministically under concurrent, out-of-order, and conflicting edits.
2. That a sequencing server in Go can coordinate multiple WebSocket connections, resolve concurrent updates using OT, broadcast transformed deltas, and maintain a consistent document state without race conditions or flakiness.

By completing this validation, we ensure the foundation is sound before rewriting production code or integrating with Flutter.

## Current state

- The Go backend currently implements a state-sync, Last-Write-Wins (LWW) model under `backend/internal/sync/service.go`. It does not support OT, WebSockets, or live document merging.
- We will isolate our validation code to a separate package (`backend/internal/sync/otvalidation`) to avoid polluting the production code and namespaces with temporary or mock structs.
- Verification commands check if the workspace compiles and runs tests cleanly. We must ensure `go test` runs correctly.

## Commands you will need

| Purpose   | Command                                                     | Expected on success |
|-----------|-------------------------------------------------------------|---------------------|
| Install   | `go get github.com/fmpwizard/go-quilljs-delta/delta`        | exit 0              |
| Install   | `go get github.com/gorilla/websocket`                       | exit 0              |
| Run Test1 | `go test -v ./internal/sync/otvalidation -run TestOT_`      | PASS                |
| Run Test2 | `go test -v ./internal/sync/otvalidation -run TestWS_`      | PASS                |

## Scope

**In scope** (the only files you should modify/create):
- `backend/internal/sync/otvalidation/ot_convergence_test.go` (create)
- `backend/internal/sync/otvalidation/ot_websocket_test.go` (create)
- `backend/go.mod` (modify via `go get` commands)

**Out of scope** (do NOT touch, even though they look related):
- `backend/internal/sync/service.go` — Leave production sync logic untouched.
- `backend/internal/sync/handler.go` — Do not modify HTTP handlers.

## Git workflow

- Commit per task. Message style: `test(sync): <description>`

---

## Steps

### Step 1: Install dependencies and create convergence test structure

Run:
```bash
cd backend
go get github.com/fmpwizard/go-quilljs-delta/delta
go get github.com/stretchr/testify
```

Create directory `backend/internal/sync/otvalidation/`. Inside it, create `ot_convergence_test.go` with deterministic OT edge-case tests:

```go
package otvalidation

import (
	"encoding/json"
	"math/rand"
	"testing"
	"time"

	"github.com/fmpwizard/go-quilljs-delta/delta"
	"github.com/stretchr/testify/assert"
)

// Invariant: Base.Compose(A).Compose(B.Transform(A, false)) == Base.Compose(B).Compose(A.Transform(B, true))
func assertConvergence(t *testing.T, base, a, b *delta.Delta) {
	aPrime := b.Transform(*a, true)
	bPrime := a.Transform(*b, false)

	docA := base.Compose(*a).Compose(*bPrime)
	docB := base.Compose(*b).Compose(*aPrime)

	jsonA, errA := json.Marshal(docA.Ops)
	jsonB, errB := json.Marshal(docB.Ops)

	if errA != nil || errB != nil {
		t.Fatalf("Failed to serialize ops to JSON: %v, %v", errA, errB)
	}

	assert.JSONEq(t, string(jsonA), string(jsonB), "Divergence detected!\nBase: %+v\nDelta A: %+v\nDelta B: %+v\nDelta A': %+v\nDelta B': %+v\nDoc A: %s\nDoc B: %s\n",
		base.Ops, a.Ops, b.Ops, aPrime.Ops, bPrime.Ops, string(jsonA), string(jsonB))
}

func TestOT_ConcurrentInsertSamePosition(t *testing.T) {
	base := delta.New().Insert("Hello", nil)
	a := delta.New().Retain(5, nil).Insert(" World", nil)
	b := delta.New().Retain(5, nil).Insert(" Guys", nil)

	assertConvergence(t, base, a, b)
}

func TestOT_DeleteOverlappingInsert(t *testing.T) {
	base := delta.New().Insert("Hello World", nil)
	a := delta.New().Retain(6, nil).Delete(5)
	b := delta.New().Retain(6, nil).Insert("Earth", nil)

	assertConvergence(t, base, a, b)
}

func TestOT_InsertInsideDeleteRange(t *testing.T) {
	base := delta.New().Insert("Hello World", nil)
	a := delta.New().Retain(3, nil).Delete(5)
	b := delta.New().Retain(5, nil).Insert("X", nil)

	assertConvergence(t, base, a, b)
}

func TestOT_ConflictingAttributes(t *testing.T) {
	base := delta.New().Insert("Hello World", nil)
	a := delta.New().Retain(6, nil).Retain(5, map[string]interface{}{"bold": true})
	b := delta.New().Retain(6, nil).Retain(5, map[string]interface{}{"italic": true})

	assertConvergence(t, base, a, b)
}
```

**Verify**: `go test -v ./internal/sync/otvalidation -run TestOT_` → PASS

### Step 2: Implement Fuzzing loop for OT convergence

Append the fuzzing logic to `backend/internal/sync/otvalidation/ot_convergence_test.go`:

```go
func randomString(n int, r *rand.Rand) string {
	var letters = []rune("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ")
	s := make([]rune, n)
	for i := range s {
		s[i] = letters[r.Intn(len(letters))]
	}
	return string(s)
}

func generateRandomDelta(docLength int, r *rand.Rand) *delta.Delta {
	d := delta.New()
	cursor := 0
	actionsCount := r.Intn(3) + 1

	for i := 0; i < actionsCount; i++ {
		if cursor >= docLength {
			d.Insert(randomString(r.Intn(5)+1, r), nil)
			break
		}

		actionType := r.Intn(3) // 0: Retain, 1: Insert, 2: Delete
		switch actionType {
		case 0: // Retain
			remLength := docLength - cursor
			if remLength <= 0 {
				continue
			}
			retainLen := r.Intn(remLength) + 1
			var attrs map[string]interface{}
			if r.Float32() < 0.3 {
				attrs = map[string]interface{}{"bold": true}
			}
			d.Retain(retainLen, attrs)
			cursor += retainLen
		case 1: // Insert
			d.Insert(randomString(r.Intn(5)+1, r), nil)
		case 2: // Delete
			remLength := docLength - cursor
			if remLength <= 0 {
				continue
			}
			deleteLen := r.Intn(remLength) + 1
			d.Delete(deleteLen)
			cursor += deleteLen
		}
	}
	return d
}

func TestOT_FuzzingConvergence(t *testing.T) {
	seed := time.Now().UnixNano()
	r := rand.New(rand.NewSource(seed))
	t.Logf("[OT Fuzz] Starting fuzzing with seed: %d", seed)

	iterations := 1000
	for i := 0; i < iterations; i++ {
		baseText := "O rato roeu a roupa do rei de Roma."
		baseDoc := delta.New().Insert(baseText, nil)
		docLength := len(baseText)

		deltaA := generateRandomDelta(docLength, r)
		deltaB := generateRandomDelta(docLength, r)

		assertConvergence(t, baseDoc, deltaA, deltaB)
	}
}
```

**Verify**: `go test -v ./internal/sync/otvalidation -run TestOT_` → PASS (All 5 tests must pass).

Commit changes:
```bash
git add backend/go.mod backend/go.sum backend/internal/sync/otvalidation/ot_convergence_test.go
git commit -m "test(sync): implement fuzzing and edge cases convergence tests for OT"
```

### Step 3: Implement WebSocket Sequencing Server and Client Harness

Run:
```bash
cd backend
go get github.com/gorilla/websocket
```

Create file `backend/internal/sync/otvalidation/ot_websocket_test.go` with a real-time sequencing server mock and client convergence test:

```go
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
						clientDelta = *histDelta.Transform(clientDelta, false)
					}
				}

				room.State = room.State.Compose(clientDelta)
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
		State:   delta.New().Insert(baseText, nil),
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

	for i := 0; i < numClients; i++ {
		clientStates[i] = delta.New().Insert(baseText, nil)
		clientVersions[i] = 0
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
			defer c.Close()

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
						// Apply only if it was sent by ANOTHER client.
						// The sender already applied it locally before transmitting.
						if msg.SenderID != clientIDStr {
							clientStates[clientId] = clientStates[clientId].Compose(msg.Delta)
						}
						clientVersions[clientId] = msg.Version
						clientMus[clientId].Unlock()
					}
				}
			}()

			rng := rand.New(rand.NewSource(time.Now().UnixNano() + int64(clientId)))
			for j := 0; j < editsPerClient; j++ {
				// Jitter
				time.Sleep(time.Duration(rng.Intn(15)) * time.Millisecond)

				clientMus[clientId].Lock()
				baseVersion := clientVersions[clientId]
				editString := string(rune('A' + clientId)) + strings.Repeat(string(rune('a'+clientId)), rng.Intn(2))
				editDelta := delta.New().Retain(rng.Intn(5), nil).Insert(editString, nil)

				// Apply locally first (instant UI feedback flow)
				clientStates[clientId] = clientStates[clientId].Compose(*editDelta)
				clientMus[clientId].Unlock()

				msg := WSMessage{
					Type:        "edit",
					SenderID:    clientIDStr,
					BaseVersion: baseVersion,
					Delta:       *editDelta,
				}
				msgBytes, _ := json.Marshal(msg)
				_ = c.WriteMessage(websocket.TextMessage, msgBytes)
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
```

**Verify**: `go test -v ./internal/sync/otvalidation -run TestWS_` → PASS

Commit changes:
```bash
git add backend/go.mod backend/go.sum backend/internal/sync/otvalidation/ot_websocket_test.go
git commit -m "test(sync): implement concurrent WebSocket client-server convergence test"
```

---

## Test plan

- Test 1: `go test -v ./internal/sync/otvalidation -run TestOT_` → Verifies convergence mathematically under 4 deterministic edge cases and 1000 randomized iterations.
- Test 2: `go test -v ./internal/sync/otvalidation -run TestWS_` → Verifies that a WebSocket server and 5 concurrent clients can send, transform, apply, and synchronize document states.

---

## Done criteria

- [ ] All 5 tests in `./internal/sync/otvalidation/...` pass successfully.
- [ ] No changes are made to production code files under `backend/internal/sync/` (checked via `git status`).
- [ ] `go.mod` is updated with only `github.com/fmpwizard/go-quilljs-delta` and `github.com/gorilla/websocket`.

---

## STOP conditions

Stop and report back if:
- `go get github.com/fmpwizard/go-quilljs-delta/delta` fails or returns 404.
- Any convergence test fails TestOT_ Convergence, indicating that the delta library does not correctly transform operations.
- The WebSocket test hangs or fails to converge after multiple attempts, suggesting a locking or transform ordering bug.
