package main

import (
	"context"
	"encoding/json"
	"log"
	"os"
	"strings"

	"github.com/joho/godotenv"
	"github.com/reearth/ygo/crdt"
	"github.com/RigleyC/supanotes/pkg/db"
)

func main() {
	if err := godotenv.Load("../.env"); err != nil {
		godotenv.Load(".env")
	}

	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		log.Fatal("DATABASE_URL must be set")
	}

	ctx := context.Background()
	pool, err := db.Connect(ctx, dbURL)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	defer pool.Close()

	log.Println("Starting Yjs metadata migration...")

	rows, err := pool.Query(ctx, "SELECT note_id, state FROM note_yjs_states")
	if err != nil {
		log.Fatalf("Failed to query note_yjs_states: %v", err)
	}
	defer rows.Close()

	var notesToMigrate []string

	for rows.Next() {
		var noteID string
		var state []byte
		if err := rows.Scan(&noteID, &state); err != nil {
			log.Fatalf("Failed to scan row: %v", err)
		}

		doc := crdt.New(crdt.WithGC(false))
		doc.ApplyUpdate(state)

		mutDoc := crdt.New(crdt.WithGC(false))
		needsUpdate := false

		nodesMap := doc.GetMap("nodes")
		if nodesMap != nil {
			for key, raw := range nodesMap.Entries() {
				if strings.Contains(key, ":") {
					continue // Already a composite key
				}

				nodeStr, ok := raw.(string)
				if !ok {
					continue // Might already be a YMap if migrated
				}

				var nodeData map[string]interface{}
				if err := json.Unmarshal([]byte(nodeStr), &nodeData); err != nil {
					continue
				}

				data, ok := nodeData["data"].(map[string]interface{})
				if !ok {
					continue
				}

				// Check if there are legacy fields in data
				fieldsToMigrate := []string{"completed", "dueDate", "recurrence", "lastCompletedAt", "hasTime"}
				migratedAny := false

				for _, field := range fieldsToMigrate {
					if val, exists := data[field]; exists {
						nodesMapOut := mutDoc.GetMap("nodes")
						mutDoc.Transact(func(txn *crdt.Transaction) {
							nodesMapOut.Set(txn, key+":"+field, val)
						})
						delete(data, field)
						migratedAny = true
					}
				}

				if migratedAny {
					needsUpdate = true
					nodeData["data"] = data
					updatedJSON, _ := json.Marshal(nodeData)
					nodesMapOut := mutDoc.GetMap("nodes")
					mutDoc.Transact(func(txn *crdt.Transaction) {
						nodesMapOut.Set(txn, key, string(updatedJSON))
					})
				}
			}
		}

		// Also clean up the old YMap("tasks") if it exists
		tasksMap := doc.GetMap("tasks")
		if tasksMap != nil && len(tasksMap.Keys()) > 0 {
			needsUpdate = true
			tasksMapOut := mutDoc.GetMap("tasks")
			for _, key := range tasksMap.Keys() {
				mutDoc.Transact(func(txn *crdt.Transaction) {
					tasksMapOut.Delete(txn, key)
				})
			}
		}

		if needsUpdate {
			updateBytes := crdt.EncodeStateAsUpdateV1(mutDoc, nil)
			// Apply update to the original doc to get the full state
			doc.ApplyUpdate(updateBytes)
			newState := crdt.EncodeStateAsUpdateV1(doc, nil)

			tx, err := pool.Begin(ctx)
			if err != nil {
				log.Fatalf("Failed to begin tx: %v", err)
			}

			_, err = tx.Exec(ctx, "UPDATE note_yjs_states SET state = $1, updated_at = NOW() WHERE note_id = $2", newState, noteID)
			if err != nil {
				tx.Rollback(ctx)
				log.Fatalf("Failed to update note_yjs_states: %v", err)
			}

			_, err = tx.Exec(ctx, "INSERT INTO note_yjs_updates (note_id, update_data) VALUES ($1, $2)", noteID, updateBytes)
			if err != nil {
				tx.Rollback(ctx)
				log.Fatalf("Failed to insert note_yjs_updates: %v", err)
			}

			if err := tx.Commit(ctx); err != nil {
				log.Fatalf("Failed to commit tx: %v", err)
			}

			log.Printf("Migrated note: %s", noteID)
			notesToMigrate = append(notesToMigrate, noteID)
		}
	}

	if err := rows.Err(); err != nil {
		log.Fatalf("Rows error: %v", err)
	}

	log.Printf("Migration complete. Migrated %d notes.", len(notesToMigrate))
}
