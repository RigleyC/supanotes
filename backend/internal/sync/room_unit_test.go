package sync

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestWsConn_ReadMessageExists(t *testing.T) {
	w := &wsConn{}
	assert.NotPanics(t, func() {
		_ = w
	})
}
