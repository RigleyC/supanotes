package sync

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"log/slog"
	"regexp"
	"sort"
	"sync"
	"sync/atomic"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/reearth/ygo/crdt"
)

var contentRegex = regexp.MustCompile(`content/[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}`)

func PreRegisterYText(doc *crdt.Doc, state []byte) {
	doc.GetMap("nodes")
	matches := contentRegex.FindAll(state, -1)
	for _, match := range matches {
		doc.GetText(string(match))
	}
}

type projectionRunner interface {
	RunDebouncedProjection(ctx context.Context, noteID string)
	ProjectCanonicalDoc(ctx context.Context, noteID string) error
	Close() error
}

// noteEntry bundles the YDoc, its per-note mutex, and metadata for LRU eviction.
//
// leaseCount tracks concurrent WithDoc callers. While leaseCount > 0 the entry
// is protected from eviction — no concurrent request can forge a fresh lock
// for the same note.
type noteEntry struct {
	mu         sync.Mutex // per-note lock — synchronises YDoc mutations
	doc        *crdt.Doc  // nil means the doc needs to be loaded from DB
	lastUsed   time.Time  // bumped on every DocFor / WithDoc
	leaseCount int32      // number of in-flight WithDoc calls
}

type YDocService struct {
	pool       *pgxpool.Pool
	projection projectionRunner
	machineID  string

	maxCachedDocs int           // 0 = unlimited (prod default: 1000)
	idleTTL       time.Duration // 0 = default 5 min

	mu    sync.Mutex
	notes map[string]*noteEntry

	evictCtx    context.Context
	evictCancel context.CancelFunc
	wg          sync.WaitGroup
}

// YDocServiceOption allows test-friendly configuration.
type YDocServiceOption func(*YDocService)

func WithMaxCachedDocs(n int) YDocServiceOption {
	return func(s *YDocService) { s.maxCachedDocs = n }
}

func WithIdleTTL(d time.Duration) YDocServiceOption {
	return func(s *YDocService) { s.idleTTL = d }
}

func NewYDocService(pool *pgxpool.Pool, projection projectionRunner, machineID string, opts ...YDocServiceOption) *YDocService {
	ctx, cancel := context.WithCancel(context.Background())
	s := &YDocService{
		pool:          pool,
		projection:    projection,
		machineID:     machineID,
		maxCachedDocs: 1000,
		idleTTL:       5 * time.Minute,
		notes:         make(map[string]*noteEntry),
		evictCtx:      ctx,
		evictCancel:   cancel,
	}
	for _, opt := range opts {
		opt(s)
	}
	s.wg.Add(1)
	go s.evictStaleLoop()
	return s
}

// Close cancels the eviction goroutine, closes the projection runner,
// and waits for all goroutines to finish.
func (s *YDocService) Close() {
	s.evictCancel()
	if s.projection != nil {
		_ = s.projection.Close()
	}
	s.wg.Wait()
}

// evictStaleLoop evicts idle docs on a ticker AND on every insert to keep the
// cache within maxCachedDocs. Entries with active leases are preserved.
func (s *YDocService) evictStaleLoop() {
	defer s.wg.Done()
	ticker := time.NewTicker(s.idleTTL)
	defer ticker.Stop()
	for {
		select {
		case <-s.evictCtx.Done():
			return
		case <-ticker.C:
		}
		s.mu.Lock()
		s.evictIdle()
		s.evictLRU()
		s.mu.Unlock()
	}
}

// evictIdle removes entries whose lastUsed exceeds idleTTL and have no active lease.
func (s *YDocService) evictIdle() {
	threshold := time.Now().Add(-s.idleTTL)
	for noteID, entry := range s.notes {
		if atomic.LoadInt32(&entry.leaseCount) == 0 && entry.lastUsed.Before(threshold) {
			delete(s.notes, noteID)
			slog.Debug("evicted idle doc", "note_id", noteID, "idle_since", entry.lastUsed.Format(time.RFC3339))
		}
	}
}

// evictLRU brings the cache down to maxCachedDocs by removing the oldest
// entries (with no active lease) when the map exceeds the limit.
func (s *YDocService) evictLRU() {
	maxDocs := s.maxCachedDocs
	if maxDocs <= 0 || len(s.notes) <= maxDocs {
		return
	}

	ids := make([]string, 0, len(s.notes))
	for noteID, entry := range s.notes {
		if atomic.LoadInt32(&entry.leaseCount) == 0 {
			ids = append(ids, noteID)
		}
	}
	if len(ids) == 0 {
		return // all entries have active leases — can't evict
	}

	sort.Slice(ids, func(i, j int) bool {
		return s.notes[ids[i]].lastUsed.Before(s.notes[ids[j]].lastUsed)
	})

	toEvict := len(s.notes) - maxDocs
	if toEvict > len(ids) {
		toEvict = len(ids)
	}
	for i := 0; i < toEvict; i++ {
		delete(s.notes, ids[i])
	}
	slog.Debug("LRU eviction: evicted", "count", toEvict, "remaining", len(s.notes))
}

