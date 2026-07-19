package sync

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"sync"
	"sync/atomic"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/reearth/ygo/crdt"
)

// debounceState tracks the pending debounce timer for a single note.
// seq is a monotonically increasing sequence number that lets the timer
// callback verify it is still the current entry before deleting.
type debounceState struct {
	timer *time.Timer
	seq   uint64
}

type Compactor struct {
	pool       *pgxpool.Pool
	debounce   map[string]*debounceState
	debounceMu sync.Mutex
	nextSeq    atomic.Uint64

	ctx    context.Context
	cancel context.CancelFunc
}

func NewCompactor(pool *pgxpool.Pool) *Compactor {
	ctx, cancel := context.WithCancel(context.Background())
	return &Compactor{
		pool:     pool,
		debounce: make(map[string]*debounceState),
		ctx:      ctx,
		cancel:   cancel,
	}
}

// Close stops all pending debounce timers and cancels the compactor context.
// Idempotent — safe to call multiple times.
func (c *Compactor) Close() error {
	c.cancel()
	c.debounceMu.Lock()
	defer c.debounceMu.Unlock()
	for _, st := range c.debounce {
		if st.timer != nil {
			st.timer.Stop()
		}
	}
	c.debounce = make(map[string]*debounceState)
	return nil
}

func (c *Compactor) RunDebouncedProjection(ctx context.Context, noteID string) {
	c.debounceMu.Lock()
	st := c.debounce[noteID]
	if st == nil {
		st = &debounceState{}
		c.debounce[noteID] = st
	}
	if st.timer != nil {
		st.timer.Stop()
	}
	// Assign a unique sequence number so the timer callback can check
	// whether another call has superseded it before deleting the entry.
	// This is necessary because Timer.Stop() returns false if the
	// callback has already started executing — in that case the old
	// callback must not delete the entry created by a newer call.
	seq := c.nextSeq.Add(1)
	st.seq = seq
	st.timer = time.AfterFunc(500*time.Millisecond, func() {
		c.debounceMu.Lock()
		// Validate seq BEFORE the projection. If a newer call already
		// replaced this timer, skip the projection entirely — it would
		// use stale state and waste I/O.
		if cur := c.debounce[noteID]; cur == nil || cur.seq != seq {
			c.debounceMu.Unlock()
			return
		}
		c.debounceMu.Unlock()

		_ = ProjectNoteContentFromYDoc(c.ctx, c.pool, noteID)

		// Clean up only if we're still the current entry.
		c.debounceMu.Lock()
		if cur := c.debounce[noteID]; cur != nil && cur.seq == seq {
			delete(c.debounce, noteID)
		}
		c.debounceMu.Unlock()
	})
	c.debounceMu.Unlock()
}

func (c *Compactor) ProjectCanonicalDoc(ctx context.Context, noteID string) error {
	return ProjectNoteContentFromYDoc(ctx, c.pool, noteID)
}

func (c *Compactor) RunDebouncedProjectionForTest(ctx context.Context, svc *YDocService, noteID string, update []byte) error {
	if err := svc.ApplyNodeMutation(ctx, noteID, update); err != nil {
		return err
	}
	return ProjectNoteContentFromYDoc(ctx, c.pool, noteID)
}

