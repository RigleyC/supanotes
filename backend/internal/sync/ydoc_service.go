package sync

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"log/slog"
	"regexp"
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
	pool       *pgxpool.Pool
	projection projectionRunner
	machineID  string
	mu         sync.Mutex
	docs       map[string]*crdt.Doc
	docLocks   map[string]*sync.Mutex
	locksMu    sync.Mutex
}

func NewYDocService(pool *pgxpool.Pool, projection projectionRunner, machineID string) *YDocService {
	return &YDocService{
		pool:       pool,
		projection: projection,
		machineID:  machineID,
		docs:       make(map[string]*crdt.Doc),
		docLocks:   make(map[string]*sync.Mutex),
	}
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
		return // Ignore our own broadcast
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
		// Too large, fetch from DB
		update, err = LoadYDocState(ctx, s.pool, noteID)
		if err != nil {
			slog.Error("handleNotification: LoadYDocState failed", "error", err)
			return
		}
	}

	doc, err := s.DocFor(ctx, noteID)
	if err != nil {
		return
	}
	
	lock := s.getDocLock(noteID)
	lock.Lock()
	defer lock.Unlock()
	
	if err := crdt.ApplyUpdateV1(doc, update, "remote"); err != nil {
		slog.Error("handleNotification: ApplyUpdateV1 failed", "error", err)
		return
	}
	
	if s.projection != nil {
		s.projection.RunDebouncedProjection(ctx, noteID)
	}
}
