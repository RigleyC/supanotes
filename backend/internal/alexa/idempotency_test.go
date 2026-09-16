package alexa

import (
	"context"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestMemoryIdempotencyReplaysCompletedResponse(t *testing.T) {
	store := newMemoryIdempotencyStore(time.Minute, time.Minute)
	first, err := store.Acquire(context.Background(), "application", "request-123", "payload-hash")
	require.NoError(t, err)
	require.False(t, first.pending)

	want := speak("item foi adicionado")
	require.NoError(t, store.Complete(context.Background(), first.reservation, want))

	replay, err := store.Acquire(context.Background(), "application", "request-123", "payload-hash")
	require.NoError(t, err)
	require.NotNil(t, replay.response)
	require.Equal(t, want, *replay.response)
}

func TestMemoryIdempotencyRejectsPayloadReuse(t *testing.T) {
	store := newMemoryIdempotencyStore(time.Minute, time.Minute)
	first, err := store.Acquire(context.Background(), "application", "request-123", "payload-a")
	require.NoError(t, err)
	require.NoError(t, store.Complete(context.Background(), first.reservation, speak("done")))

	_, err = store.Acquire(context.Background(), "application", "request-123", "payload-b")
	require.ErrorIs(t, err, errRequestIDPayloadMismatch)
}

func TestMemoryIdempotencyAllowsOnlyOneConcurrentOwner(t *testing.T) {
	store := newMemoryIdempotencyStore(time.Minute, time.Minute)
	first, err := store.Acquire(context.Background(), "application", "request-123", "payload-hash")
	require.NoError(t, err)

	const callers = 16
	decisions := make(chan idempotencyDecision, callers)
	errors := make(chan error, callers)
	var waitGroup sync.WaitGroup
	for range callers {
		waitGroup.Add(1)
		go func() {
			defer waitGroup.Done()
			decision, acquireErr := store.Acquire(context.Background(), "application", "request-123", "payload-hash")
			decisions <- decision
			errors <- acquireErr
		}()
	}
	waitGroup.Wait()
	close(decisions)
	close(errors)

	for acquireErr := range errors {
		require.NoError(t, acquireErr)
	}
	for decision := range decisions {
		require.True(t, decision.pending)
	}

	require.NoError(t, store.Complete(context.Background(), first.reservation, speak("done")))
	replay, err := store.Acquire(context.Background(), "application", "request-123", "payload-hash")
	require.NoError(t, err)
	require.NotNil(t, replay.response)
}

func TestMemoryIdempotencyReclaimsExpiredLease(t *testing.T) {
	store := newMemoryIdempotencyStore(time.Minute, time.Second)
	now := time.Date(2026, 9, 16, 12, 0, 0, 0, time.UTC)
	store.now = func() time.Time { return now }

	first, err := store.Acquire(context.Background(), "application", "request-123", "payload-hash")
	require.NoError(t, err)
	now = now.Add(2 * time.Second)
	second, err := store.Acquire(context.Background(), "application", "request-123", "payload-hash")
	require.NoError(t, err)
	require.False(t, second.pending)
	require.NotEqual(t, first.reservation.ownerToken, second.reservation.ownerToken)

	require.NoError(t, store.Complete(context.Background(), second.reservation, speak("recovered")))
	replay, err := store.Acquire(context.Background(), "application", "request-123", "payload-hash")
	require.NoError(t, err)
	require.Equal(t, "recovered", replay.response.Response.OutputSpeech.Text)
}

func TestMemoryIdempotencyRejectsCompletionByPreviousOwner(t *testing.T) {
	store := newMemoryIdempotencyStore(time.Minute, time.Second)
	now := time.Date(2026, 9, 16, 12, 0, 0, 0, time.UTC)
	store.now = func() time.Time { return now }

	first, err := store.Acquire(context.Background(), "application", "request-123", "payload-hash")
	require.NoError(t, err)
	now = now.Add(2 * time.Second)
	second, err := store.Acquire(context.Background(), "application", "request-123", "payload-hash")
	require.NoError(t, err)

	require.ErrorIs(t, store.Complete(context.Background(), first.reservation, speak("stale")), errIdempotencyReservationLost)
	require.NoError(t, store.Complete(context.Background(), second.reservation, speak("current")))
}
