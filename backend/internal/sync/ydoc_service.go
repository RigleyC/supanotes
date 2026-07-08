package sync

import (
	"context"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/reearth/ygo/crdt"
)

func mergeYjsUpdates(updates [][]byte) ([]byte, error) {
	if len(updates) == 0 {
		return nil, nil
	}
	if len(updates) == 1 {
		return updates[0], nil
	}
	return crdt.MergeUpdatesV1(updates...)
}

type YDocService struct {
	pool    *pgxpool.Pool
	mu      sync.Mutex
	buffers map[string][][]byte
}

func NewYDocService(pool *pgxpool.Pool) *YDocService {
	return &YDocService{
		pool:    pool,
		buffers: make(map[string][][]byte),
	}
}

func (s *YDocService) ApplyNodeMutation(_ context.Context, noteID string, update []byte) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.buffers[noteID] = append(s.buffers[noteID], update)
	return nil
}

func (s *YDocService) flushNoteToDB(ctx context.Context, noteID string, updates [][]byte) error {
	merged, err := mergeYjsUpdates(updates)
	if err != nil {
		return err
	}

	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx, "SELECT pg_advisory_xact_lock(hashtext($1::text), hashtext('nodes'))", noteID); err != nil {
		return err
	}

	if _, err := tx.Exec(ctx, "INSERT INTO note_yjs_updates (note_id, update_data) VALUES ($1, $2)", noteID, merged); err != nil {
		return err
	}

	return tx.Commit(ctx)
}

func (s *YDocService) FlushUpdates(ctx context.Context, noteID string) error {
	s.mu.Lock()
	updates := s.buffers[noteID]
	delete(s.buffers, noteID)
	s.mu.Unlock()

	if len(updates) == 0 {
		return nil
	}

	if err := s.flushNoteToDB(ctx, noteID, updates); err != nil {
		s.mu.Lock()
		s.buffers[noteID] = append(updates, s.buffers[noteID]...)
		s.mu.Unlock()
		return err
	}
	return nil
}

func (s *YDocService) StartFlusher(ctx context.Context, interval time.Duration) {
	go func() {
		ticker := time.NewTicker(interval)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				s.flushAll(ctx)
			}
		}
	}()
}

func (s *YDocService) flushAll(ctx context.Context) {
	s.mu.Lock()
	noteIDs := make([]string, 0, len(s.buffers))
	for id := range s.buffers {
		noteIDs = append(noteIDs, id)
	}
	s.mu.Unlock()

	for _, id := range noteIDs {
		_ = s.FlushUpdates(ctx, id)
	}
}
