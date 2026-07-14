//go:build ignore

package main

import (
	"context"
	"fmt"
	"os"

	"github.com/jackc/pgx/v5"
)

func main() {
	url := "postgres://postgres:4yfVB4Dn5oZV9Ai@localhost:5432/backend_winter_waterfall_5807?sslmode=disable"
	conn, err := pgx.Connect(context.Background(), url)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Unable to connect to database: %v\n", err)
		os.Exit(1)
	}
	defer conn.Close(context.Background())

	var name string
	err = conn.QueryRow(context.Background(), "SELECT current_database()").Scan(&name)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Query failed: %v\n", err)
		os.Exit(1)
	}

	fmt.Println("Connected to database:", name)
}
