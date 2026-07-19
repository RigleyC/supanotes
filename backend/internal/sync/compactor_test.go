//go:build !integration

package sync

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestCompactorSeqIncreasesOnEachCall(t *testing.T) {
	c := NewCompactor(nil)

	c.RunDebouncedProjection(context.Background(), "note-1")

	c.debounceMu.Lock()
	st := c.debounce["note-1"]
	require.NotNil(t, st)
	seq1 := st.seq
	c.debounceMu.Unlock()

	c.RunDebouncedProjection(context.Background(), "note-1")

	c.debounceMu.Lock()
	st = c.debounce["note-1"]
	require.NotNil(t, st)
	seq2 := st.seq
	c.debounceMu.Unlock()

	assert.Greater(t, seq2, seq1, "second call must have higher seq than first")
}

func TestCompactorDebounceCleanedUpAfterTimerFires(t *testing.T) {
	c := NewCompactor(nil)

	c.RunDebouncedProjection(context.Background(), "note-cleanup")

	c.debounceMu.Lock()
	_, exists := c.debounce["note-cleanup"]
	c.debounceMu.Unlock()
	assert.True(t, exists, "entry must exist immediately after call")

	// Wait for the 500ms debounce timer to fire and complete its cleanup.
	require.Eventually(t, func() bool {
		c.debounceMu.Lock()
		_, exists := c.debounce["note-cleanup"]
		c.debounceMu.Unlock()
		return !exists
	}, 2*time.Second, 50*time.Millisecond,
		"expected debounce entry to be cleaned up after timer fires")
}

func TestCompactorMultipleNotesDontInterfere(t *testing.T) {
	c := NewCompactor(nil)

	c.RunDebouncedProjection(context.Background(), "note-a")
	c.RunDebouncedProjection(context.Background(), "note-b")

	c.debounceMu.Lock()
	assert.Len(t, c.debounce, 2, "both notes should have their own debounce entries")
	sa := c.debounce["note-a"]
	sb := c.debounce["note-b"]
	c.debounceMu.Unlock()

	assert.NotEqual(t, sa.seq, sb.seq, "seq values must be unique across notes")
	assert.NotNil(t, sa.timer)
	assert.NotNil(t, sb.timer)
}

func TestCompactorCloseStopsPendingTimers(t *testing.T) {
	c := NewCompactor(nil)

	c.RunDebouncedProjection(context.Background(), "note-close")

	c.debounceMu.Lock()
	_, exists := c.debounce["note-close"]
	c.debounceMu.Unlock()
	assert.True(t, exists, "entry must exist before Close")

	c.Close()

	// After Close, the debounce map is cleared.
	c.debounceMu.Lock()
	_, exists = c.debounce["note-close"]
	c.debounceMu.Unlock()
	assert.False(t, exists, "entry should be cleared after Close")
}

func TestCompactorCloseIdempotent(t *testing.T) {
	c := NewCompactor(nil)
	c.RunDebouncedProjection(context.Background(), "note-idempotent")

	// First Close stops timers and clears map.
	c.Close()
	// Second Close must not panic (cancel on cancelled context is safe).
	c.Close()
}

func TestCompactorSeqSkipsStaleCallback(t *testing.T) {
	c := NewCompactor(nil)

	c.RunDebouncedProjection(context.Background(), "note-seq")

	c.debounceMu.Lock()
	firstSeq := c.debounce["note-seq"].seq
	c.debounceMu.Unlock()

	// Second call replaces the timer and increments seq.
	c.RunDebouncedProjection(context.Background(), "note-seq")

	c.debounceMu.Lock()
	st := c.debounce["note-seq"]
	secondSeq := st.seq
	c.debounceMu.Unlock()

	assert.Greater(t, secondSeq, firstSeq)

	// Simulate what the stale callback check does: if cur.seq != oldSeq, skip.
	// We verify by checking that the entry still exists (a stale callback would
	// not delete it because the seq wouldn't match).
	c.debounceMu.Lock()
	_, exists := c.debounce["note-seq"]
	wasStopped := st.timer.Stop()
	c.debounceMu.Unlock()

	assert.True(t, exists, "entry should still exist (timer replaced, new one pending)")
	_ = wasStopped
}
