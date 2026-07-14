package sync

import (
	"context"
	"encoding/json"
	"log/slog"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/reearth/ygo/crdt"
)

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
// Both must be kept in sync. The migration:
//  1. Detects legacy schema (completed field in node data)
//  2. Moves completed/dueDate/recurrence/lastCompletedAt to YMap("tasks")
//  3. Removes these fields from node data
// Schema is: YMap("nodes") -> {...} with data:{taskId?} and YMap("tasks") -> {taskId: JSON{nodeId,completed,title,dueDate,recurrence,lastCompletedAt}}

type legacyNode struct {
	ID   string          `json:"id"`
	Type string          `json:"type"`
	Data json.RawMessage `json:"data"`
}

// MigrateLegacyDoc upgrades a legacy YDoc where task fields (completed, dueDate,
// recurrence, lastCompletedAt) are stored inline in the node `data` map.
// It moves these fields into YMap("tasks") entries and removes them from node data.
// Idempotent: skips if YMap("tasks") already has entries.
func MigrateLegacyDoc(doc *crdt.Doc) {
	tasksMap := doc.GetMap("tasks")
	if tasksMap != nil && len(tasksMap.Keys()) > 0 {
		return
	}

	nodesMap := doc.GetMap("nodes")
	if nodesMap == nil {
		return
	}

	needsMigration := false
	for _, key := range nodesMap.Keys() {
		raw, ok := nodesMap.Get(key)
		if !ok {
			continue
		}
		rawStr, ok := raw.(string)
		if !ok {
			continue
		}
		var nd legacyNode
		if err := json.Unmarshal([]byte(rawStr), &nd); err != nil {
			slog.Warn("MigrateLegacyDoc: decode error", "key", key, "error", err)
			continue
		}
		if nd.Type != "task" {
			continue
		}
		var dataMap map[string]interface{}
		if err := json.Unmarshal(nd.Data, &dataMap); err != nil {
			slog.Warn("MigrateLegacyDoc: decode error", "key", key, "error", err)
			continue
		}
		if _, ok := dataMap["completed"]; ok {
			needsMigration = true
			break
		}
	}

	if !needsMigration {
		return
	}

	slog.Info("MigrateLegacyDoc: migrating doc to P4 schema")
	if tasksMap == nil {
		tasksMap = doc.GetMap("tasks")
	}
	doc.Transact(func(txn *crdt.Transaction) {
		taskUpdates := make(map[string]string)
		nodeUpdates := make(map[string]string)

		for _, key := range nodesMap.Keys() {
			raw, ok := nodesMap.Get(key)
			if !ok {
				continue
			}
			rawStr, ok := raw.(string)
			if !ok {
				continue
			}
			var nd legacyNode
			if err := json.Unmarshal([]byte(rawStr), &nd); err != nil {
				slog.Warn("MigrateLegacyDoc: decode error", "key", key, "error", err)
				continue
			}
			if nd.Type != "task" {
				continue
			}
			var dataMap map[string]interface{}
			if err := json.Unmarshal(nd.Data, &dataMap); err != nil {
				slog.Warn("MigrateLegacyDoc: decode error", "key", key, "error", err)
				continue
			}
			completedVal, hasCompleted := dataMap["completed"]
			if !hasCompleted {
				continue
			}
			completed, _ := completedVal.(bool)

			entry := taskDataEntry{
				NodeID:    nd.ID,
				Completed: completed,
			}
			if titleType := doc.GetText("content/" + nd.ID); titleType != nil {
				entry.Title = titleType.ToString()
			}
			if dueDate, ok := dataMap["dueDate"].(string); ok {
				entry.DueDate = dueDate
			}
			if recurrence, ok := dataMap["recurrence"].(string); ok {
				entry.Recurrence = recurrence
			}
			if lastCompletedAt, ok := dataMap["lastCompletedAt"].(string); ok {
				entry.LastCompleted = lastCompletedAt
			}

			entryJSON, err := json.Marshal(entry)
			if err != nil {
				slog.Warn("MigrateLegacyDoc: marshal taskEntry error", "key", key, "error", err)
				continue
			}
			taskUpdates[nd.ID] = string(entryJSON)

			delete(dataMap, "completed")
			delete(dataMap, "dueDate")
			delete(dataMap, "recurrence")
			delete(dataMap, "lastCompletedAt")
			cleanedData, err := json.Marshal(dataMap)
			if err != nil {
				slog.Warn("MigrateLegacyDoc: marshal cleanedData error", "key", key, "error", err)
				continue
			}

			var updatedNode map[string]interface{}
			if err := json.Unmarshal([]byte(rawStr), &updatedNode); err != nil {
				slog.Warn("MigrateLegacyDoc: unmarshal updatedNode error", "key", key, "error", err)
				continue
			}
			updatedNode["data"] = string(cleanedData)
			updatedJSON, err := json.Marshal(updatedNode)
			if err != nil {
				slog.Warn("MigrateLegacyDoc: marshal updatedNode error", "key", key, "error", err)
				continue
			}
			nodeUpdates[key] = string(updatedJSON)
		}

		for k, v := range taskUpdates {
			tasksMap.Set(txn, k, v)
		}
		for k, v := range nodeUpdates {
			nodesMap.Set(txn, k, v)
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

	go s.roomMgr.BroadcastIfActive(noteID, update)

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
