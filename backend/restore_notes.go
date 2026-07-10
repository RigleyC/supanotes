package main

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/jackc/pgx/v5"
)

func restoreTable(ctx context.Context, conn *pgx.Conn, filePath string, tableName string, copyPrefix string) error {
	f, err := os.Open(filePath)
	if err != nil {
		return err
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	// We need a large buffer for long lines (e.g. Yjs states)
	buf := make([]byte, 0, 64*1024)
	scanner.Buffer(buf, 1024*1024*10)

	found := false
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, copyPrefix) {
			found = true
			break
		}
	}

	if !found {
		return fmt.Errorf("COPY command for %s not found", tableName)
	}

	r, w := io.Pipe()

	go func() {
		defer w.Close()
		for scanner.Scan() {
			line := scanner.Text()
			if line == "\\." {
				break
			}
			w.Write([]byte(line + "\n"))
		}
		if err := scanner.Err(); err != nil {
			fmt.Printf("Scanner error: %v\n", err)
		}
	}()

	// The copy prefix looks like: COPY public.notes (id, user_id, ...) FROM stdin;
	// PgConn().CopyFrom expects just the query
	res, err := conn.PgConn().CopyFrom(ctx, r, copyPrefix)
	if err != nil {
		return fmt.Errorf("CopyFrom failed: %w", err)
	}

	fmt.Printf("Restored %d rows to %s\n", res.RowsAffected(), tableName)
	return nil
}

func main() {
	url := "postgres://postgres:4yfVB4Dn5oZV9Ai@localhost:5432/backend_winter_waterfall_5807?sslmode=disable"
	ctx := context.Background()
	conn, err := pgx.Connect(ctx, url)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Unable to connect: %v\n", err)
		os.Exit(1)
	}
	defer conn.Close(ctx)

	tables := []string{"note_shares", "note_tags", "tasks", "note_nodes", "note_links", "notes"}
	for _, t := range tables {
		_, err := conn.Exec(ctx, "TRUNCATE public."+t+" CASCADE")
		if err != nil {
			fmt.Printf("Warning truncating %s: %v\n", t, err)
		} else {
			fmt.Printf("Truncated %s\n", t)
		}
	}

	_, err = conn.Exec(ctx, "ALTER TABLE public.notes ADD COLUMN is_inbox BOOLEAN DEFAULT false;")
	if err != nil {
		fmt.Printf("Warning adding is_inbox: %v\n", err)
	}

	// Restore in order
	targets := []struct {
		table  string
		prefix string
	}{
		{"notes", "COPY public.notes (id, user_id, context_id, content, excerpt, is_inbox, search_vector, created_at, updated_at, deleted_at, embedding_status, collapse_images) FROM stdin;"},
		{"note_nodes", "COPY public.note_nodes (id, note_id, parent_id, \"position\", type, data, created_at, updated_at, deleted_at) FROM stdin;"},
		{"tasks", "COPY public.tasks (id, note_id, user_id, title, status, due_date, recurrence, \"position\", created_at, updated_at, deleted_at, completed_at, node_id) FROM stdin;"},
		{"note_tags", "COPY public.note_tags (note_id, tag_id) FROM stdin;"},
		{"note_shares", "COPY public.note_shares (id, note_id, user_id, permission, created_at, updated_at) FROM stdin;"},
	}

	for _, tgt := range targets {
		err := restoreTable(ctx, conn, "backup.sql", tgt.table, tgt.prefix)
		if err != nil {
			fmt.Printf("Error restoring %s: %v\n", tgt.table, err)
		}
	}

	_, err = conn.Exec(ctx, "ALTER TABLE public.notes DROP COLUMN is_inbox;")
	if err != nil {
		fmt.Printf("Warning dropping is_inbox: %v\n", err)
	}
}
