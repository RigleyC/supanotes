package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/reearth/ygo/crdt"
)

func main() {
	ctx := context.Background()
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		log.Fatal("DATABASE_URL environment variable is required")
	}

	conn, err := pgx.Connect(ctx, dbURL)
	if err != nil {
		log.Fatalf("connect to database: %v", err)
	}
	defer conn.Close(ctx)

	// Fetch all notes with non-empty markdown content
	rows, err := conn.Query(ctx, "SELECT id, content::text FROM notes WHERE content IS NOT NULL AND content != ''")
	if err != nil {
		log.Fatalf("query notes: %v", err)
	}
	defer rows.Close()

	type noteData struct {
		ID      string
		Content string
	}
	var notes []noteData
	for rows.Next() {
		var n noteData
		if err := rows.Scan(&n.ID, &n.Content); err != nil {
			log.Fatalf("scan note: %v", err)
		}
		notes = append(notes, n)
	}

	var count int
	for _, n := range notes {
		if err := migrateNote(ctx, conn, n.ID, n.Content); err != nil {
			log.Printf("error migrating note %s: %v", n.ID, err)
		} else {
			count++
		}
	}
	log.Printf("Successfully migrated %d notes to YDoc state", count)
}

func migrateNote(ctx context.Context, conn *pgx.Conn, noteID, content string) error {
	doc := crdt.New(crdt.WithGC(false))
	nodesMap := doc.GetMap("nodes")

	lines := strings.Split(content, "\n")
	
	type parsedNode struct {
		Key  string
		Text string
	}
	var parsedNodes []parsedNode

	doc.Transact(func(txn *crdt.Transaction) {
		for i, line := range lines {
			trimmed := strings.TrimSpace(line)
			if trimmed == "" {
				continue
			}

			nodeType := "paragraph"
			if strings.HasPrefix(trimmed, "- [ ] ") || strings.HasPrefix(trimmed, "- [x] ") {
				nodeType = "task"
				trimmed = trimmed[6:] // remove checkbox
			} else if strings.HasPrefix(trimmed, "# ") {
				nodeType = "header"
				trimmed = trimmed[2:]
			}

			key := uuid.New().String()
			pos := fmt.Sprintf("a%05d", i)

			raw, _ := json.Marshal(map[string]string{"text": trimmed})
			meta, _ := json.Marshal(map[string]interface{}{
				"id":       key,
				"type":     nodeType,
				"position": pos,
				"data":     json.RawMessage(raw),
			})
			nodesMap.Set(txn, key, string(meta))
			
			parsedNodes = append(parsedNodes, parsedNode{Key: key, Text: trimmed})
		}
	})

	for _, pn := range parsedNodes {
		textType := doc.GetText("content/" + pn.Key)
		doc.Transact(func(txn *crdt.Transaction) {
			textType.Insert(txn, 0, pn.Text, nil)
		})
	}

	newState := crdt.EncodeStateAsUpdateV1(doc, nil)
	noteUUID := uuid.MustParse(noteID)

	// Upsert into note_yjs_states
	_, err := conn.Exec(ctx, `
		INSERT INTO note_yjs_states (note_id, state)
		VALUES ($1, $2)
		ON CONFLICT (note_id) DO UPDATE SET state = EXCLUDED.state, updated_at = NOW()
	`, noteUUID, newState)
	
	return err
}
