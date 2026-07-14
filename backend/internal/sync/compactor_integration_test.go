//go:build integration

package sync

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/reearth/ygo/crdt"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func insertNoteForCompactor(t *testing.T, ctx context.Context, pool *pgxpool.Pool, noteID string) {
	t.Helper()
	_, err := pool.Exec(ctx,
		`INSERT INTO notes (id, user_id, content, created_at) VALUES ($1, '00000000-0000-0000-0000-000000000000', '', NOW()) ON CONFLICT (id) DO NOTHING`,
		noteID,
	)
	require.NoError(t, err)
}

func insertYjsUpdate(t *testing.T, ctx context.Context, pool *pgxpool.Pool, noteID string, update []byte) {
	t.Helper()
	_, err := pool.Exec(ctx,
		`INSERT INTO note_yjs_updates (note_id, update_data) VALUES ($1, $2)`,
		noteID, update,
	)
	require.NoError(t, err)
}

func countYjsUpdates(t *testing.T, ctx context.Context, pool *pgxpool.Pool, noteID string) int {
	t.Helper()
	var count int
	err := pool.QueryRow(ctx, `SELECT COUNT(*) FROM note_yjs_updates WHERE note_id = $1`, noteID).Scan(&count)
	require.NoError(t, err)
	return count
}

func countYjsStates(t *testing.T, ctx context.Context, pool *pgxpool.Pool, noteID string) int {
	t.Helper()
	var count int
	err := pool.QueryRow(ctx, `SELECT COUNT(*) FROM note_yjs_states WHERE note_id = $1`, noteID).Scan(&count)
	require.NoError(t, err)
	return count
}

func makeTestUpdateWithText(t *testing.T, text string) []byte {
	t.Helper()
	doc := crdt.New(crdt.WithGC(false))
	textType := doc.GetText("content")
	doc.Transact(func(txn *crdt.Transaction) {
		textType.Insert(txn, 0, text, nil)
	})
	return crdt.EncodeStateAsUpdateV1(doc, nil)
}

func TestCompactorCompactNote(t *testing.T) {
	ctx := context.Background()
	pool := setupTestDB(t)
	compactor := NewCompactor(pool)

	noteID := uuid.New().String()
	insertNoteForCompactor(t, ctx, pool, noteID)

	// Create sequential deterministic updates:
	// update1: insert "hello " at 0
	// update2: insert "world" at 6 (full state after both inserts)
	doc := crdt.New(crdt.WithGC(false))
	textType := doc.GetText("content")
	doc.Transact(func(txn *crdt.Transaction) {
		textType.Insert(txn, 0, "hello ", nil)
	})
	update1 := crdt.EncodeStateAsUpdateV1(doc, nil)

	doc.Transact(func(txn *crdt.Transaction) {
		textType.Insert(txn, 6, "world", nil)
	})
	update2 := crdt.EncodeStateAsUpdateV1(doc, nil)

	insertYjsUpdate(t, ctx, pool, noteID, update1)
	insertYjsUpdate(t, ctx, pool, noteID, update2)
	t.Cleanup(func() {
		pool.Exec(ctx, "DELETE FROM note_yjs_updates WHERE note_id = $1", noteID)
		pool.Exec(ctx, "DELETE FROM note_yjs_states WHERE note_id = $1", noteID)
		pool.Exec(ctx, "DELETE FROM notes WHERE id = $1", noteID)
	})

	initialUpdateCount := countYjsUpdates(t, ctx, pool, noteID)
	assert.Equal(t, 2, initialUpdateCount, "should have 2 updates before compaction")

	err := compactor.CompactNote(ctx, noteID)
	require.NoError(t, err)

	updateCount := countYjsUpdates(t, ctx, pool, noteID)
	stateCount := countYjsStates(t, ctx, pool, noteID)

	assert.Equal(t, 0, updateCount, "all updates should be deleted after compaction")
	assert.Equal(t, 1, stateCount, "should have exactly one state row after compaction")

	var storedState []byte
	err = pool.QueryRow(ctx, "SELECT state FROM note_yjs_states WHERE note_id = $1", noteID).Scan(&storedState)
	require.NoError(t, err)
	require.NotEmpty(t, storedState, "merged state should not be empty")

	docMerged := crdt.New(crdt.WithGC(false))
	err = crdt.ApplyUpdateV1(docMerged, storedState, nil)
	require.NoError(t, err)
	assert.Equal(t, "hello world", docMerged.GetText("content").ToString(),
		"merged state should contain both text updates")
}

func TestCompactorCompactNoteEmpty(t *testing.T) {
	ctx := context.Background()
	pool := setupTestDB(t)
	compactor := NewCompactor(pool)

	noteID := uuid.New().String()
	insertNoteForCompactor(t, ctx, pool, noteID)
	t.Cleanup(func() {
		pool.Exec(ctx, "DELETE FROM notes WHERE id = $1", noteID)
	})

	err := compactor.CompactNote(ctx, noteID)
	require.NoError(t, err, "compacting a note with no updates should not error")
}

