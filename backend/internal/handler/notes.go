package handler

import (
	"encoding/json"
	"net/http"
)

// Note represents a single note (stub model).
type Note struct {
	ID      string `json:"id"`
	Title   string `json:"title"`
	Content string `json:"content"`
}

// ListNotes handles GET /api/v1/notes
func ListNotes(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	// TODO: query database
	json.NewEncoder(w).Encode([]Note{})
}

// CreateNote handles POST /api/v1/notes
func CreateNote(w http.ResponseWriter, r *http.Request) {
	var note Note
	if err := json.NewDecoder(r.Body).Decode(&note); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}
	// TODO: persist to database
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(note)
}

// GetNote handles GET /api/v1/notes/{id}
func GetNote(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	// TODO: fetch from database
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(Note{ID: id})
}

// UpdateNote handles PUT /api/v1/notes/{id}
func UpdateNote(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	var note Note
	if err := json.NewDecoder(r.Body).Decode(&note); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}
	note.ID = id
	// TODO: update in database
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(note)
}

// DeleteNote handles DELETE /api/v1/notes/{id}
func DeleteNote(w http.ResponseWriter, r *http.Request) {
	// id := r.PathValue("id")
	// TODO: delete from database
	w.WriteHeader(http.StatusNoContent)
}
