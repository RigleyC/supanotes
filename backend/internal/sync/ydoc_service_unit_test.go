//go:build !integration

package sync

import (
	"testing"

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
