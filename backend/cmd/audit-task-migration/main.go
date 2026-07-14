package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"

	"github.com/RigleyC/supanotes/internal/sync"
	"github.com/RigleyC/supanotes/pkg/config"
	"github.com/RigleyC/supanotes/pkg/db"
	"github.com/reearth/ygo/crdt"
)

type auditResult struct {
	NoteID     string
	TaskNodeID string
	Bucket     string // "clean" | "dual" | "legacy_only"
}

func main() {
	if err := run(); err != nil {
		log.Fatalf("error: %v", err)
	}
}

func run() error {
	ctx := context.Background()

	// Load config to get DB URL
	os.Setenv("ENVIRONMENT", "development")
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("load config: %w", err)
	}
	if cfg.DatabaseURL == "" {
		return fmt.Errorf("DATABASE_URL is empty")
	}

	// Connect to DB
	pool, err := db.Connect(ctx, cfg.DatabaseURL)
	if err != nil {
		return fmt.Errorf("connect db: %w", err)
	}
	defer pool.Close()

	// Get all distinct note IDs that have Yjs state or updates
	rows, err := pool.Query(ctx, `
		SELECT DISTINCT note_id::text FROM note_yjs_states
		UNION
		SELECT DISTINCT note_id::text FROM note_yjs_updates
	`)
	if err != nil {
		return fmt.Errorf("query note ids: %w", err)
	}
	defer rows.Close()

	var noteIDs []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return fmt.Errorf("scan note id: %w", err)
		}
		noteIDs = append(noteIDs, id)
	}

	fmt.Printf("Found %d notes to audit\n", len(noteIDs))

	cleanCount := 0
	dualCount := 0
	legacyOnlyCount := 0
	var legacyOnlyNotes []string

	for _, noteID := range noteIDs {
		state, err := sync.LoadYDocState(ctx, pool, noteID)
		if err != nil {
			log.Printf("Failed to load ydoc state for %s: %v", noteID, err)
			continue
		}
		if len(state) == 0 {
			continue
		}

		doc := crdt.New(crdt.WithGC(false))
		if err := crdt.ApplyUpdateV1(doc, state, nil); err != nil {
			log.Printf("Failed to apply ydoc state for %s: %v", noteID, err)
			continue
		}

		results := auditNote(noteID, doc)
		hasLegacyOnly := false
		for _, r := range results {
			switch r.Bucket {
			case "clean":
				cleanCount++
			case "dual":
				dualCount++
			case "legacy_only":
				legacyOnlyCount++
				hasLegacyOnly = true
			}
		}
		if hasLegacyOnly {
			legacyOnlyNotes = append(legacyOnlyNotes, noteID)
		}
	}

	fmt.Printf("\n--- Audit Results ---\n")
	fmt.Printf("clean: %d\n", cleanCount)
	fmt.Printf("dual: %d\n", dualCount)
	fmt.Printf("legacy_only: %d\n", legacyOnlyCount)

	if len(legacyOnlyNotes) > 0 {
		fmt.Printf("\nNotes with legacy_only tasks:\n")
		for _, id := range legacyOnlyNotes {
			fmt.Printf("- %s\n", id)
		}
	}

	return nil
}

func auditNote(noteID string, doc *crdt.Doc) []auditResult {
	var results []auditResult
	nodesMap := doc.GetMap("nodes")
	if nodesMap == nil {
		return results
	}
	tasksMap := doc.GetMap("tasks")

	for _, key := range nodesMap.Keys() {
		raw, ok := nodesMap.Get(key)
		if !ok {
			continue
		}
		rawStr, ok := raw.(string)
		if !ok {
			continue
		}

		var nd struct {
			Type string          `json:"type"`
			Data json.RawMessage `json:"data"`
		}
		if err := json.Unmarshal([]byte(rawStr), &nd); err != nil {
			continue
		}
		if nd.Type != "task" {
			continue
		}

		var dataFields map[string]any
		if err := json.Unmarshal(nd.Data, &dataFields); err != nil {
			continue
		}

		_, hasLegacyCompleted := dataFields["completed"]
		
		hasTaskEntry := false
		if tasksMap != nil {
			_, hasTaskEntry = tasksMap.Get(key)
		}

		bucket := "clean"
		switch {
		case hasLegacyCompleted && !hasTaskEntry:
			bucket = "legacy_only"
		case hasLegacyCompleted && hasTaskEntry:
			bucket = "dual"
		}
		
		results = append(results, auditResult{NoteID: noteID, TaskNodeID: key, Bucket: bucket})
	}
	return results
}
