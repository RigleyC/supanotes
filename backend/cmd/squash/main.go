package main

import (
	"context"
	"encoding/json"
	"flag"
	"log"
	"os"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/reearth/ygo/crdt"

	"github.com/RigleyC/supanotes/internal/sync"
)

func main() {
	noteID := flag.String("note", "", "UUID of the note to squash")
	flag.Parse()

	if *noteID == "" {
		log.Fatal("Usage: squash -note <note_id>")
	}

	connStr := os.Getenv("DATABASE_URL")
	if connStr == "" {
		log.Fatal("DATABASE_URL is not set")
	}

	ctx := context.Background()
	pool, err := pgxpool.New(ctx, connStr)
	if err != nil {
		log.Fatalf("Unable to connect to database: %v\n", err)
	}
	defer pool.Close()

	// 1. Load bloated state
	log.Printf("Loading YDoc state for note %s...\n", *noteID)
	bloatedState, err := sync.LoadYDocState(ctx, pool, *noteID)
	if err != nil {
		log.Fatalf("Failed to load state: %v\n", err)
	}
	if len(bloatedState) == 0 {
		log.Fatalf("Note %s has no YDoc state to squash.\n", *noteID)
	}
	originalSize := len(bloatedState)
	log.Printf("Loaded bloated state: %d bytes (%.2f MB)\n", originalSize, float64(originalSize)/1024/1024)

	// 2. Decode bloated doc and extract nodes
	doc := crdt.New(crdt.WithGC(false))
	// Pre-register texts like Flutter's yjs_dart does to avoid missing roots
	sync.PreRegisterYText(doc, bloatedState) // Note: Need to export preRegisterYText or use standard
	if err := crdt.ApplyUpdateV1(doc, bloatedState, nil); err != nil {
		log.Fatalf("Failed to apply bloated state: %v\n", err)
	}

	nodes := sync.NodesFromDoc(doc)
	log.Printf("Extracted %d nodes from bloated state.\n", len(nodes))

	nodesMap := doc.GetMap("nodes")
	keys := nodesMap.Keys()
	if len(keys) > 0 {
		raw, _ := nodesMap.Get(keys[0])
		log.Printf("DEBUG: Found %d keys. Type of first key '%s' is %T\n", len(keys), keys[0], raw)
	} else {
		log.Printf("DEBUG: nodesMap has 0 keys.\n")
	}

	// 3. Create a clean doc
	cleanDoc := crdt.New(crdt.WithGC(true))
	cleanNodesMap := cleanDoc.GetMap("nodes")

	for _, n := range nodes {
		// Populate node in YMap
		nodeMap := make(map[string]any)
		nodeMap["id"] = n.ID
		nodeMap["type"] = n.Type
		nodeMap["position"] = n.Position
		if len(n.Data) > 0 {
			var dataObj any
			if err := json.Unmarshal(n.Data, &dataObj); err == nil {
				nodeMap["data"] = dataObj
			} else {
				nodeMap["data"] = string(n.Data)
			}
		}
		for k, v := range n.Metadata {
			nodeMap[k] = v
		}

		nodeJSON, _ := json.Marshal(nodeMap)

		cleanDoc.Transact(func(txn *crdt.Transaction) {
			cleanNodesMap.Set(txn, n.ID, string(nodeJSON))
			// Populate the canonical YText root. content_fixed is read-only
			// compatibility for states produced by older squash runs.
			if n.Text != "" {
				ytext := cleanDoc.GetText("content/" + n.ID)
				ytext.Insert(txn, 0, n.Text, nil)
			}
		})
	}

	// 4. Encode clean doc
	cleanState := crdt.EncodeStateAsUpdateV1(cleanDoc, nil)
	cleanSize := len(cleanState)
	log.Printf("Clean state encoded: %d bytes (%.2f KB)\n", cleanSize, float64(cleanSize)/1024)

	// 5. Transaction to replace state and delete updates
	tx, err := pool.Begin(ctx)
	if err != nil {
		log.Fatalf("Failed to begin transaction: %v\n", err)
	}
	defer tx.Rollback(ctx)

	// Update snapshot
	res, err := tx.Exec(ctx, "UPDATE note_yjs_states SET state = $1, updated_at = NOW() WHERE note_id = $2", cleanState, *noteID)
	if err != nil {
		log.Fatalf("Failed to update note_yjs_states: %v\n", err)
	}
	if res.RowsAffected() == 0 {
		log.Fatalf("No rows updated in note_yjs_states (note not found?)\n")
	}

	// Delete pending updates
	delRes, err := tx.Exec(ctx, "DELETE FROM note_yjs_updates WHERE note_id = $1", *noteID)
	if err != nil {
		log.Fatalf("Failed to delete note_yjs_updates: %v\n", err)
	}

	if err := tx.Commit(ctx); err != nil {
		log.Fatalf("Failed to commit transaction: %v\n", err)
	}

	log.Printf("Squash SUCCESS! Reduced size from %d bytes to %d bytes. Deleted %d pending updates.\n", originalSize, cleanSize, delRes.RowsAffected())
}