// acquireLease marks the entry as in-use; eviction will skip it until releaseLease.
func (s *YDocService) acquireLease(entry *noteEntry) {
	atomic.AddInt32(&entry.leaseCount, 1)
}

func (s *YDocService) releaseLease(entry *noteEntry) {
	atomic.AddInt32(&entry.leaseCount, -1)
}

// getOrCreateEntry returns the noteEntry for noteID, creating one if absent.
func (s *YDocService) getOrCreateEntry(noteID string) *noteEntry {
	entry := s.notes[noteID]
	if entry == nil {
		entry = &noteEntry{}
		s.notes[noteID] = entry
	}
	return entry
}

func (s *YDocService) WithDoc(ctx context.Context, noteID string, fn func(doc *crdt.Doc) error) error {
	s.mu.Lock()
	entry := s.getOrCreateEntry(noteID)
	s.acquireLease(entry)
	s.mu.Unlock()

	doc, err := s.DocFor(ctx, noteID)
	if err != nil {
		s.releaseLease(entry)
		return err
	}

	entry.mu.Lock()
	err = fn(doc)
	entry.mu.Unlock()
	s.releaseLease(entry)
	return err
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
	entry := s.getOrCreateEntry(noteID)
	if entry.doc != nil {
		entry.lastUsed = time.Now()
		s.mu.Unlock()
		slog.Debug("DocFor: cache hit", "note_id", noteID)
		return entry.doc, nil
	}
	s.mu.Unlock()

	startLoad := time.Now()
	state, err := LoadYDocState(ctx, s.pool, noteID)
	loadElapsed := time.Since(startLoad)
	if err != nil {
		slog.Error("DocFor: LoadYDocState failed", "note_id", noteID, "error", err, "elapsed_ms", loadElapsed.Milliseconds())
		return nil, err
	}
	slog.Info("DocFor: LoadYDocState done", "note_id", noteID, "state_bytes", len(state), "elapsed_ms", loadElapsed.Milliseconds())

	startApply := time.Now()
	doc := crdt.New(crdt.WithGC(false))
	if len(state) > 0 {
		PreRegisterYText(doc, state)
		if err := crdt.ApplyUpdateV1(doc, state, nil); err != nil {
			slog.Error("DocFor: ApplyUpdateV1 failed", "note_id", noteID, "error", err, "elapsed_ms", time.Since(startApply).Milliseconds())
			return nil, err
		}
	}
	slog.Info("DocFor: ApplyUpdateV1 done", "note_id", noteID, "elapsed_ms", time.Since(startApply).Milliseconds())

	s.mu.Lock()
	// Double-check — another goroutine may have loaded concurrently.
	if entry.doc != nil {
		s.mu.Unlock()
		slog.Debug("DocFor: concurrent load resolved", "note_id", noteID)
		return entry.doc, nil
	}
	entry.doc = doc
	entry.lastUsed = time.Now()
	s.mu.Unlock()

	// Evict on insert to respect capacity immediately.
	s.mu.Lock()
	s.evictLRU()
	s.mu.Unlock()

	slog.Info("DocFor: doc cached", "note_id", noteID, "total_elapsed_ms", time.Since(startLoad).Milliseconds())
	return doc, nil
}

func (s *YDocService) ApplyNodeMutation(ctx context.Context, noteID string, update []byte) error {
	s.mu.Lock()
	entry := s.getOrCreateEntry(noteID)
	s.acquireLease(entry)
	s.mu.Unlock()
	defer s.releaseLease(entry)

	entry.mu.Lock()
	defer entry.mu.Unlock()

	doc, err := s.DocFor(ctx, noteID)
	if err != nil {
		return err
	}
	return s.ApplyNodeMutationLocked(ctx, doc, noteID, update)
}

