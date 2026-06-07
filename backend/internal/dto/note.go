package dto

type NoteResponse struct {
	ID        string  `json:"id"`
	ContextID *string `json:"context_id,omitempty"`
	Title     *string `json:"title,omitempty"`
	Content   string  `json:"content"`
	Excerpt   *string `json:"excerpt,omitempty"`
	IsInbox   bool    `json:"is_inbox"`
	Favorite  bool    `json:"favorite"`
	Archived  bool    `json:"archived"`
	CreatedAt string  `json:"created_at"`
	UpdatedAt string  `json:"updated_at"`
}
