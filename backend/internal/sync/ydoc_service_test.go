package sync

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/reearth/ygo/crdt"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestMergeYjsUpdates(t *testing.T) {
	doc1 := crdt.New()
	text1 := doc1.GetText("content")
	doc1.Transact(func(txn *crdt.Transaction) {
		text1.Insert(txn, 0, "hello", nil)
	})
	update1 := crdt.EncodeStateAsUpdateV1(doc1, nil)
	require.NotEmpty(t, update1)

	doc2 := crdt.New()
	text2 := doc2.GetText("content")
	doc2.Transact(func(txn *crdt.Transaction) {
		text2.Insert(txn, 5, " world", nil)
	})
	update2 := crdt.EncodeStateAsUpdateV1(doc2, nil)
	require.NotEmpty(t, update2)

	merged, err := mergeYjsUpdates([][]byte{update1, update2})
	require.NoError(t, err)
	require.NotEmpty(t, merged)

	assert.NotEqual(t, update1, merged)
	assert.NotEqual(t, update2, merged)

	doc3 := crdt.New()
	err = crdt.ApplyUpdateV1(doc3, merged, nil)
	require.NoError(t, err)

	text3 := doc3.GetText("content")
	assert.Equal(t, "hello world", text3.ToString())
}

func TestMergeYjsUpdates_Empty(t *testing.T) {
	merged, err := mergeYjsUpdates(nil)
	require.NoError(t, err)
	assert.Nil(t, merged)

	merged, err = mergeYjsUpdates([][]byte{})
	require.NoError(t, err)
	assert.Nil(t, merged)
}

func TestMergeYjsUpdates_Single(t *testing.T) {
	doc := crdt.New()
	doc.Transact(func(txn *crdt.Transaction) {
		doc.GetText("content").Insert(txn, 0, "single", nil)
	})
	update := crdt.EncodeStateAsUpdateV1(doc, nil)

	merged, err := mergeYjsUpdates([][]byte{update})
	require.NoError(t, err)
	assert.Equal(t, update, merged)
}

func TestYDocServiceFlush(t *testing.T) {
	pool := setupTestDB(t)
	svc := NewYDocService(pool)
	ctx := context.Background()

	noteID := uuid.New().String()
	_, err := pool.Exec(ctx, "INSERT INTO notes (id, user_id, content, created_at) VALUES ($1, '00000000-0000-0000-0000-000000000000', '', NOW())", noteID)
	require.NoError(t, err)
	t.Cleanup(func() {
		pool.Exec(ctx, "DELETE FROM notes WHERE id = $1", noteID)
	})

	doc1 := crdt.New()
	doc1.Transact(func(txn *crdt.Transaction) {
		doc1.GetText("content").Insert(txn, 0, "hello", nil)
	})
	update1 := crdt.EncodeStateAsUpdateV1(doc1, nil)

	doc2 := crdt.New()
	doc2.Transact(func(txn *crdt.Transaction) {
		doc2.GetText("content").Insert(txn, 5, " world", nil)
	})
	update2 := crdt.EncodeStateAsUpdateV1(doc2, nil)

	err = svc.ApplyNodeMutation(ctx, noteID, update1)
	require.NoError(t, err)
	err = svc.ApplyNodeMutation(ctx, noteID, update2)
	require.NoError(t, err)

	err = svc.FlushUpdates(ctx, noteID)
	require.NoError(t, err)

	var count int
	err = pool.QueryRow(ctx, "SELECT COUNT(*) FROM note_yjs_updates WHERE note_id = $1", noteID).Scan(&count)
	require.NoError(t, err)
	assert.Equal(t, 1, count)

	var storedUpdate []byte
	err = pool.QueryRow(ctx, "SELECT update_data FROM note_yjs_updates WHERE note_id = $1 ORDER BY created_at DESC LIMIT 1", noteID).Scan(&storedUpdate)
	require.NoError(t, err)
	require.NotEmpty(t, storedUpdate)

	doc3 := crdt.New()
	err = crdt.ApplyUpdateV1(doc3, storedUpdate, nil)
	require.NoError(t, err)
	assert.Equal(t, "hello world", doc3.GetText("content").ToString())
}

func TestYDocServiceFlush_EmptyBuffer(t *testing.T) {
	pool := setupTestDB(t)
	svc := NewYDocService(pool)
	ctx := context.Background()

	err := svc.FlushUpdates(ctx, "nonexistent-note")
	require.NoError(t, err)
}

func TestYDocServiceFlusher(t *testing.T) {
	pool := setupTestDB(t)
	svc := NewYDocService(pool)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	noteID := uuid.New().String()
	_, err := pool.Exec(ctx, "INSERT INTO notes (id, user_id, content, created_at) VALUES ($1, '00000000-0000-0000-0000-000000000000', '', NOW())", noteID)
	require.NoError(t, err)
	t.Cleanup(func() {
		pool.Exec(ctx, "DELETE FROM notes WHERE id = $1", noteID)
	})

	doc := crdt.New()
	doc.Transact(func(txn *crdt.Transaction) {
		doc.GetText("content").Insert(txn, 0, "flusher test", nil)
	})
	update := crdt.EncodeStateAsUpdateV1(doc, nil)
	require.NotEmpty(t, update)

	svc.StartFlusher(ctx, 50*time.Millisecond)

	err = svc.ApplyNodeMutation(ctx, noteID, update)
	require.NoError(t, err)

	require.Eventually(t, func() bool {
		var count int
		err := pool.QueryRow(ctx, "SELECT COUNT(*) FROM note_yjs_updates WHERE note_id = $1", noteID).Scan(&count)
		if err != nil {
			return false
		}
		return count == 1
	}, 2*time.Second, 50*time.Millisecond, "expected flusher to persist update within 2s")
}
