//go:build !integration

package sync

import (
	"encoding/json"
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

func TestMigrateLegacyDoc(t *testing.T) {
	doc := crdt.New(crdt.WithGC(false))
	nodesMap := doc.GetMap("nodes")
	
	// Create a legacy node (JSON string)
	legacyNode := map[string]interface{}{
		"id":       "123",
		"type":     "task",
		"position": 1.0,
		"data": map[string]interface{}{
			"text":      "legacy task",
			"completed": true,
			"dueDate":   "2023-01-01",
		},
	}
	b, _ := json.Marshal(legacyNode)
	doc.Transact(func(txn *crdt.Transaction) {
		nodesMap.Set(txn, "123", string(b))
	})

	// Run migration
	MigrateLegacyDoc(doc)

	// Verify it was converted to YMap and fields extracted
	rawNode, ok := nodesMap.Get("123")
	require.True(t, ok)
	
	nodeMap, ok := rawNode.(*crdt.YMap)
	require.True(t, ok, "Legacy node should be converted to YMap")
	
	completed, ok := nodeMap.Get("completed")
	require.True(t, ok)
	assert.Equal(t, true, completed)
	
	dueDate, ok := nodeMap.Get("dueDate")
	require.True(t, ok)
	assert.Equal(t, "2023-01-01", dueDate)
	
	// Data should now be a stringified JSON without the top level fields
	dataStr, ok := nodeMap.Get("data")
	require.True(t, ok)
	assert.Contains(t, dataStr, "legacy task")
	assert.NotContains(t, dataStr, "completed")
}
