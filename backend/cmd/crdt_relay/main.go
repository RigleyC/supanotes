package main

import (
	"fmt"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

const writeWait = 5 * time.Second

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

type Client struct {
	conn *websocket.Conn
	mu   sync.Mutex
}

func (c *Client) WriteMessage(messageType int, data []byte) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	_ = c.conn.SetWriteDeadline(time.Now().Add(writeWait))
	return c.conn.WriteMessage(messageType, data)
}

func main() {
	var mu sync.Mutex
	var history [][]byte
	clients := make(map[*Client]bool)

	http.HandleFunc("/sync", func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			return
		}
		defer conn.Close()

		client := &Client{conn: conn}

		client.mu.Lock() // Acquire connection lock first to block incoming broadcasts

		mu.Lock()
		clients[client] = true
		// Copy history to read outside lock
		catchup := make([][]byte, len(history))
		copy(catchup, history)
		mu.Unlock()

		defer func() {
			mu.Lock()
			delete(clients, client)
			mu.Unlock()
		}()

		// Write catch-up messages outside global lock
		for _, msg := range catchup {
			_ = client.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := client.conn.WriteMessage(websocket.BinaryMessage, msg); err != nil {
				break
			}
		}
		client.mu.Unlock() // Release connection lock

		for {
			_, msgBytes, err := conn.ReadMessage()
			if err != nil {
				break
			}

			mu.Lock()
			history = append(history, msgBytes)
			// Copy target connections to read outside lock
			var targets []*Client
			for c := range clients {
				if c != client {
					targets = append(targets, c)
				}
			}
			mu.Unlock()

			// Broadcast outside lock
			for _, c := range targets {
				_ = c.WriteMessage(websocket.BinaryMessage, msgBytes)
			}
		}
	})

	fmt.Println("Relay server listening on :8989")
	err := http.ListenAndServe(":8989", nil)
	if err != nil {
		fmt.Printf("Server failed: %v\n", err)
	}
}
