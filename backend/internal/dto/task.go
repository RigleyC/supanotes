package dto

type TaskResponse struct {
	ID         string  `json:"id"`
	NoteID     string  `json:"note_id"`
	Title      string  `json:"title"`
	Status     string  `json:"status"`
	DueDate    *string `json:"due_date,omitempty"`
	Recurrence *string `json:"recurrence,omitempty"`
	Position   int     `json:"position"`
	CreatedAt  string  `json:"created_at"`
	UpdatedAt  string  `json:"updated_at"`
}
