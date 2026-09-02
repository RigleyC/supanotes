package syncfeed

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Change struct {
	Sequence  int64     `json:"sequence"`
	Type      string    `json:"type"`
	NoteID    string    `json:"noteId,omitempty"`
	Revision  int64     `json:"revision,omitempty"`
	CreatedAt time.Time `json:"createdAt"`
}

type Page struct {
	Cursor  int64    `json:"cursor"`
	HasMore bool     `json:"hasMore"`
	Changes []Change `json:"changes"`
}

type ChangeReader interface {
	ListChanges(ctx context.Context, userID pgtype.UUID, after int64, limit int) (Page, error)
}

type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

func (r *Repository) ListChanges(ctx context.Context, userID pgtype.UUID, after int64, limit int) (Page, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT sequence, kind, COALESCE(note_id::text, ''), COALESCE(revision, 0), created_at
		FROM sync_changes
		WHERE target_user_id = $1 AND sequence > $2
		ORDER BY sequence ASC
		LIMIT $3
	`, userID, after, limit+1)
	if err != nil {
		return Page{}, err
	}
	defer rows.Close()

	changes := make([]Change, 0, limit+1)
	for rows.Next() {
		var change Change
		if err := rows.Scan(&change.Sequence, &change.Type, &change.NoteID, &change.Revision, &change.CreatedAt); err != nil {
			return Page{}, err
		}
		changes = append(changes, change)
	}
	if err := rows.Err(); err != nil {
		return Page{}, err
	}

	hasMore := len(changes) > limit
	if hasMore {
		changes = changes[:limit]
	}
	cursor := after
	if len(changes) > 0 {
		cursor = changes[len(changes)-1].Sequence
	}
	return Page{Cursor: cursor, HasMore: hasMore, Changes: changes}, nil
}
