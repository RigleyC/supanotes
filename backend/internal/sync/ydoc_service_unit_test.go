//go:build !integration

package sync

import (
	"fmt"
	"sync/atomic"
	"testing"
	"time"

	"github.com/reearth/ygo/crdt"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestMergeYjsUpdates_Empty(t *testing.T) {
	result, err := mergeYjsUpdates(nil)
	require.NoError(t, err)
	assert.Nil(t, result)

	result, err = mergeYjsUpdates([][]byte{})
	require.NoError(t, err)
	assert.Nil(t, result)
}

func TestMergeYjsUpdates_Single(t *testing.T) {
	update := []byte{1, 2, 3}
	result, err := mergeYjsUpdates([][]byte{update})
	require.NoError(t, err)
	assert.Equal(t, update, result)
}

func TestMergeYjsUpdates_Multiple(t *testing.T) {
	doc1 := crdt.New(crdt.WithGC(false))
	text1 := doc1.GetText("content/a")
	doc1.Transact(func(txn *crdt.Transaction) {
		text1.Insert(txn, 0, "hi", nil)
	})
	update1 := crdt.EncodeStateAsUpdateV1(doc1, nil)

	doc2 := crdt.New(crdt.WithGC(false))
	text2 := doc2.GetText("content/b")
	doc2.Transact(func(txn *crdt.Transaction) {
		text2.Insert(txn, 0, "there", nil)
	})
	update2 := crdt.EncodeStateAsUpdateV1(doc2, nil)

	merged, err := mergeYjsUpdates([][]byte{update1, update2})
	require.NoError(t, err)
	require.NotEmpty(t, merged)
}

func TestPreRegisterYTextSupportsLegacyAndNonUUIDContentRoots(t *testing.T) {
	source := crdt.New(crdt.WithGC(false))
	for root, text := range map[string]string{
		"content/p1":       "paragraph with a short id",
		"content_fixed/p2": "legacy paragraph",
	} {
		ytext := source.GetText(root)
		source.Transact(func(txn *crdt.Transaction) {
			ytext.Insert(txn, 0, text, nil)
		})
	}

	update := crdt.EncodeStateAsUpdateV1(source, nil)
	target := crdt.New(crdt.WithGC(false))
	PreRegisterYText(target, update)
	require.NoError(t, crdt.ApplyUpdateV1(target, update, nil))

	assert.Equal(t, "paragraph with a short id", target.GetText("content/p1").ToString())
	assert.Equal(t, "legacy paragraph", target.GetText("content_fixed/p2").ToString())
}

func TestApplyYjsUpdateIfChangedIgnoresDuplicateUpdate(t *testing.T) {
	source := crdt.New(crdt.WithGC(false))
	source.GetText("content/node-1").Insert(nil, 0, "hello", nil)
	update := crdt.EncodeStateAsUpdateV1(source, nil)

	target := crdt.New(crdt.WithGC(false))
	changed, err := applyYjsUpdateIfChanged(target, update, "test")
	require.NoError(t, err)
	assert.True(t, changed)

	changed, err = applyYjsUpdateIfChanged(target, update, "test")
	require.NoError(t, err)
	assert.False(t, changed)
	assert.Equal(t, "hello", target.GetText("content/node-1").ToString())
}

func TestYDocServiceCloseIsIdempotent(t *testing.T) {
	svc := NewYDocService(nil, nil, "test", WithMaxCachedDocs(10))
	// First Close should cancel the context and wait for the goroutine.
	svc.Close()
	// Second Close must not panic — evictCancel on a cancelled context is safe.
	svc.Close()
}

func TestYDocServiceEvictLRURemovesOldest(t *testing.T) {
	svc := NewYDocService(nil, nil, "test", WithMaxCachedDocs(2))
	defer svc.Close()

	// Add 3 entries to the internal map.
	svc.mu.Lock()
	for i := 0; i < 3; i++ {
		id := fmt.Sprintf("note-%d", i)
		svc.notes[id] = &noteEntry{lastUsed: time.Now()}
	}
	svc.mu.Unlock()

	svc.mu.Lock()
	svc.evictLRU()
	svc.mu.Unlock()

	svc.mu.Lock()
	assert.Equal(t, 2, len(svc.notes), "evictLRU must reduce cache to maxCachedDocs")
	svc.mu.Unlock()
}

func TestYDocServiceEvictIdleRemovesStaleOnly(t *testing.T) {
	svc := NewYDocService(nil, nil, "test", WithMaxCachedDocs(10), WithIdleTTL(100*time.Millisecond))
	defer svc.Close()

	svc.mu.Lock()
	svc.notes["stale"] = &noteEntry{lastUsed: time.Now().Add(-1 * time.Hour)}
	svc.notes["fresh"] = &noteEntry{lastUsed: time.Now()}
	svc.mu.Unlock()

	svc.mu.Lock()
	svc.evictIdle()
	svc.mu.Unlock()

	svc.mu.Lock()
	assert.Equal(t, 1, len(svc.notes), "only fresh entry should survive evictIdle")
	_, exists := svc.notes["fresh"]
	assert.True(t, exists, "fresh entry must still be in cache")
	svc.mu.Unlock()
}

func TestYDocServiceLeaseProtectsFromEviction(t *testing.T) {
	svc := NewYDocService(nil, nil, "test", WithMaxCachedDocs(1))
	defer svc.Close()

	now := time.Now()
	svc.mu.Lock()
	svc.notes["leased"] = &noteEntry{
		lastUsed:   now.Add(-1 * time.Hour),
		leaseCount: 1, // active lease prevents eviction
	}
	svc.notes["idle"] = &noteEntry{
		lastUsed:   now.Add(-1 * time.Hour),
		leaseCount: 0, // no lease — eligible for eviction
	}
	svc.mu.Unlock()

	svc.mu.Lock()
	svc.evictIdle()
	svc.mu.Unlock()

	svc.mu.Lock()
	_, leasedExists := svc.notes["leased"]
	assert.True(t, leasedExists, "leased entry must survive eviction")
	_, idleExists := svc.notes["idle"]
	assert.False(t, idleExists, "idle entry without lease must be evicted")
	svc.mu.Unlock()
}

func TestYDocServiceAcquireReleaseLease(t *testing.T) {
	svc := NewYDocService(nil, nil, "test", WithMaxCachedDocs(10))
	defer svc.Close()

	entry := &noteEntry{}
	assert.Equal(t, int32(0), atomic.LoadInt32(&entry.leaseCount))

	svc.acquireLease(entry)
	assert.Equal(t, int32(1), atomic.LoadInt32(&entry.leaseCount))

	svc.releaseLease(entry)
	assert.Equal(t, int32(0), atomic.LoadInt32(&entry.leaseCount))
}
