package dto

type SearchResult struct {
	ID        string  `json:"id"`
	Title     *string `json:"title,omitempty"`
	Content   string  `json:"content"`
	Excerpt   *string `json:"excerpt,omitempty"`
	ContextID *string `json:"context_id,omitempty"`
	Favorite  bool    `json:"favorite"`
	Archived  bool    `json:"archived"`
	Score     float64 `json:"score"`
	UpdatedAt string  `json:"updated_at"`
}
