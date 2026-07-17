package sync

import (
	"context"
	"encoding/json"
	"log/slog"
	"regexp"
	"strings"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/reearth/ygo/crdt"
)

var contentRegex = regexp.MustCompile(`content/[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}`)

func preRegisterYText(doc *crdt.Doc, state []byte) {
	matches := contentRegex.FindAll(state, -1)
	for _, match := range matches {
		doc.GetText(string(match))
	}
}

type projectionRunner interface {
	RunDebouncedProjection(ctx context.Context, noteID string)
	ProjectCanonicalDoc(ctx context.Context, noteID string) error
}

type YDocService struct {
	pool         *pgxpool.Pool
	projection   projectionRunner
	roomMgr      *RoomManager
	mu           sync.Mutex
	docs         map[string]*crdt.Doc
	buffers      map[string][][]byte
	failureCount map[string]int
	docLocks     map[string]*sync.Mutex
	locksMu      sync.Mutex
}

func NewYDocService(pool *pgxpool.Pool, projection projectionRunner, roomMgr *RoomManager) *YDocService {
	return &YDocService{
		pool:         pool,
		projection:   projection,
		roomMgr:      roomMgr,
		docs:         make(map[string]*crdt.Doc),
		buffers:      make(map[string][][]byte),
		failureCount: make(map[string]int),
		docLocks:     make(map[string]*sync.Mutex),
	}
}

// SetRoomManager sets the RoomManager after construction to break the
// circular dependency: YDocService ↔ RoomManager. Call once before use.
func (s *YDocService) SetRoomManager(mgr *RoomManager) {
	s.roomMgr = mgr
}

func (s *YDocService) getDocLock(noteID string) *sync.Mutex {
	s.locksMu.Lock()
	defer s.locksMu.Unlock()
	l, ok := s.docLocks[noteID]
	if !ok {
		l = &sync.Mutex{}
		s.docLocks[noteID] = l
	}
	return l
}

func (s *YDocService) WithDoc(ctx context.Context, noteID string, fn func(doc *crdt.Doc) error) error {
	startLock := time.Now()
	lock := s.getDocLock(noteID)
	lock.Lock()
	lockElapsed := time.Since(startLock)
	if lockElapsed > 5*time.Millisecond {
		slog.Warn("WithDoc: lock acquired slowly", "note_id", noteID, "lock_wait_ms", lockElapsed.Milliseconds())
	}
	defer lock.Unlock()

	startDoc := time.Now()
	doc, err := s.DocFor(ctx, noteID)
	docElapsed := time.Since(startDoc)
	if docElapsed > 5*time.Millisecond {
		slog.Warn("WithDoc: DocFor slow", "note_id", noteID, "doc_for_ms", docElapsed.Milliseconds(), "error", err)
	}
	if err != nil {
		slog.Error("WithDoc: DocFor failed", "note_id", noteID, "error", err, "elapsed_ms", time.Since(startLock).Milliseconds())
		return err
	}
	startFn := time.Now()
	err = fn(doc)
	fnElapsed := time.Since(startFn)
	if fnElapsed > 5*time.Millisecond {
		slog.Warn("WithDoc: fn slow", "note_id", noteID, "fn_ms", fnElapsed.Milliseconds())
	}
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
	if doc, ok := s.docs[noteID]; ok {
		s.mu.Unlock()
		slog.Debug("DocFor: cache hit", "note_id", noteID)
		return doc, nil
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
		preRegisterYText(doc, state)
		if err := crdt.ApplyUpdateV1(doc, state, nil); err != nil {
			slog.Error("DocFor: ApplyUpdateV1 failed", "note_id", noteID, "error", err, "elapsed_ms", time.Since(startApply).Milliseconds())
			return nil, err
		}
	}
	slog.Info("DocFor: ApplyUpdateV1 done", "note_id", noteID, "elapsed_ms", time.Since(startApply).Milliseconds())

	// P4 migration: upgrade legacy docs where task data is inline in node `data`.
	MigrateLegacyDoc(doc)

	s.mu.Lock()
	// Double-check in case another goroutine loaded concurrently.
	if existing, ok := s.docs[noteID]; ok {
		s.mu.Unlock()
		slog.Debug("DocFor: concurrent load resolved", "note_id", noteID)
		return existing, nil
	}
	s.docs[noteID] = doc
	s.mu.Unlock()
	slog.Info("DocFor: doc cached", "note_id", noteID, "total_elapsed_ms", time.Since(startLoad).Milliseconds())
	return doc, nil
}

