package main

import (
	"fmt"
	"log/slog"
	"net/http"
	"os"

	"github.com/RigleyC/supanotes/internal/handler"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	mux := http.NewServeMux()

	// Health check
	mux.HandleFunc("GET /api/v1/health", handler.Health)

	// Notes
	mux.HandleFunc("GET /api/v1/notes", handler.ListNotes)
	mux.HandleFunc("POST /api/v1/notes", handler.CreateNote)
	mux.HandleFunc("GET /api/v1/notes/{id}", handler.GetNote)
	mux.HandleFunc("PUT /api/v1/notes/{id}", handler.UpdateNote)
	mux.HandleFunc("DELETE /api/v1/notes/{id}", handler.DeleteNote)

	addr := fmt.Sprintf(":%s", port)
	slog.Info("SupaNotes backend starting", "addr", addr)

	if err := http.ListenAndServe(addr, mux); err != nil {
		slog.Error("server failed", "err", err)
		os.Exit(1)
	}
}
