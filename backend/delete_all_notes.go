package main

import (
	"context"
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

	// Delete states first due to foreign key constraints, though ON DELETE CASCADE might be on.
	_, err = conn.Exec(context.Background(), "DELETE FROM note_yjs_states")
	if err != nil {
		log.Fatal("Delete note_yjs_states error: ", err)
	}

	_, err = conn.Exec(context.Background(), "DELETE FROM notes")
	if err != nil {
		log.Fatal("Delete notes error: ", err)
	}

	log.Println("All notes and YDoc states have been removed from the database.")
}
