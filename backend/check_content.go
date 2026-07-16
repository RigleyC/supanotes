package main

import (
	"context"
	"fmt"
	"log"
	"os"

	"github.com/jackc/pgx/v5"
)

func main() {
	conn, err := pgx.Connect(context.Background(), os.Getenv("DATABASE_URL"))
	if err != nil {
		log.Fatal("Connect error: ", err)
	}
	defer conn.Close(context.Background())

	rows, err := conn.Query(context.Background(), "SELECT id, content::text FROM notes WHERE content IS NOT NULL LIMIT 5")
	if err != nil {
		log.Fatal("Query error: ", err)
	}
	defer rows.Close()

	for rows.Next() {
		var id string
		var content string
		if err := rows.Scan(&id, &content); err != nil {
			log.Fatal(err)
		}
		fmt.Printf("Note %s:\n%s\n---\n", id, content)
	}
}
