package main

import (
	"context"
	"log"
	"os"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/notes"
)

func main() {
	ctx := context.Background()
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		dbURL = "postgres://supanotes:supanotes@localhost:5432/supanotes?sslmode=disable"
	}

	pool, err := pgxpool.New(ctx, dbURL)
	if err != nil {
		log.Fatalf("connect to database: %v", err)
	}
	defer pool.Close()

	q := sqlcgen.New(pool)

	dbNotes, err := q.GetAllNotesForMigration(ctx)
	if err != nil {
		log.Fatalf("get notes: %v", err)
	}

	totalNodes := 0
	for _, note := range dbNotes {
		content := note.Content
		if strings.TrimSpace(content) == "" {
			continue
		}

		parsedNodes := notes.ParseMarkdownToNodes(content)

		// Fetch existing tasks for this note
		rows, err := pool.Query(ctx, "SELECT id, title FROM tasks WHERE note_id = $1 AND deleted_at IS NULL", note.ID)
		var dbTasks []struct {
			ID    uuid.UUID
			Title string
		}
		if err == nil {
			for rows.Next() {
				var id uuid.UUID
				var title string
				if err := rows.Scan(&id, &title); err == nil {
					dbTasks = append(dbTasks, struct {
						ID    uuid.UUID
						Title string
					}{id, title})
				}
			}
			rows.Close()
		}

		for i, node := range parsedNodes {
			_, err := q.InsertNode(ctx, sqlcgen.InsertNodeParams{
				ID:       node.ID,
				NoteID:   note.ID,
				Position: int32(i),
				Type:     node.Type,
				Data:     node.Data,
			})
			if err != nil {
				log.Printf("error inserting node for note %v: %v", note.ID, err)
				continue
			}

			// Link existing tasks to the new task nodes by matching title
			if node.IsTask {
				for _, t := range dbTasks {
					if strings.TrimSpace(t.Title) == strings.TrimSpace(node.Text) {
						var nodeUUID uuid.UUID
						copy(nodeUUID[:], node.ID.Bytes[:])
						_, _ = pool.Exec(ctx, "UPDATE tasks SET node_id = $1 WHERE id = $2", nodeUUID, t.ID)
						break
					}
				}
			}
			totalNodes++
		}

		// Clear note content since we migrated it to nodes!
		_, _ = pool.Exec(ctx, "UPDATE notes SET content = '' WHERE id = $1", note.ID)
	}

	log.Printf("Migration complete: %d nodes created across %d notes", totalNodes, len(dbNotes))
}
