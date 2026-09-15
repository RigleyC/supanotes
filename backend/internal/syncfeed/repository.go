package syncfeed

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Change struct {
	Sequence  int64     `json:"sequence"`
	Type      string    `json:"type"`
	NoteID    string    `json:"noteId,omitempty"`
	TaskID    string    `json:"taskId,omitempty"`
	Revision  int64     `json:"revision,omitempty"`
	CreatedAt time.Time `json:"createdAt"`
}

type Scope string

const (
	ScopeNotes Scope = "notes"
	ScopeAll   Scope = "all"
)

type Page struct {
	Cursor    int64    `json:"cursor"`
	Watermark int64    `json:"watermark"`
	HasMore   bool     `json:"hasMore"`
	Changes   []Change `json:"changes"`
}

type ChangeReader interface {
	ListChanges(ctx context.Context, userID pgtype.UUID, after int64, limit int, scope Scope) (Page, error)
}

type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

func (r *Repository) ListChanges(ctx context.Context, userID pgtype.UUID, after int64, limit int, scope Scope) (Page, error) {
	if scope != ScopeNotes && scope != ScopeAll {
		return Page{}, fmt.Errorf("invalid sync feed scope %q", scope)
	}
	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly})
	if err != nil {
		return Page{}, err
	}
	defer tx.Rollback(ctx)

	filter := ""
	if scope == ScopeNotes {
		// The default is deliberately note-only so clients predating task events
		// never receive an unknown kind without a taskId-aware coordinator.
		filter = " AND task_id IS NULL"
	}
	var watermark int64
	watermarkQuery := `
		SELECT GREATEST(COALESCE(MAX(sequence), 0), $2)
		FROM sync_changes
		WHERE target_user_id = $1` + filter
	if err := tx.QueryRow(ctx, watermarkQuery, userID, after).Scan(&watermark); err != nil {
		return Page{}, err
	}

	rows, err := tx.Query(ctx, `
		SELECT sequence, kind, COALESCE(note_id::text, ''), COALESCE(task_id::text, ''), COALESCE(revision, 0), created_at
		FROM sync_changes
		WHERE target_user_id = $1
		`+filter+`
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
		if err := rows.Scan(&change.Sequence, &change.Type, &change.NoteID, &change.TaskID, &change.Revision, &change.CreatedAt); err != nil {
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