// WARNING: This function has a twin in lib/core/sync/yjs_sync_manager.dart.
// Both must be kept in sync.
//
// Migrates a legacy doc where nodes are stored as JSON strings into nested
// YMap entries. Task fields (completed, dueDate, recurrence, lastCompletedAt)
// are promoted to top-level keys on the node's YMap.
//
// Idempotent: skips if any node is already a YMap.
func MigrateLegacyDoc(doc *crdt.Doc) {
	nodesMap := doc.GetMap("nodes")
	if nodesMap == nil {
		return
	}

	// Check if migration is needed: any node is still a string
	needsMigration := false
	for _, key := range nodesMap.Keys() {
		if strings.Contains(key, ":") {
			continue
		}
		raw, ok := nodesMap.Get(key)
		if !ok {
			continue
		}
		switch raw.(type) {
		case *crdt.YMap:
			// Already migrated, skip
			continue
		case string:
			needsMigration = true
			break
		}
	}
	if !needsMigration {
		return
	}

	slog.Info("MigrateLegacyDoc: migrating doc to nested YMap schema")
	keys := nodesMap.Keys()
	doc.Transact(func(txn *crdt.Transaction) {
		for _, key := range keys {
			if strings.Contains(key, ":") {
				continue
			}
			raw, ok := nodesMap.Get(key)
			if !ok {
				continue
			}
			rawStr, ok := raw.(string)
			if !ok {
				continue
			}
			var meta map[string]interface{}
			if err := json.Unmarshal([]byte(rawStr), &meta); err != nil {
				slog.Warn("MigrateLegacyDoc: decode error", "key", key, "error", err)
				continue
			}

			nodeMap := &crdt.YMap{}
			nodeMap.Set(txn, "id", meta["id"])
			nodeMap.Set(txn, "parentId", meta["parentId"])
			nodeMap.Set(txn, "position", meta["position"])
			nodeMap.Set(txn, "type", meta["type"])

			if typeStr, _ := meta["type"].(string); typeStr == "task" {
				if data, ok := meta["data"].(map[string]interface{}); ok {
					if completed, exists := data["completed"]; exists {
						nodeMap.Set(txn, "completed", completed)
						delete(data, "completed")
					}
					if dueDate, exists := data["dueDate"]; exists {
						nodeMap.Set(txn, "dueDate", dueDate)
						delete(data, "dueDate")
					}
					if recurrence, exists := data["recurrence"]; exists {
						nodeMap.Set(txn, "recurrence", recurrence)
						delete(data, "recurrence")
					}
					if lastCompletedAt, exists := data["lastCompletedAt"]; exists {
						nodeMap.Set(txn, "lastCompletedAt", lastCompletedAt)
						delete(data, "lastCompletedAt")
					}
					cleanedData, _ := json.Marshal(data)
					nodeMap.Set(txn, "data", string(cleanedData))
				}
			} else {
				if data, ok := meta["data"]; ok {
					switch d := data.(type) {
					case string:
						nodeMap.Set(txn, "data", d)
					case map[string]interface{}, []interface{}:
						b, _ := json.Marshal(d)
						nodeMap.Set(txn, "data", string(b))
					default:
						nodeMap.Set(txn, "data", d)
					}
				}
			}

			if createdAt, ok := meta["createdAt"]; ok {
				nodeMap.Set(txn, "createdAt", createdAt)
			}

			nodesMap.Set(txn, key, nodeMap)
		}
	})
	slog.Info("MigrateLegacyDoc: migration complete")
}

func (s *YDocService) ApplyNodeMutation(ctx context.Context, noteID string, update []byte) error {
	startLock := time.Now()
	lock := s.getDocLock(noteID)
	lock.Lock()
	lockElapsed := time.Since(startLock)
	if lockElapsed > 5*time.Millisecond {
		slog.Warn("ApplyNodeMutation: lock acquired slowly", "note_id", noteID, "lock_wait_ms", lockElapsed.Milliseconds())
	}
	defer lock.Unlock()

	startDoc := time.Now()
	doc, err := s.DocFor(ctx, noteID)
	if err != nil {
		slog.Error("ApplyNodeMutation: DocFor failed", "note_id", noteID, "error", err, "elapsed_ms", time.Since(startDoc).Milliseconds())
		return err
	}
	slog.Info("ApplyNodeMutation: DocFor done", "note_id", noteID, "elapsed_ms", time.Since(startDoc).Milliseconds())
	return s.ApplyNodeMutationLocked(ctx, doc, noteID, update)
}

func (s *YDocService) ApplyNodeMutationLocked(ctx context.Context, doc *crdt.Doc, noteID string, update []byte) error {
	startApply := time.Now()
	preRegisterYText(doc, update)
	if err := crdt.ApplyUpdateV1(doc, update, "local"); err != nil {
		slog.Error("ApplyNodeMutationLocked: ApplyUpdateV1 failed", "note_id", noteID, "error", err)
		return err
	}
	slog.Debug("ApplyNodeMutationLocked: ApplyUpdateV1 done", "note_id", noteID, "update_bytes", len(update), "elapsed_ms", time.Since(startApply).Milliseconds())

	s.mu.Lock()
	s.buffers[noteID] = append(s.buffers[noteID], update)
	bufLen := len(s.buffers[noteID])
	s.mu.Unlock()
	slog.Debug("ApplyNodeMutationLocked: buffered", "note_id", noteID, "buffer_len", bufLen)

	if s.projection != nil {
		s.projection.RunDebouncedProjection(ctx, noteID)
	}

	if s.roomMgr != nil {
		go s.roomMgr.BroadcastIfActive(noteID, update)
	}

	return nil
}

