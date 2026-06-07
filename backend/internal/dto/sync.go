package dto

type SyncNote struct {
	ID              string  `json:"id"`
	UserID          string  `json:"user_id"`
	ContextID       *string `json:"context_id,omitempty"`
	Title           *string `json:"title,omitempty"`
	Content         string  `json:"content"`
	Excerpt         *string `json:"excerpt,omitempty"`
	IsInbox         bool    `json:"is_inbox"`
	Favorite        bool    `json:"favorite"`
	Archived        bool    `json:"archived"`
	EmbeddingStatus string  `json:"embedding_status"`
	CreatedAt       string  `json:"created_at"`
	UpdatedAt       string  `json:"updated_at"`
	DeletedAt       *string `json:"deleted_at,omitempty"`
}

type SyncTask struct {
	ID         string  `json:"id"`
	NoteID     string  `json:"note_id"`
	UserID     string  `json:"user_id"`
	Title      string  `json:"title"`
	Status     string  `json:"status"`
	DueDate    *string `json:"due_date,omitempty"`
	Recurrence *string `json:"recurrence,omitempty"`
	Position   int     `json:"position"`
	CreatedAt  string  `json:"created_at"`
	UpdatedAt  string  `json:"updated_at"`
	DeletedAt  *string `json:"deleted_at,omitempty"`
}

type SyncContext struct {
	ID        string `json:"id"`
	UserID    string `json:"user_id"`
	Slug      string `json:"slug"`
	Name      string `json:"name"`
	CreatedAt string `json:"created_at"`
	UpdatedAt string `json:"updated_at"`
}

type SyncTag struct {
	ID        string `json:"id"`
	UserID    string `json:"user_id"`
	Name      string `json:"name"`
	CreatedAt string `json:"created_at"`
}

type SyncTaskCompletion struct {
	ID          string `json:"id"`
	TaskID      string `json:"task_id"`
	CompletedAt string `json:"completed_at"`
	Status      string `json:"status"`
}

type SyncPayload struct {
	Notes           []SyncNote           `json:"notes"`
	Tasks           []SyncTask           `json:"tasks"`
	Contexts        []SyncContext        `json:"contexts"`
	Tags            []SyncTag            `json:"tags"`
	TaskCompletions []SyncTaskCompletion `json:"task_completions"`
}