func (s *YDocService) ApplyNodeMutationLocked(ctx context.Context, doc *crdt.Doc, noteID string, update []byte) error {
	startApply := time.Now()
	PreRegisterYText(doc, update)
	if err := crdt.ApplyUpdateV1(doc, update, "local"); err != nil {
		slog.Error("ApplyNodeMutationLocked: ApplyUpdateV1 failed", "note_id", noteID, "error", err)
		return err
	}
	slog.Debug("ApplyNodeMutationLocked: ApplyUpdateV1 done", "note_id", noteID, "update_bytes", len(update), "elapsed_ms", time.Since(startApply).Milliseconds())

	// Persist synchronously to DB
	if err := s.persistNoteToDB(ctx, noteID, update); err != nil {
		slog.Error("ApplyNodeMutationLocked: persist failed", "note_id", noteID, "error", err)
		return err
	}

	if s.projection != nil {
		s.projection.RunDebouncedProjection(ctx, noteID)
	}

	// Broadcast to other instances via Postgres NOTIFY
	go func() {
		bgCtx := context.Background()
		b64Update := ""
		if len(update) < 6000 {
			b64Update = base64.StdEncoding.EncodeToString(update)
		}
		payloadBytes, _ := json.Marshal(map[string]string{
			"note_id":    noteID,
			"update":     b64Update,
			"machine_id": s.machineID,
		})
		_, err := s.pool.Exec(bgCtx, "SELECT pg_notify('yjs_room_updates', $1)", string(payloadBytes))
		if err != nil {
			slog.Error("ApplyNodeMutationLocked: notify failed", "error", err)
		}
	}()

	return nil
}

func (s *YDocService) persistNoteToDB(ctx context.Context, noteID string, update []byte) error {
	startInsert := time.Now()
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		slog.Error("persistNoteToDB: begin tx failed", "note_id", noteID, "error", err, "elapsed_ms", time.Since(startInsert).Milliseconds())
		return err
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx, "INSERT INTO note_yjs_updates (note_id, update_data) VALUES ($1, $2)", noteID, update); err != nil {
		slog.Error("persistNoteToDB: insert failed", "note_id", noteID, "error", err, "elapsed_ms", time.Since(startInsert).Milliseconds())
		return err
	}
	if err := tx.Commit(ctx); err != nil {
		slog.Error("persistNoteToDB: commit failed", "note_id", noteID, "error", err, "elapsed_ms", time.Since(startInsert).Milliseconds())
		return err
	}
	slog.Debug("persistNoteToDB: committed", "note_id", noteID, "elapsed_ms", time.Since(startInsert).Milliseconds())
	return nil
}

func (s *YDocService) ProjectCanonicalDoc(ctx context.Context, noteID string) error {
	if s.projection == nil {
		return nil
	}
	return s.projection.ProjectCanonicalDoc(ctx, noteID)
}

func (s *YDocService) StartListener(ctx context.Context) {
	go func() {
		for {
			select {
			case <-ctx.Done():
				return
			default:
			}
			conn, err := s.pool.Acquire(ctx)
			if err != nil {
				time.Sleep(2 * time.Second)
				continue
			}
			_, err = conn.Exec(ctx, "LISTEN yjs_room_updates")
			if err != nil {
				conn.Release()
				time.Sleep(2 * time.Second)
				continue
			}
			for {
				notification, err := conn.Conn().WaitForNotification(ctx)
				if err != nil {
					conn.Release()
					break
				}
				s.handleNotification(ctx, notification.Payload)
			}
		}
	}()
}

func (s *YDocService) handleNotification(ctx context.Context, payload string) {
	var data map[string]string
	if err := json.Unmarshal([]byte(payload), &data); err != nil {
		slog.Error("handleNotification: invalid payload", "error", err)
		return
	}
	noteID := data["note_id"]
	if noteID == "" {
		return
	}
	if data["machine_id"] == s.machineID {
		return
	}

	var update []byte
	var err error
	if b64, ok := data["update"]; ok && b64 != "" {
		update, err = base64.StdEncoding.DecodeString(b64)
		if err != nil {
			slog.Error("handleNotification: base64 decode failed", "error", err)
			return
		}
	} else {
		update, err = LoadYDocState(ctx, s.pool, noteID)
		if err != nil {
			slog.Error("handleNotification: LoadYDocState failed", "error", err)
			return
		}
	}

	// Acquire entry + lease + per-note lock BEFORE DocFor so no concurrent
	// mutation can race with us (same pattern as ApplyNodeMutation).
	s.mu.Lock()
	entry := s.getOrCreateEntry(noteID)
	s.acquireLease(entry)
	s.mu.Unlock()
	defer s.releaseLease(entry)

	entry.mu.Lock()
	defer entry.mu.Unlock()

	doc, err := s.DocFor(ctx, noteID)
	if err != nil {
		return
	}

	if err := crdt.ApplyUpdateV1(doc, update, "remote"); err != nil {
		slog.Error("handleNotification: ApplyUpdateV1 failed", "error", err)
		return
	}

	if s.projection != nil {
		s.projection.RunDebouncedProjection(ctx, noteID)
	}
}
