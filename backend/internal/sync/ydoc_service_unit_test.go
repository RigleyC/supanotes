package sync

import (
	"testing"

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
	_, err := mergeYjsUpdates([][]byte{{0}, {1}})
	_ = err
}
