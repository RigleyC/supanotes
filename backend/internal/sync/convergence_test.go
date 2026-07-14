package sync

import (
	"encoding/json"
	"testing"

	"github.com/google/uuid"
	"github.com/reearth/ygo/crdt"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func setNodeOnDoc(t *testing.T, doc *crdt.Doc, id, typ, position string, data map[string]any) {
	t.Helper()
	nodesMap := doc.GetMap("nodes")
	dataRaw, _ := json.Marshal(data)
	meta, _ := json.Marshal(map[string]any{
		"id":       id,
		"type":     typ,
		"position": position,
		"data":     json.RawMessage(dataRaw),
	})
	doc.Transact(func(txn *crdt.Transaction) {
		nodesMap.Set(txn, id, string(meta))
	})
}

func insertTextOnDoc(t *testing.T, doc *crdt.Doc, id, text string) {
	t.Helper()
	textType := doc.GetText("content/" + id)
	doc.Transact(func(txn *crdt.Transaction) {
		textType.Insert(txn, 0, text, nil)
	})
}

func newUUID(t *testing.T) string {
	t.Helper()
	return uuid.New().String()
}

func TestConvergenceTwoConcurrentEditsMerge(t *testing.T) {
	headerID := newUUID(t)
	paraID := newUUID(t)
	taskNodeID := newUUID(t)
	newParaID := newUUID(t)

	docOriginal := crdt.New(crdt.WithGC(false))
	setNodeOnDoc(t, docOriginal, headerID, "header", "a0", map[string]any{"text": "My Note"})
	setNodeOnDoc(t, docOriginal, paraID, "paragraph", "a1", map[string]any{"text": "Intro"})
	setNodeOnDoc(t, docOriginal, taskNodeID, "task", "a2", map[string]any{"text": "Buy milk"})
	insertTextOnDoc(t, docOriginal, headerID, "My Note")
	insertTextOnDoc(t, docOriginal, paraID, "Intro")
	insertTextOnDoc(t, docOriginal, taskNodeID, "Buy milk")

	state0 := crdt.EncodeStateAsUpdateV1(docOriginal, nil)
	sv0Bytes := crdt.EncodeStateVectorV1(docOriginal)
	sv0, err := crdt.DecodeStateVectorV1(sv0Bytes)
	require.NoError(t, err)

	docA := crdt.New(crdt.WithGC(false))
	require.NoError(t, crdt.ApplyUpdateV1(docA, state0, nil))
	setNodeOnDoc(t, docA, newParaID, "paragraph", "a3", map[string]any{"text": "New para"})
	insertTextOnDoc(t, docA, newParaID, "New para")
	updateA := crdt.EncodeStateAsUpdateV1(docA, sv0)

	docB := crdt.New(crdt.WithGC(false))
	require.NoError(t, crdt.ApplyUpdateV1(docB, state0, nil))
	setNodeOnDoc(t, docB, taskNodeID, "task", "a2", map[string]any{"text": "Buy milk", "completed": true, "lastCompletedAt": "2024-01-01T00:00:00Z"})
	updateB := crdt.EncodeStateAsUpdateV1(docB, sv0)

	merged, err := crdt.MergeUpdatesV1(updateA, updateB)
	require.NoError(t, err)

	require.NoError(t, crdt.ApplyUpdateV1(docOriginal, merged, nil))

	md := deriveMarkdownFromDoc(docOriginal)
	expectedMD := "# My Note\nIntro\n- [x] Buy milk\nNew para"
	assert.Equal(t, expectedMD, md)

	tasks := deriveTasksFromDoc(docOriginal)
	require.Len(t, tasks, 1)
	assert.Equal(t, "Buy milk", tasks[0].Title)
	assert.Equal(t, "done", tasks[0].Status)
	assert.True(t, tasks[0].CompletedAt.Valid, "CompletedAt should be valid for completed task")

	entries := nodesFromDoc(docOriginal)
	require.Len(t, entries, 4)
	assert.Equal(t, "My Note", entries[0].Text)
	assert.Equal(t, "Intro", entries[1].Text)
	assert.Equal(t, "Buy milk", entries[2].Text)
	assert.Equal(t, "New para", entries[3].Text)
}

func TestConvergenceTaskProjectionFromTwoLevelCRDT(t *testing.T) {
	taskNodeID := newUUID(t)

	doc := crdt.New(crdt.WithGC(false))
	setNodeOnDoc(t, doc, taskNodeID, "task", "a0", map[string]any{"text": "Write tests"})
	insertTextOnDoc(t, doc, taskNodeID, "Write tests")

	tasks := deriveTasksFromDoc(doc)
	require.Len(t, tasks, 1)
	assert.Equal(t, "Write tests", tasks[0].Title)
	assert.Equal(t, "open", tasks[0].Status)
	assert.False(t, tasks[0].CompletedAt.Valid, "CompletedAt should be invalid when not completed")

	md := deriveMarkdownFromDoc(doc)
	assert.Equal(t, "- [ ] Write tests", md)

	setNodeOnDoc(t, doc, taskNodeID, "task", "a0", map[string]any{"text": "Write tests", "completed": true, "lastCompletedAt": "2024-01-01T00:00:00Z"})

	tasksAfter := deriveTasksFromDoc(doc)
	require.Len(t, tasksAfter, 1)
	assert.Equal(t, "Write tests", tasksAfter[0].Title)
	assert.Equal(t, "done", tasksAfter[0].Status)
	assert.True(t, tasksAfter[0].CompletedAt.Valid, "CompletedAt should be valid after toggle")

	mdAfter := deriveMarkdownFromDoc(doc)
	assert.Equal(t, "- [x] Write tests", mdAfter)
}

func TestConvergenceDocTaskCompletedInNodeData(t *testing.T) {
	taskNodeID := newUUID(t)

	doc := crdt.New(crdt.WithGC(false))
	setNodeOnDoc(t, doc, taskNodeID, "task", "a0", map[string]any{"text": "legacy task", "completed": true})
	insertTextOnDoc(t, doc, taskNodeID, "legacy task")

	tasks := deriveTasksFromDoc(doc)
	require.Len(t, tasks, 1)
	assert.Equal(t, "legacy task", tasks[0].Title)
	assert.Equal(t, "done", tasks[0].Status)
	assert.True(t, tasks[0].CompletedAt.Valid, "CompletedAt should be valid for completed legacy task")

	md := deriveMarkdownFromDoc(doc)
	assert.Equal(t, "- [x] legacy task", md)
}