package sync

import (
	"io"
	"log/slog"
	"sync/atomic"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestPermissionListenerRegisterAndUnregister(t *testing.T) {
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	pl := &PermissionListener{
		subs: make(map[permissionSub]func()),
		log:  log,
	}
	var called atomic.Int32
	unregister := pl.Register("note-1", "user-1", func() {
		called.Add(1)
	})
	require.Equal(t, 1, len(pl.subs))
	unregister()
	require.Equal(t, 0, len(pl.subs))
	pl.mu.RLock()
	for _, fn := range pl.subs {
		fn()
	}
	pl.mu.RUnlock()
	assert.Equal(t, int32(0), called.Load())
}

func TestPermissionListenerRegisterMultipleUsers(t *testing.T) {
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	pl := &PermissionListener{subs: make(map[permissionSub]func()), log: log}
	var calls atomic.Int32
	closeFn := func() { calls.Add(1) }
	pl.Register("n", "u1", closeFn)
	pl.Register("n", "u2", closeFn)
	pl.mu.RLock()
	for _, fn := range pl.subs {
		fn()
	}
	pl.mu.RUnlock()
	assert.Equal(t, int32(2), calls.Load())
}