func (s *YDocService) flushNoteToDB(ctx context.Context, noteID string, updates [][]byte) error {
	startMerge := time.Now()
	merged, err := mergeYjsUpdates(updates)
	if err != nil {
		slog.Error("flushNoteToDB: merge failed", "note_id", noteID, "error", err)
		return err
	}
	slog.Info("flushNoteToDB: merged", "note_id", noteID, "updates", len(updates), "merged_bytes", len(merged), "elapsed_ms", time.Since(startMerge).Milliseconds())

	startTx := time.Now()
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		slog.Error("flushNoteToDB: begin tx failed", "note_id", noteID, "error", err, "elapsed_ms", time.Since(startTx).Milliseconds())
		return err
	}
	defer tx.Rollback(ctx)

	startLock := time.Now()
	if _, err := tx.Exec(ctx, "SELECT pg_advisory_xact_lock(hashtext($1::text), hashtext('nodes'))", noteID); err != nil {
		slog.Error("flushNoteToDB: advisory lock failed", "note_id", noteID, "error", err, "elapsed_ms", time.Since(startLock).Milliseconds())
		return err
	}
	slog.Info("flushNoteToDB: advisory lock acquired", "note_id", noteID, "elapsed_ms", time.Since(startLock).Milliseconds())

	startInsert := time.Now()
	if _, err := tx.Exec(ctx, "INSERT INTO note_yjs_updates (note_id, update_data) VALUES ($1, $2)", noteID, merged); err != nil {
		slog.Error("flushNoteToDB: insert failed", "note_id", noteID, "error", err, "elapsed_ms", time.Since(startInsert).Milliseconds())
		return err
	}
	slog.Info("flushNoteToDB: insert done", "note_id", noteID, "elapsed_ms", time.Since(startInsert).Milliseconds())

	startCommit := time.Now()
	if err := tx.Commit(ctx); err != nil {
		slog.Error("flushNoteToDB: commit failed", "note_id", noteID, "error", err, "elapsed_ms", time.Since(startCommit).Milliseconds())
		return err
	}
	slog.Info("flushNoteToDB: committed", "note_id", noteID, "elapsed_ms", time.Since(startCommit).Milliseconds(), "total_elapsed_ms", time.Since(startTx).Milliseconds())
	return nil
}

func (s *YDocService) ProjectCanonicalDoc(ctx context.Context, noteID string) error {
	if s.projection == nil {
		return nil
	}
	return s.projection.ProjectCanonicalDoc(ctx, noteID)
}

func (s *YDocService) FlushUpdates(ctx context.Context, noteID string) error {
	startSwap := time.Now()
	s.mu.Lock()
	updates := s.buffers[noteID]
	delete(s.buffers, noteID)
	s.mu.Unlock()

	if len(updates) == 0 {
		return nil
	}
	slog.Info("FlushUpdates: starting", "note_id", noteID, "updates", len(updates), "swap_ms", time.Since(startSwap).Milliseconds())

	startFlush := time.Now()
	if err := s.flushNoteToDB(ctx, noteID, updates); err != nil {
		s.mu.Lock()
		s.buffers[noteID] = append(updates, s.buffers[noteID]...)
		s.failureCount[noteID]++
		fc := s.failureCount[noteID]
		s.mu.Unlock()
		if fc == 3 || fc%20 == 0 {
			slog.Error("ydoc flush repeatedly failing",
				"note_id", noteID,
				"failure_count", fc,
				"error", err,
				"elapsed_ms", time.Since(startFlush).Milliseconds())
		}
		return err
	}
	s.mu.Lock()
	delete(s.failureCount, noteID)
	s.mu.Unlock()
	slog.Info("FlushUpdates: done", "note_id", noteID, "elapsed_ms", time.Since(startFlush).Milliseconds())
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

const maxConcurrentFlushes = 16

func (s *YDocService) flushAll(ctx context.Context) {
	s.mu.Lock()
	noteIDs := make([]string, 0, len(s.buffers))
	for id := range s.buffers {
		noteIDs = append(noteIDs, id)
	}
	s.mu.Unlock()

	sem := make(chan struct{}, maxConcurrentFlushes)
	var wg sync.WaitGroup
	for _, id := range noteIDs {
		wg.Add(1)
		id := id
		go func() {
			defer wg.Done()
			select {
			case sem <- struct{}{}:
				defer func() { <-sem }()
			case <-ctx.Done():
				return
			}
			_ = s.FlushUpdates(ctx, id)
		}()
	}
	wg.Wait()
}
