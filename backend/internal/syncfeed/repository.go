package syncfeed

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"
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
	Cursor    int64    `json:"cursor"`
	Watermark int64    `json:"watermark"`
	HasMore   bool     `json:"hasMore"`
	Changes   []Change `json:"changes"`
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
	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly})
	if err != nil {
		return Page{}, err
	}
	defer tx.Rollback(ctx)

	var watermark int64
	if err := tx.QueryRow(ctx, `
		SELECT GREATEST(COALESCE(MAX(sequence), 0), $2)
		FROM sync_changes
		WHERE target_user_id = $1
	`, userID, after).Scan(&watermark); err != nil {
		return Page{}, err
	}

	rows, err := tx.Query(ctx, `
		SELECT sequence, kind, COALESCE(note_id::text, ''), COALESCE(revision, 0), created_at
		FROM sync_changes
		WHERE target_user_id = $1
		  AND sequence > $2
		  AND sequence <= $3
		ORDER BY sequence ASC
		LIMIT $4
	`, userID, after, watermark, limit+1)
	if err != nil {
		return Page{}, err
	}

	changes := make([]Change, 0, limit+1)
	for rows.Next() {
		var change Change
		if err := rows.Scan(&change.Sequence, &change.Type, &change.NoteID, &change.Revision, &change.CreatedAt); err != nil {
			rows.Close()
			return Page{}, err
		}
		changes = append(changes, change)
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		return Page{}, err
	}
	rows.Close()

	if err := tx.Commit(ctx); err != nil {
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
	return Page{
		Cursor:    cursor,
		Watermark: watermark,
		HasMore:   hasMore,
		Changes:   changes,
	}, nil
}
