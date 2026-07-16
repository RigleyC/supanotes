package main

import (
	"bufio"
	"context"
	"fmt"
	"log"
	"os"
	"strings"

	"github.com/jackc/pgx/v5"
)

func main() {
	conn, err := pgx.Connect(context.Background(), os.Getenv("DATABASE_URL"))
	if err != nil {
		log.Fatal("Connect error: ", err)
	}
	defer conn.Close(context.Background())

	file, err := os.Open("backup.sql")
	if err != nil {
		log.Fatal(err)
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	// bufio.Scanner has a default max line size of 64KB, which might be too small for search_vector or large notes.
	// We'll increase the buffer size.
	buf := make([]byte, 0, 64*1024)
	scanner.Buffer(buf, 10*1024*1024)

	inNotesBlock := false
	restored := 0

	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "COPY public.notes ") {
			inNotesBlock = true
			continue
		}
		if inNotesBlock {
			if line == "\\." {
				break
			}
			parts := strings.Split(line, "\t")
			if len(parts) < 12 {
				continue
			}

			id := parts[0]
			userId := parts[1]
			
			// context_id
			var contextId *string
			if parts[2] != "\\N" {
				contextId = &parts[2]
			}
			
			// content
			content := strings.ReplaceAll(parts[3], "\\n", "\n")
			content = strings.ReplaceAll(content, "\\t", "\t")
			if parts[3] == "\\N" {
				content = ""
			}

			// excerpt
			excerpt := strings.ReplaceAll(parts[4], "\\n", "\n")
			if parts[4] == "\\N" {
				excerpt = ""
			}
			
			// search_vector
			searchVector := parts[6]
			
			createdAt := parts[7]
			updatedAt := parts[8]
			
			// We will forcefully RESTORE all notes by setting deleted_at to NULL if they are the deleted ones
			var deletedAtVal *string
			embStatus := parts[10]
			collapseImg := parts[11] == "t"

			_, err := conn.Exec(context.Background(), `
				INSERT INTO notes (
					id, user_id, context_id, content, excerpt, 
					search_vector, created_at, updated_at, deleted_at, 
					embedding_status, collapse_images
				) VALUES (
					$1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11
				) ON CONFLICT (id) DO NOTHING
			`, id, userId, contextId, content, excerpt, searchVector, createdAt, updatedAt, deletedAtVal, embStatus, collapseImg)

			if err != nil {
				log.Printf("Error inserting note %s: %v", id, err)
			} else {
				restored++
			}
		}
	}

	if err := scanner.Err(); err != nil {
		log.Fatal("Scanner error: ", err)
	}

	fmt.Printf("Restored %d notes (or they were already present).\n", restored)
}