func TestCompactorCompactAll(t *testing.T) {
	ctx := context.Background()
	pool := setupTestDB(t)
	compactor := NewCompactor(pool)

	noteID1 := uuid.New().String()
	noteID2 := uuid.New().String()
	insertNoteForCompactor(t, ctx, pool, noteID1)
	insertNoteForCompactor(t, ctx, pool, noteID2)

	update1 := makeTestUpdateWithText(t, "note one")
	update2 := makeTestUpdateWithText(t, "note two")
	insertYjsUpdate(t, ctx, pool, noteID1, update1)
	insertYjsUpdate(t, ctx, pool, noteID2, update2)
	t.Cleanup(func() {
		pool.Exec(ctx, "DELETE FROM note_yjs_updates WHERE note_id IN ($1, $2)", noteID1, noteID2)
		pool.Exec(ctx, "DELETE FROM note_yjs_states WHERE note_id IN ($1, $2)", noteID1, noteID2)
		pool.Exec(ctx, "DELETE FROM notes WHERE id IN ($1, $2)", noteID1, noteID2)
	})

	err := compactor.CompactAll(ctx)
	require.NoError(t, err)

	assert.Equal(t, 0, countYjsUpdates(t, ctx, pool, noteID1), "note1 updates should be deleted")
	assert.Equal(t, 0, countYjsUpdates(t, ctx, pool, noteID2), "note2 updates should be deleted")
	assert.Equal(t, 1, countYjsStates(t, ctx, pool, noteID1), "note1 should have a state row")
	assert.Equal(t, 1, countYjsStates(t, ctx, pool, noteID2), "note2 should have a state row")
}

func TestCompactorCompactAllWithNoUpdates(t *testing.T) {
	ctx := context.Background()
	pool := setupTestDB(t)
	compactor := NewCompactor(pool)

	err := compactor.CompactAll(ctx)
	require.NoError(t, err, "CompactAll with no updates should not error")
}

func TestCompactorRunDebouncedProjectionProjects(t *testing.T) {
	ctx := context.Background()
	pool := setupTestDB(t)
	compactor := NewCompactor(pool)
	ydocSvc := NewYDocService(pool, compactor)
	noteID := uuid.New().String()
	insertNoteForCompactor(t, ctx, pool, noteID)
	t.Cleanup(func() {
		pool.Exec(ctx, "DELETE FROM note_yjs_updates WHERE note_id = $1", noteID)
		pool.Exec(ctx, "DELETE FROM note_yjs_states WHERE note_id = $1", noteID)
		pool.Exec(ctx, "DELETE FROM notes WHERE id = $1", noteID)
	})

	nodeID := uuid.New().String()
	doc := crdt.New(crdt.WithGC(false))
	textNode := doc.GetText("content/" + nodeID)
	nodesMap := doc.GetMap("nodes")
	doc.Transact(func(txn *crdt.Transaction) {
		nd, _ := json.Marshal(map[string]any{
			"id":       nodeID,
			"position": 0.0,
			"type":     "paragraph",
			"data":     map[string]string{"text": "hi"},
		})
		nodesMap.Set(txn, nodeID, string(nd))
		textNode.Insert(txn, 0, "hi", nil)
	})
	update := crdt.EncodeStateAsUpdateV1(doc, nil)

	require.NoError(t, compactor.RunDebouncedProjectionForTest(ctx, ydocSvc, noteID, update))

	var content string
	require.NoError(t, pool.QueryRow(ctx, "SELECT content FROM notes WHERE id = $1", noteID).Scan(&content))
	assert.Equal(t, "hi", content)
}

func TestCompactorStartScheduler(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	pool := setupTestDB(t)
	compactor := NewCompactor(pool)

	noteID := uuid.New().String()
	insertNoteForCompactor(t, ctx, pool, noteID)

	update := makeTestUpdateWithText(t, "scheduled compaction")
	insertYjsUpdate(t, ctx, pool, noteID, update)
	t.Cleanup(func() {
		pool.Exec(ctx, "DELETE FROM note_yjs_updates WHERE note_id = $1", noteID)
		pool.Exec(ctx, "DELETE FROM note_yjs_states WHERE note_id = $1", noteID)
		pool.Exec(ctx, "DELETE FROM notes WHERE id = $1", noteID)
	})

	compactor.StartScheduler(ctx, 100*time.Millisecond)

	require.Eventually(t, func() bool {
		updates := countYjsUpdates(t, ctx, pool, noteID)
		states := countYjsStates(t, ctx, pool, noteID)
		return updates == 0 && states == 1
	}, 3*time.Second, 100*time.Millisecond,
		"expected scheduler to compact updates within 3s")
}
