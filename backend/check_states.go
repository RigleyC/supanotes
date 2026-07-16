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

	var count int
	err = conn.QueryRow(context.Background(), "SELECT count(*) FROM note_yjs_states").Scan(&count)
	if err != nil {
		log.Fatal("Count error: ", err)
	}

	fmt.Printf("Count of note_yjs_states: %d\n", count)
}
