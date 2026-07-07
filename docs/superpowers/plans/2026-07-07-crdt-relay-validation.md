# Plan: CRDT LF Go Relay Verification Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a trivial Go relay server and a Dart client test to verify the "dumb relay" architecture hypothesis: that clients can successfully sync and resolve Fugue conflicts when the server simply acts as a blind message broadcaster/persister without decoding or understanding the payloads.

**Architecture:** 
- A simple Go binary (`backend/cmd/crdt_relay/main.go`) that starts a WebSocket server, stores raw binary messages in memory (history list), sends history to newly connected clients (catch-up), and broadcasts incoming messages to other clients.
- A Dart test (`test/crdt_validation/crdt_relay_test.dart`) that spawns the Go server, starts two `crdt_lf` documents, connects them via WebSockets, exchanges edits, and verifies convergence.

**Tech Stack:** Go (Standard Library + Gorilla Websocket), Dart (Standard Library `dart:io` + `crdt_lf` package).

---

### Task 1: Go Dumb Relay Server

**Files:**
- Create: [main.go](file:///c:/Users/rigleyc/projects/supanotes/backend/cmd/crdt_relay/main.go)

- [ ] **Step 1: Write the Go relay server**
  Create `backend/cmd/crdt_relay/main.go` with a simple WebSocket relay server.

  Code:
  ```go
  package main

  import (
  	"fmt"
  	"net/http"
  	"sync"

  	"github.com/gorilla/websocket"
  )

  var upgrader = websocket.Upgrader{
  	CheckOrigin: func(r *http.Request) bool { return true },
  }

  func main() {
  	var mu sync.Mutex
  	var history [][]byte
  	clients := make(map[*websocket.Conn]bool)

  	http.HandleFunc("/sync", func(w http.ResponseWriter, r *http.Request) {
  		conn, err := upgrader.Upgrade(w, r, nil)
  		if err != nil {
  			return
  		}
  		defer conn.Close()

  		mu.Lock()
  		clients[conn] = true
  		// Send all stored catch-up history to new client
  		for _, msg := range history {
  			_ = conn.WriteMessage(websocket.BinaryMessage, msg)
  		}
  		mu.Unlock()

  		defer func() {
  			mu.Lock()
  			delete(clients, conn)
  			mu.Unlock()
  		}()

  		for {
  			_, msgBytes, err := conn.ReadMessage()
  			if err != nil {
  				break
  			}

  			mu.Lock()
  			// Persist raw bytes blindly in history log
  			history = append(history, msgBytes)
  			// Relay to all other clients
  			for c := range clients {
  				if c != conn {
  					_ = c.WriteMessage(websocket.BinaryMessage, msgBytes)
  				}
  			}
  			mu.Unlock()
  		}
  	})

  	fmt.Println("Relay server listening on :8989")
  	err := http.ListenAndServe(":8989", nil)
  	if err != nil {
  		fmt.Printf("Server failed: %v\n", err)
  	}
  }
  ```

- [ ] **Step 2: Verify compilation of Go relay**
  Run: `go build -o /tmp/crdt_relay backend/cmd/crdt_relay/main.go` (or `go build -o crdt_relay.exe ./backend/cmd/crdt_relay/main.go` on Windows).
  Expected: Builds cleanly without syntax errors.

- [ ] **Step 3: Commit**
  Run:
  `git add backend/cmd/crdt_relay/main.go; git commit -m "test(sync): implement dumb Go websocket relay"`

---

### Task 2: Dart Relay Integration Test

**Files:**
- Create: [crdt_relay_test.dart](file:///c:/Users/rigleyc/projects/supanotes/test/crdt_validation/crdt_relay_test.dart)

- [ ] **Step 1: Write Dart websocket integration test**
  Create `test/crdt_validation/crdt_relay_test.dart` to spawn the Go server, connect two document nodes via WebSockets, and assert convergence after concurrent editing.

  Code:
  ```dart
  import 'dart:async';
  import 'dart:io';
  import 'dart:typed_data';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:crdt_lf/crdt_lf.dart';

  void main() {
    test('Dumb Go Relay sync and convergence verification', () async {
      // 1. Spawn Go server process
      final process = await Process.start(
        'go',
        ['run', 'backend/cmd/crdt_relay/main.go'],
      );

      // Wait a moment for server to bind
      await Future.delayed(const Duration(milliseconds: 800));

      final docs = <String, CRDTDocument>{};
      final sockets = <String, WebSocket>{};

      // Helper to setup client
      Future<CRDTDocument> setupClient(String name, PeerId peerId) async {
        final doc = CRDTDocument(peerId: peerId)..registerDefaultFactories();
        final ws = await WebSocket.connect('ws://localhost:8989/sync');
        
        sockets[name] = ws;
        docs[name] = doc;

        // Auto-instantiate the Fugue text handler
        CRDTFugueTextHandler(doc, 'text-relay');

        ws.listen((data) {
          if (data is List<int>) {
            doc.binaryImportChanges(Uint8List.fromList(data));
          }
        });

        return doc;
      }

      final peerA = PeerId.parse('00000000-0000-4000-8000-000000000001');
      final peerB = PeerId.parse('00000000-0000-4000-8000-000000000002');

      final docA = await setupClient('A', peerA);
      final docB = await setupClient('B', peerB);

      final textA = docA.registeredHandlers['text-relay']! as CRDTFugueTextHandler;
      final textB = docB.registeredHandlers['text-relay']! as CRDTFugueTextHandler;

      // Type initial text on A and sync
      textA.insert(0, "Hello");
      sockets['A']!.add(docA.binaryExportChanges());

      // Wait for sync propagation
      await Future.delayed(const Duration(milliseconds: 200));
      expect(textB.value, "Hello");

      // Concurrent edits
      textA.insert(5, " Ola");
      textB.insert(5, " World");

      // Export changes concurrently
      sockets['A']!.add(docA.binaryExportChanges());
      sockets['B']!.add(docB.binaryExportChanges());

      // Wait for sync propagation
      await Future.delayed(const Duration(milliseconds: 400));

      // Assert that both documents have converged to the exact same text
      expect(textA.value, textB.value);
      expect(textA.value, anyOf('Hello Ola World', 'Hello World Ola'));

      // Close sockets and kill server
      await sockets['A']!.close();
      await sockets['B']!.close();
      process.kill();
    });
  }
  ```

- [ ] **Step 2: Run Go Relay integration test**
  Run:
  `flutter test test/crdt_validation/crdt_relay_test.dart`
  Expected: Test passes successfully.

- [ ] **Step 3: Commit**
  Run:
  `git add test/crdt_validation/crdt_relay_test.dart; git commit -m "test(sync): add Go websocket relay integration test"`
