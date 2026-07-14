package sync

import (
	"encoding/json"
	"testing"

	"github.com/reearth/ygo/crdt"
	"github.com/stretchr/testify/assert"
)

// makeNodeDoc creates a Doc with nodes at given (key, position, text) triples.
// Positions are set out-of-order to verify sorting.
func makeNodeDoc(t *testing.T, nodes []struct{ key, pos, typ, text string }) *crdt.Doc {
	t.Helper()
	doc := crdt.New(crdt.WithGC(false))
	nodesMap := doc.GetMap("nodes")
	doc.Transact(func(txn *crdt.Transaction) {
		for _, n := range nodes {
			raw, _ := json.Marshal(map[string]string{"text": n.text})
			meta, _ := json.Marshal(map[string]interface{}{
				"id":       n.key,
				"type":     n.typ,
				"position": n.pos,
				"data":     json.RawMessage(raw),
			})
			nodesMap.Set(txn, n.key, string(meta))
		}
	})
	for _, n := range nodes {
		if n.text != "" {
			textType := doc.GetText("content/" + n.key)
			doc.Transact(func(txn *crdt.Transaction) {
				textType.Insert(txn, 0, n.text, nil)
			})
		}
	}
	return doc
}

func TestMakeNodeDoc(t *testing.T) {
	doc := makeNodeDoc(t, []struct{ key, pos, typ, text string }{
		{key: "a", pos: "a0", typ: "paragraph", text: "hello"},
	})
	assert.NotNil(t, doc)
	textType := doc.GetText("content/a")
	assert.Equal(t, "hello", textType.ToString())
}

func TestNodesFromDoc_SortsByPosition(t *testing.T) {
	doc := makeNodeDoc(t, []struct{ key, pos, typ, text string }{
		{key: "c", pos: "z0", typ: "paragraph", text: "third"},
		{key: "a", pos: "a0", typ: "paragraph", text: "first"},
		{key: "b", pos: "m0", typ: "paragraph", text: "second"},
	})

	entries := nodesFromDoc(doc)
	assert.Len(t, entries, 3)
	assert.Equal(t, "first", entries[0].Text)
	assert.Equal(t, "second", entries[1].Text)
	assert.Equal(t, "third", entries[2].Text)
}

func TestDeriveMarkdownFromDoc_OrdersByPosition(t *testing.T) {
	doc := makeNodeDoc(t, []struct{ key, pos, typ, text string }{
		{key: "x", pos: "c0", typ: "paragraph", text: "middle"},
		{key: "y", pos: "a0", typ: "header", text: "Title"},
		{key: "z", pos: "z0", typ: "header", text: "Last"},
	})

	md := deriveMarkdownFromDoc(doc)
	expected := "# Title\nmiddle\n# Last"
	assert.Equal(t, expected, md)
}

func TestDeriveMarkdownFromDoc_PositionsCBA(t *testing.T) {
	doc := makeNodeDoc(t, []struct{ key, pos, typ, text string }{
		{key: "c", pos: "c", typ: "paragraph", text: "c content"},
		{key: "a", pos: "a", typ: "paragraph", text: "a content"},
		{key: "b", pos: "b", typ: "paragraph", text: "b content"},
	})

	md := deriveMarkdownFromDoc(doc)
	expected := "a content\nb content\nc content"
	assert.Equal(t, expected, md)
}

func TestDeriveTasksFromDoc_ReturnsSorted(t *testing.T) {
	doc := makeNodeDoc(t, []struct{ key, pos, typ, text string }{
		{key: "00000000-0000-0000-0000-000000000001", pos: "a0", typ: "task", text: "first task"},
		{key: "00000000-0000-0000-0000-000000000002", pos: "z0", typ: "task", text: "second task"},
		{key: "00000000-0000-0000-0000-000000000003", pos: "m0", typ: "paragraph", text: "not a task"},
	})

	tasks := deriveTasksFromDoc(doc)
	assert.Len(t, tasks, 2)
	assert.Equal(t, "first task", tasks[0].Title)
	assert.Equal(t, "second task", tasks[1].Title)
}