func (c *Compactor) CompactNote(ctx context.Context, noteID string) error {
	startTotal := time.Now()
	slog.Info("CompactNote: starting", "note_id", noteID)

	startTx := time.Now()
	tx, err := c.pool.Begin(ctx)
	if err != nil {
		slog.Error("CompactNote: begin tx failed", "note_id", noteID, "error", err, "elapsed_ms", time.Since(startTx).Milliseconds())
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	startLock := time.Now()
	if _, err := tx.Exec(ctx, "SELECT pg_advisory_xact_lock(hashtext($1::text), hashtext('nodes'))", noteID); err != nil {
		slog.Error("CompactNote: advisory lock failed", "note_id", noteID, "error", err, "elapsed_ms", time.Since(startLock).Milliseconds())
		return fmt.Errorf("advisory lock: %w", err)
	}
	slog.Info("CompactNote: lock acquired", "note_id", noteID, "lock_ms", time.Since(startLock).Milliseconds())

	startQuery := time.Now()
	var existingState []byte
	if err := tx.QueryRow(ctx, "SELECT state FROM note_yjs_states WHERE note_id = $1", noteID).Scan(&existingState); err != nil && !errors.Is(err, pgx.ErrNoRows) {
		slog.Error("CompactNote: query state failed", "note_id", noteID, "error", err, "elapsed_ms", time.Since(startQuery).Milliseconds())
		return fmt.Errorf("query existing state: %w", err)
	}

	rows, err := tx.Query(ctx, "SELECT update_data FROM note_yjs_updates WHERE note_id = $1 ORDER BY created_at ASC", noteID)
	if err != nil {
		slog.Error("CompactNote: query updates failed", "note_id", noteID, "error", err, "elapsed_ms", time.Since(startQuery).Milliseconds())
		return fmt.Errorf("query updates: %w", err)
	}
	var allUpdates [][]byte
	for rows.Next() {
		var u []byte
		if err := rows.Scan(&u); err != nil {
			rows.Close()
			slog.Error("CompactNote: scan update failed", "note_id", noteID, "error", err)
			return fmt.Errorf("scan update: %w", err)
		}
		allUpdates = append(allUpdates, u)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return fmt.Errorf("rows iter: %w", err)
	}
	slog.Info("CompactNote: queries done", "note_id", noteID, "existing_state_bytes", len(existingState), "pending_updates", len(allUpdates), "query_ms", time.Since(startQuery).Milliseconds())

	if len(allUpdates) == 0 && existingState == nil {
		slog.Info("CompactNote: nothing to compact", "note_id", noteID, "elapsed_ms", time.Since(startTotal).Milliseconds())
		return nil
	}

	startMerge := time.Now()
	parts := make([][]byte, 0, len(allUpdates)+1)
	if existingState != nil {
		parts = append(parts, existingState)
	}
	parts = append(parts, allUpdates...)
	merged, err := crdt.MergeUpdatesV1(parts...)
	if err != nil {
		slog.Error("CompactNote: merge failed", "note_id", noteID, "error", err, "elapsed_ms", time.Since(startMerge).Milliseconds())
		return fmt.Errorf("merge updates: %w", err)
	}
	slog.Info("CompactNote: merged", "note_id", noteID, "merged_bytes", len(merged), "merge_ms", time.Since(startMerge).Milliseconds())

	startPersist := time.Now()
	if _, err := tx.Exec(ctx, `
		INSERT INTO note_yjs_states (note_id, state, updated_at)
		VALUES ($1, $2, NOW())
		ON CONFLICT (note_id) DO UPDATE
		SET state = EXCLUDED.state, updated_at = NOW()
	`, noteID, merged); err != nil {
		slog.Error("CompactNote: upsert state failed", "note_id", noteID, "error", err, "elapsed_ms", time.Since(startPersist).Milliseconds())
		return fmt.Errorf("upsert state: %w", err)
	}

	if _, err := tx.Exec(ctx, "DELETE FROM note_yjs_updates WHERE note_id = $1", noteID); err != nil {
		slog.Error("CompactNote: delete updates failed", "note_id", noteID, "error", err, "elapsed_ms", time.Since(startPersist).Milliseconds())
		return fmt.Errorf("delete compacted updates: %w", err)
	}
	slog.Info("CompactNote: persist done", "note_id", noteID, "persist_ms", time.Since(startPersist).Milliseconds())

	startCommit := time.Now()
	if err := tx.Commit(ctx); err != nil {
		slog.Error("CompactNote: commit failed", "note_id", noteID, "error", err, "elapsed_ms", time.Since(startCommit).Milliseconds())
		return fmt.Errorf("commit: %w", err)
	}
	slog.Info("CompactNote: done", "note_id", noteID, "total_ms", time.Since(startTotal).Milliseconds())
	return nil
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

func (c *Compactor) PruneOldUpdates(ctx context.Context, olderThan time.Duration) error {
	_, err := c.pool.Exec(ctx,
		"DELETE FROM note_yjs_updates WHERE created_at < NOW() - $1::interval",
		olderThan.String(),
	)
	return err
}

func (c *Compactor) StartScheduler(ctx context.Context, interval time.Duration) {
	go func() {
		ticker := time.NewTicker(interval)
		defer ticker.Stop()
		pruneTicker := time.NewTicker(24 * time.Hour)
		defer pruneTicker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				if err := c.CompactAll(ctx); err != nil {
					slog.Error("compaction run failed", "error", err)
				}
			case <-pruneTicker.C:
				if err := c.PruneOldUpdates(ctx, 30*24*time.Hour); err != nil {
					slog.Error("prune run failed", "error", err)
				}
			}
		}
	}()
}
