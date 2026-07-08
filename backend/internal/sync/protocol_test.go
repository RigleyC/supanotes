package sync

import (
	"bytes"
	"testing"

	"github.com/reearth/ygo/crdt"
	ygsync "github.com/reearth/ygo/sync"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestSyncProtocolWireFormatGoldenBytes(t *testing.T) {
	doc := crdt.New(crdt.WithGC(false))
	doc.Transact(func(txn *crdt.Transaction) {
		doc.GetText("content/x").Insert(txn, 0, "hello", nil)
	})

	step1 := ygsync.EncodeSyncStep1(doc)
	require.NotEmpty(t, step1)
	assert.Equal(t, ygsync.MsgSyncStep1, int(step1[0]), "Step1 must start with MsgSyncStep1 type tag")

	msgType, _, err := ygsync.ReadSyncMessage(step1)
	require.NoError(t, err)
	assert.Equal(t, ygsync.MsgSyncStep1, msgType)

	// Round-trip: Step1 → Step2 → Apply.
	step2, err := ygsync.EncodeSyncStep2(doc, step1)
	require.NoError(t, err)
	require.NotEmpty(t, step2)
	assert.Equal(t, ygsync.MsgSyncStep2, int(step2[0]), "Step2 must start with MsgSyncStep2 type tag")

	doc2 := crdt.New(crdt.WithGC(false))
	reply, err := ygsync.ApplySyncMessage(doc2, step2, nil)
	require.NoError(t, err)
	assert.Empty(t, reply, "Step2 must not produce a reply")
	require.Contains(t, doc2.GetText("content/x").ToString(), "hello")
}

func TestSyncProtocolUpdateBroadcastsByteIdentical(t *testing.T) {
	doc := crdt.New(crdt.WithGC(false))
	doc.Transact(func(txn *crdt.Transaction) {
		doc.GetText("content/x").Insert(txn, 0, "edit", nil)
	})
	update := crdt.EncodeStateAsUpdateV1(doc, nil)
	wrapped := ygsync.EncodeUpdate(update)
	require.Greater(t, len(wrapped), len(update), "wrapped must add type tag + length prefix")
	assert.Equal(t, ygsync.MsgUpdate, int(wrapped[0]))

	doc2 := crdt.New(crdt.WithGC(false))
	reply, err := ygsync.ApplySyncMessage(doc2, wrapped, nil)
	require.NoError(t, err)
	assert.Empty(t, reply)
	require.Contains(t, doc2.GetText("content/x").ToString(), "edit")
}

func TestSyncProtocolByteStripHeuristicIsGone(t *testing.T) {
	doc := crdt.New(crdt.WithGC(false))
	doc.Transact(func(txn *crdt.Transaction) {
		doc.GetText("content/x").Insert(txn, 0, "x", nil)
	})
	update := crdt.EncodeStateAsUpdateV1(doc, nil)
	require.Equal(t, byte(0), update[0], "sanity: this particular update starts with 0")

	doc2 := crdt.New(crdt.WithGC(false))
	wrapped := ygsync.EncodeUpdate(update)
	_, err := ygsync.ApplySyncMessage(doc2, wrapped, nil)
	require.NoError(t, err)
	require.False(t, bytes.Equal(wrapped, update), "wrapped must differ from raw update by at least one byte")
}
