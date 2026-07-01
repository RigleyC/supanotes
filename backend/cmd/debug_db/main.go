package main

import (
	"context"
	"fmt"
	"log"
	"os"

	"github.com/jackc/pgx/v5/pgxpool"
)

func main() {
	ctx := context.Background()
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		dbURL = "postgres://backend_winter_waterfall_5807:BpXimItNqgwcS1i@localhost:5433/backend_winter_waterfall_5807?sslmode=disable"
	}

	pool, err := pgxpool.New(ctx, dbURL)
	if err != nil {
		log.Fatalf("connect to database: %v", err)
	}
	defer pool.Close()

	// Find notes where the first node has the title text
	rows, err := pool.Query(ctx, `
		SELECT n.id, n.content 
		FROM notes n
		JOIN note_nodes nn ON nn.note_id = n.id
		WHERE nn.position = 0 
		AND (nn.data->>'text' ILIKE '%midia%' OR nn.data->>'text' ILIKE '%mídia%' OR nn.data->>'text' ILIKE '%mensagem%' OR nn.data->>'text' ILIKE '%mercado%')
	`)
	if err != nil {
		log.Fatalf("query: %v", err)
	}
	defer rows.Close()

	for rows.Next() {
		var id, content string
		if err := rows.Scan(&id, &content); err != nil {
			log.Fatalf("scan: %v", err)
		}
		fmt.Printf("Note ID: %s (ContentLen: %d)\n", id, len(content))
		
		nodeRows, err := pool.Query(ctx, "SELECT id, type, data, position FROM note_nodes WHERE note_id = $1 AND deleted_at IS NULL ORDER BY position", id)
		if err != nil {
			log.Fatalf("query nodes: %v", err)
		}
		for nodeRows.Next() {
			var nId, nType string
			var nData []byte
			var pos int
			if err := nodeRows.Scan(&nId, &nType, &nData, &pos); err != nil {
				log.Fatalf("scan node: %v", err)
			}
			fmt.Printf("  Node[%d] %s: %s (ID: %s)\n", pos, nType, string(nData), nId)
		}
		nodeRows.Close()
	}
}
