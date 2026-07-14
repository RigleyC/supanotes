package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/reearth/ygo/crdt"

	"github.com/RigleyC/supanotes/internal/sync"
	"github.com/RigleyC/supanotes/pkg/config"
	"github.com/RigleyC/supanotes/pkg/db"
)

type backupEntry struct {
	NoteID  string
	State   []byte
	Updates [][]byte
}

func main() {
	if err := run(); err != nil {
		log.Fatalf("error: %v", err)
	}
}

func run() error {
	ctx := context.Background()

	os.Setenv("ENVIRONMENT", "development")
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("load config: %w", err)
	}

	pool, err := db.Connect(ctx, cfg.DatabaseURL)
	if err != nil {
		return fmt.Errorf("connect db: %w", err)
	}
	defer pool.Close()

	// 1. Audit to get notes
	rows, err := pool.Query(ctx, `
		SELECT DISTINCT note_id::text FROM note_yjs_states
		UNION
		SELECT DISTINCT note_id::text FROM note_yjs_updates
	`)
	if err != nil {
		return fmt.Errorf("query note ids: %w", err)
	}

	var allNoteIDs []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			rows.Close()
			return fmt.Errorf("scan note id: %w", err)
		}
		allNoteIDs = append(allNoteIDs, id)
	}
	rows.Close()

	var targetNoteIDs []string
	for _, noteID := range allNoteIDs {
		state, err := sync.LoadYDocState(ctx, pool, noteID)
		if err != nil || len(state) == 0 {
			continue
		}
		doc := crdt.New(crdt.WithGC(false))
		if err := crdt.ApplyUpdateV1(doc, state, nil); err != nil {
			continue
		}
		if needsMigration(doc) {
			targetNoteIDs = append(targetNoteIDs, noteID)
		}
	}

	if len(targetNoteIDs) == 0 {
		fmt.Println("No notes need migration.")
		return nil
	}

	fmt.Printf("Found %d notes to migrate: %v\n", len(targetNoteIDs), targetNoteIDs)

	// 2. Backup & Migrate within a transaction with advisory lock
	var backups []backupEntry

	for _, noteID := range targetNoteIDs {
		if err := migrateNote(ctx, pool, noteID, &backups); err != nil {
			return fmt.Errorf("failed to migrate note %s: %w", noteID, err)
		}
	}

	// Save backup
	b, _ := json.MarshalIndent(backups, "", "  ")
	if err := os.WriteFile("migration_backup.json", b, 0644); err != nil {
		log.Printf("Warning: failed to write backup file: %v", err)
	} else {
		fmt.Println("Backup saved to migration_backup.json")
	}

	fmt.Println("Migration complete!")
	return nil
}

func needsMigration(doc *crdt.Doc) bool {
	nodesMap := doc.GetMap("nodes")
	if nodesMap == nil {
		return false
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
		if hasLegacyCompleted && !hasTaskEntry {
			return true
		}
	}
	return false
}

func migrateNote(ctx context.Context, pool *pgxpool.Pool, noteID string, backups *[]backupEntry) error {
	tx, err := pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	// Get advisory lock
	if _, err := tx.Exec(ctx, "SELECT pg_advisory_xact_lock(hashtext($1::text), hashtext('nodes'))", noteID); err != nil {
		return fmt.Errorf("advisory lock: %w", err)
	}

	// Backup current state
	noteUUID := uuid.MustParse(noteID)
	var state []byte
	err = tx.QueryRow(ctx, "SELECT state FROM note_yjs_states WHERE note_id = $1", noteUUID).Scan(&state)
	if err != nil && err != pgx.ErrNoRows {
		return fmt.Errorf("query state: %w", err)
	}

	rows, err := tx.Query(ctx, "SELECT update_data FROM note_yjs_updates WHERE note_id = $1 ORDER BY created_at ASC", noteUUID)
	if err != nil {
		return fmt.Errorf("query updates: %w", err)
	}
	var updates [][]byte
	for rows.Next() {
		var u []byte
		if err := rows.Scan(&u); err != nil {
			rows.Close()
			return fmt.Errorf("scan update: %w", err)
		}
		updates = append(updates, u)
	}
	rows.Close()

	*backups = append(*backups, backupEntry{NoteID: noteID, State: state, Updates: updates})

	// Merge manually to apply correctly
	var all [][]byte
	if len(state) > 0 {
		all = append(all, state)
	}
	all = append(all, updates...)
	merged, err := crdt.MergeUpdatesV1(all...)
	if err != nil {
		return fmt.Errorf("merge updates: %w", err)
	}

	doc := crdt.New(crdt.WithGC(false))
	if err := crdt.ApplyUpdateV1(doc, merged, nil); err != nil {
		return fmt.Errorf("apply merged: %w", err)
	}

	// Migrate
	sync.MigrateLegacyDoc(doc)

	// Get new state
	newState := crdt.EncodeStateAsUpdateV1(doc, nil)

	// Persist
	if len(state) > 0 {
		if _, err := tx.Exec(ctx, "UPDATE note_yjs_states SET state = $1 WHERE note_id = $2", newState, noteUUID); err != nil {
			return fmt.Errorf("update state: %w", err)
		}
	} else {
		if _, err := tx.Exec(ctx, "INSERT INTO note_yjs_states (note_id, state) VALUES ($1, $2)", noteUUID, newState); err != nil {
			return fmt.Errorf("insert state: %w", err)
		}
	}

	if _, err := tx.Exec(ctx, "DELETE FROM note_yjs_updates WHERE note_id = $1", noteUUID); err != nil {
		return fmt.Errorf("delete updates: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit tx: %w", err)
	}

	fmt.Printf("Migrated note %s\n", noteID)
	return nil
}
