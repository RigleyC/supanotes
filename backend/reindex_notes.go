package main

import (
	"context"
	"fmt"
	"os"

	"github.com/jackc/pgx/v5"
	"github.com/RigleyC/supanotes/internal/utils"
)

func main() {
	url := "postgres://postgres:4yfVB4Dn5oZV9Ai@localhost:5432/backend_winter_waterfall_5807?sslmode=disable"
	ctx := context.Background()
	conn, err := pgx.Connect(ctx, url)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Unable to connect: %v\n", err)
		os.Exit(1)
	}
	defer conn.Close(ctx)

	rows, err := conn.Query(ctx, "SELECT DISTINCT note_id FROM note_nodes")
	if err != nil {
		fmt.Fprintf(os.Stderr, "Query failed: %v\n", err)
		os.Exit(1)
	}
	
	var noteIDs []string
	for rows.Next() {
		var id string
		rows.Scan(&id)
		noteIDs = append(noteIDs, id)
	}
	rows.Close()

	for _, noteID := range noteIDs {
		// Sort by casting to float8 so "10" comes after "2"
		nodeRows, err := conn.Query(ctx, "SELECT id FROM note_nodes WHERE note_id = $1 ORDER BY position::float8 ASC", noteID)
		if err != nil {
			fmt.Printf("Error querying nodes for note %s: %v\n", noteID, err)
			continue
		}
		
		var nodeIDs []string
		for nodeRows.Next() {
			var id string
			nodeRows.Scan(&id)
			nodeIDs = append(nodeIDs, id)
		}
		nodeRows.Close()

		var prev string
		for _, nodeID := range nodeIDs {
			newPos, err := utils.GenerateKeyBetween(prev, "")
			if err != nil {
				fmt.Printf("Error generating key for %s: %v\n", nodeID, err)
				continue
			}
			_, err = conn.Exec(ctx, "UPDATE note_nodes SET position = $1 WHERE id = $2", newPos, nodeID)
			if err != nil {
				fmt.Printf("Error updating node %s: %v\n", nodeID, err)
			}
			// Also update tasks if it's a task
			_, _ = conn.Exec(ctx, "UPDATE tasks SET position = $1 WHERE node_id = $2", newPos, nodeID)
			
			prev = newPos
		}
		fmt.Printf("Re-indexed %d nodes for note %s\n", len(nodeIDs), noteID)
	}
	
	fmt.Println("Done!")
}
