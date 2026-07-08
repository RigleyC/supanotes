package sync

import (
	"context"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/reearth/ygo/crdt"
)

type projectionRunner interface {
	RunDebouncedProjection(ctx context.Context, noteID string)
}

type YDocService struct {
	pool       *pgxpool.Pool
	projection projectionRunner
	mu         sync.Mutex
	docs       map[string]*crdt.Doc
	buffers    map[string][][]byte
}

func NewYDocService(pool *pgxpool.Pool, projection projectionRunner) *YDocService {
	return &YDocService{
		pool:       pool,
		projection: projection,
		docs:       make(map[string]*crdt.Doc),
		buffers:    make(map[string][][]byte),
	}
}

func mergeYjsUpdates(updates [][]byte) ([]byte, error) {
	if len(updates) == 0 {
		return nil, nil
	}
	if len(updates) == 1 {
		return updates[0], nil
	}
	return crdt.MergeUpdatesV1(updates...)
}

func (s *YDocService) DocFor(ctx context.Context, noteID string) (*crdt.Doc, error) {
	s.mu.Lock()
	if doc, ok := s.docs[noteID]; ok {
		s.mu.Unlock()
		return doc, nil
	}
	s.mu.Unlock()

	state, err := LoadYDocState(ctx, s.pool, noteID)
	if err != nil {
		return nil, err
	}
	doc := crdt.New(crdt.WithGC(false))
	if len(state) > 0 {
		if err := crdt.ApplyUpdateV1(doc, state, nil); err != nil {
			return nil, err
		}
	}
	s.mu.Lock()
	// Double-check in case another goroutine loaded concurrently.
	if existing, ok := s.docs[noteID]; ok {
		s.mu.Unlock()
		return existing, nil
	}
	s.docs[noteID] = doc
	s.mu.Unlock()
	return doc, nil
}

func (s *YDocService) ApplyNodeMutation(ctx context.Context, noteID string, update []byte) error {
	doc, err := s.DocFor(ctx, noteID)
	if err != nil {
		return err
	}
	if err := crdt.ApplyUpdateV1(doc, update, "local"); err != nil {
		return err
	}

	s.mu.Lock()
	s.buffers[noteID] = append(s.buffers[noteID], update)
	s.mu.Unlock()

	if s.projection != nil {
		s.projection.RunDebouncedProjection(ctx, noteID)
	}
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

	var wg sync.WaitGroup
	for _, id := range noteIDs {
		wg.Add(1)
		id := id
		go func() {
			defer wg.Done()
			_ = s.FlushUpdates(ctx, id)
		}()
	}
	wg.Wait()
}
