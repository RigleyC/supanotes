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
	flushFn    func(context.Context, string) error
}

func NewCompactor(pool *pgxpool.Pool) *Compactor {
	return &Compactor{
		pool:     pool,
		debounce: make(map[string]*debounceState),
	}
}

func (c *Compactor) SetFlushFunc(fn func(context.Context, string) error) {
	c.flushFn = fn
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
		_ = c.ProjectCanonicalDoc(context.Background(), noteID)
	})
}

func (c *Compactor) RunDebouncedProjectionForTest(ctx context.Context, svc *YDocService, noteID string, update []byte) error {
	if err := svc.ApplyNodeMutation(ctx, noteID, update); err != nil {
		return err
	}
	if err := svc.FlushUpdates(ctx, noteID); err != nil {
		return err
	}
	return c.ProjectCanonicalDoc(ctx, noteID)
}

func (c *Compactor) ProjectCanonicalDoc(ctx context.Context, noteID string) error {
	startTotal := time.Now()
	if c.flushFn != nil {
		if err := c.flushFn(ctx, noteID); err != nil {
			slog.Error("projectCanonicalDoc: flushFn failed", "note_id", noteID, "error", err)
		}
	}
	state, err := LoadYDocState(ctx, c.pool, noteID)
	if err != nil {
		slog.Error("projectCanonicalDoc: LoadYDocState failed", "note_id", noteID, "error", err, "elapsed_ms", time.Since(startTotal).Milliseconds())
		return err
	}
	if len(state) == 0 {
		slog.Debug("projectCanonicalDoc: empty state, skip", "note_id", noteID)
		return nil
	}
	startApply := time.Now()
	doc := crdt.New(crdt.WithGC(false))
	if err := crdt.ApplyUpdateV1(doc, state, nil); err != nil {
		slog.Error("projectCanonicalDoc: ApplyUpdateV1 failed", "note_id", noteID, "error", err, "elapsed_ms", time.Since(startApply).Milliseconds())
		return err
	}
	slog.Debug("projectCanonicalDoc: doc loaded", "note_id", noteID, "state_bytes", len(state), "apply_ms", time.Since(startApply).Milliseconds())

	startTx := time.Now()
	tx, err := c.pool.Begin(ctx)
	if err != nil {
		slog.Error("projectCanonicalDoc: begin tx failed", "note_id", noteID, "error", err, "elapsed_ms", time.Since(startTx).Milliseconds())
		return err
	}
	defer tx.Rollback(ctx)
	if _, err := tx.Exec(ctx, "SELECT pg_advisory_xact_lock(hashtext($1::text), hashtext('nodes'))", noteID); err != nil {
		slog.Error("projectCanonicalDoc: advisory lock failed", "note_id", noteID, "error", err, "elapsed_ms", time.Since(startTx).Milliseconds())
		return err
	}
	startProj := time.Now()
	if err := ProjectToDBTxFromDoc(ctx, tx, doc, noteID); err != nil {
		slog.Error("projectCanonicalDoc: project failed", "note_id", noteID, "error", err, "elapsed_ms", time.Since(startProj).Milliseconds())
		return err
	}
	slog.Debug("projectCanonicalDoc: project done", "note_id", noteID, "project_ms", time.Since(startProj).Milliseconds())

	startCommit := time.Now()
	if err := tx.Commit(ctx); err != nil {
		slog.Error("projectCanonicalDoc: commit failed", "note_id", noteID, "error", err, "elapsed_ms", time.Since(startCommit).Milliseconds())
		return err
	}
	slog.Info("projectCanonicalDoc: done", "note_id", noteID, "total_ms", time.Since(startTotal).Milliseconds())
	return nil
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

	// PROJECT FROM THE FULL DOC STATE — not from the partial update.
	startProj := time.Now()
	doc := crdt.New(crdt.WithGC(false))
	if err := crdt.ApplyUpdateV1(doc, merged, nil); err != nil {
		slog.Error("CompactNote: ApplyUpdateV1 failed", "note_id", noteID, "error", err, "elapsed_ms", time.Since(startProj).Milliseconds())
		return fmt.Errorf("apply merged state for projection: %w", err)
	}
	if err := projectDocToDB(ctx, tx, doc, noteID); err != nil {
		slog.Error("CompactNote: projectDocToDB failed", "note_id", noteID, "error", err, "elapsed_ms", time.Since(startProj).Milliseconds())
		return fmt.Errorf("project during compaction: %w", err)
	}
	slog.Info("CompactNote: project done", "note_id", noteID, "project_ms", time.Since(startProj).Milliseconds())

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
