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

	var total int
	err = conn.QueryRow(context.Background(), "SELECT count(*) FROM notes").Scan(&total)
	if err != nil {
		log.Fatal("Query error: ", err)
	}
	fmt.Printf("Total notes: %d\n", total)

	var ydocCount int
	err = conn.QueryRow(context.Background(), "SELECT count(*) FROM note_yjs_states").Scan(&ydocCount)
	if err != nil {
		log.Fatal("Query error: ", err)
	}
	fmt.Printf("Total ydocs: %d\n", ydocCount)
}
