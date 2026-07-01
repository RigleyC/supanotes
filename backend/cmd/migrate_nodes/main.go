package main

import (
	"context"
	"encoding/json"
	"log"
	"os"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

func main() {
	ctx := context.Background()
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		log.Fatal("DATABASE_URL environment variable is required")
	}

	pool, err := pgxpool.New(ctx, dbURL)
	if err != nil {
		log.Fatalf("connect to database: %v", err)
	}
	defer pool.Close()

	q := sqlcgen.New(pool)

	notes, err := q.GetAllNotesForMigration(ctx)
	if err != nil {
		log.Fatalf("get notes: %v", err)
	}

	totalNodes := 0
	for _, note := range notes {
		content := note.Content
		if strings.TrimSpace(content) == "" {
			continue
		}

		lines := strings.Split(content, "\n")
		for i, line := range lines {
			trimmed := strings.TrimSpace(line)
			if trimmed == "" {
				continue
			}

			nodeType := "paragraph"
			if strings.HasPrefix(trimmed, "- [") {
				nodeType = "task"
			}

			data, _ := json.Marshal(map[string]string{
				"text": trimmed,
			})

			newUUID := uuid.New()
			_, err := q.InsertNode(ctx, sqlcgen.InsertNodeParams{
				ID:       pgtype.UUID{Bytes: newUUID, Valid: true},
				NoteID:   note.ID,
				Position: int32(i),
				Type:     nodeType,
				Data:     data,
			})
			if err != nil {
				log.Printf("error inserting node for note %s: %v", note.ID, err)
				continue
			}
			totalNodes++
		}
	}

	log.Printf("Migration complete: %d nodes created across %d notes", totalNodes, len(notes))
}
