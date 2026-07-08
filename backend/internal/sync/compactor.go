package sync

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"sync"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/reearth/ygo/crdt"
)

type debounceState struct {
	timer   *time.Timer
	skipSeq int
}

type Compactor struct {
	pool       *pgxpool.Pool
	debounce   map[string]*debounceState
	debounceMu sync.Mutex
}

func NewCompactor(pool *pgxpool.Pool) *Compactor {
	return &Compactor{
		pool:     pool,
		debounce: make(map[string]*debounceState),
	}
}

func (c *Compactor) RunDebouncedProjection(ctx context.Context, noteID string) {
	c.debounceMu.Lock()
	defer c.debounceMu.Unlock()
	st := c.debounce[noteID]
	if st == nil {
		st = &debounceState{}
		c.debounce[noteID] = st
	}
	if st.timer != nil {
		st.timer.Stop()
	}
	st.skipSeq++
	seq := st.skipSeq
	st.timer = time.AfterFunc(500*time.Millisecond, func() {
		c.debounceMu.Lock()
		if cur := c.debounce[noteID]; cur == nil || cur.skipSeq != seq {
			c.debounceMu.Unlock()
			return
		}
		c.debounceMu.Unlock()
		_ = c.projectCanonicalDoc(ctx, noteID)
	})
}

func (c *Compactor) RunDebouncedProjectionForTest(ctx context.Context, svc *YDocService, noteID string, update []byte) error {
	if err := svc.ApplyNodeMutation(ctx, noteID, update); err != nil {
		return err
	}
	return c.projectCanonicalDoc(ctx, noteID)
}

func (c *Compactor) projectCanonicalDoc(ctx context.Context, noteID string) error {
	state, err := LoadYDocState(ctx, c.pool, noteID)
	if err != nil {
		return err
	}
	if len(state) == 0 {
		return nil
	}
	doc := crdt.New(crdt.WithGC(false))
	if err := crdt.ApplyUpdateV1(doc, state, nil); err != nil {
		return err
	}

	tx, err := c.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	if _, err := tx.Exec(ctx, "SELECT pg_advisory_xact_lock(hashtext($1::text), hashtext('nodes'))", noteID); err != nil {
		return err
	}
	if err := ProjectToDBTxFromDoc(ctx, tx, doc, noteID); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func (c *Compactor) CompactNote(ctx context.Context, noteID string) error {
	tx, err := c.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx, "SELECT pg_advisory_xact_lock(hashtext($1::text), hashtext('nodes'))", noteID); err != nil {
		return fmt.Errorf("advisory lock: %w", err)
	}

	var existingState []byte
	if err := tx.QueryRow(ctx, "SELECT state FROM note_yjs_states WHERE note_id = $1", noteID).Scan(&existingState); err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return fmt.Errorf("query existing state: %w", err)
	}

	rows, err := tx.Query(ctx, "SELECT update_data FROM note_yjs_updates WHERE note_id = $1 ORDER BY created_at ASC", noteID)
	if err != nil {
		return fmt.Errorf("query updates: %w", err)
	}
	var allUpdates [][]byte
	for rows.Next() {
		var u []byte
		if err := rows.Scan(&u); err != nil {
			rows.Close()
			return fmt.Errorf("scan update: %w", err)
		}
		allUpdates = append(allUpdates, u)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return fmt.Errorf("rows iter: %w", err)
	}

	if len(allUpdates) == 0 && existingState == nil {
		return nil
	}

	parts := make([][]byte, 0, len(allUpdates)+1)
	if existingState != nil {
		parts = append(parts, existingState)
	}
	parts = append(parts, allUpdates...)
	merged, err := crdt.MergeUpdatesV1(parts...)
	if err != nil {
		return fmt.Errorf("merge updates: %w", err)
	}

	// PROJECT FROM THE FULL DOC STATE — not from the partial update.
	doc := crdt.New(crdt.WithGC(false))
	if err := crdt.ApplyUpdateV1(doc, merged, nil); err != nil {
		return fmt.Errorf("apply merged state for projection: %w", err)
	}
	if err := projectDocToDB(ctx, tx, doc, noteID); err != nil {
		// Abort; do NOT persist snapshot or delete updates.
		return fmt.Errorf("project during compaction: %w", err)
	}

	if _, err := tx.Exec(ctx, `
		INSERT INTO note_yjs_states (note_id, state, updated_at)
		VALUES ($1, $2, NOW())
		ON CONFLICT (note_id) DO UPDATE
		SET state = EXCLUDED.state, updated_at = NOW()
	`, noteID, merged); err != nil {
		return fmt.Errorf("upsert state: %w", err)
	}

	if _, err := tx.Exec(ctx, "DELETE FROM note_yjs_updates WHERE note_id = $1", noteID); err != nil {
		return fmt.Errorf("delete compacted updates: %w", err)
	}

	// 30-day retention safety: prune any stragglers from orphaned failures.
	if _, err := tx.Exec(ctx, "DELETE FROM note_yjs_updates WHERE note_id = $1 AND created_at < NOW() - INTERVAL '30 days'", noteID); err != nil {
		return fmt.Errorf("prune old updates: %w", err)
	}

	return tx.Commit(ctx)
}

func (c *Compactor) CompactAll(ctx context.Context) error {
	rows, err := c.pool.Query(ctx, "SELECT DISTINCT note_id FROM note_yjs_updates")
	if err != nil {
		return fmt.Errorf("query distinct note_ids: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var noteID string
		if err := rows.Scan(&noteID); err != nil {
			return fmt.Errorf("scan note_id: %w", err)
		}
		if err := c.CompactNote(ctx, noteID); err != nil {
			slog.Error("compact note", "note_id", noteID, "error", err)
		}
	}
	return rows.Err()
}

func (c *Compactor) StartScheduler(ctx context.Context, interval time.Duration) {
	go func() {
		ticker := time.NewTicker(interval)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				if err := c.CompactAll(ctx); err != nil {
					slog.Error("compaction run failed", "error", err)
				}
			}
		}
	}()
}
