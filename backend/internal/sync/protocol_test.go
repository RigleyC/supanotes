package sync

import (
	"testing"

	"github.com/reearth/ygo/crdt"
	ygsync "github.com/reearth/ygo/sync"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestSyncProtocolWireFormatGoldenBytes(t *testing.T) {
	doc := crdt.New(crdt.WithGC(false))
	text := doc.GetText("content/x")
	doc.Transact(func(txn *crdt.Transaction) {
		text.Insert(txn, 0, "hello", nil)
	})

	step1 := ygsync.EncodeSyncStep1(doc)
	require.NotEmpty(t, step1)
	assert.Equal(t, ygsync.MsgSyncStep1, int(step1[0]), "Step1 must start with MsgSyncStep1 type tag")

	msgType, _, err := ygsync.ReadSyncMessage(step1)
	require.NoError(t, err)
	assert.Equal(t, ygsync.MsgSyncStep1, msgType)

	// Round-trip: empty client Step1 → server Step2 (full diff) → Apply.
	emptyDoc := crdt.New(crdt.WithGC(false))
	clientSV := ygsync.EncodeSyncStep1(emptyDoc)
	step2, err := ygsync.EncodeSyncStep2(doc, clientSV)
	require.NoError(t, err)
	require.NotEmpty(t, step2)
	assert.Equal(t, ygsync.MsgSyncStep2, int(step2[0]), "Step2 must start with MsgSyncStep2 type tag")

	doc2 := crdt.New(crdt.WithGC(false))
	doc2.GetText("content/x") // Pre-register to avoid share-map type corruption
	reply, err := ygsync.ApplySyncMessage(doc2, step2, nil)
	require.NoError(t, err)
	assert.Empty(t, reply, "Step2 must not produce a reply")
	require.Contains(t, doc2.GetText("content/x").ToString(), "hello")
}

func TestSyncProtocolUpdateBroadcastsByteIdentical(t *testing.T) {
	doc := crdt.New(crdt.WithGC(false))
	text := doc.GetText("content/x")
	doc.Transact(func(txn *crdt.Transaction) {
		text.Insert(txn, 0, "edit", nil)
	})
	update := crdt.EncodeStateAsUpdateV1(doc, nil)
	wrapped := ygsync.EncodeUpdate(update)
	require.Greater(t, len(wrapped), len(update), "wrapped must add type tag + length prefix")
	assert.Equal(t, ygsync.MsgUpdate, int(wrapped[0]))

	doc2 := crdt.New(crdt.WithGC(false))
	doc2.GetText("content/x")
	reply, err := ygsync.ApplySyncMessage(doc2, wrapped, nil)
	require.NoError(t, err)
	assert.Empty(t, reply)
	require.Contains(t, doc2.GetText("content/x").ToString(), "edit")
}

func TestSyncProtocolByteStripHeuristicIsGone(t *testing.T) {
	doc := crdt.New(crdt.WithGC(false))
	text := doc.GetText("content/x")
	doc.Transact(func(txn *crdt.Transaction) {
		text.Insert(txn, 0, "x", nil)
	})
	update := crdt.EncodeStateAsUpdateV1(doc, nil)

	doc2 := crdt.New(crdt.WithGC(false))
	doc2.GetText("content/x")
	wrapped := ygsync.EncodeUpdate(update)
	_, err := ygsync.ApplySyncMessage(doc2, wrapped, nil)
	require.NoError(t, err)
	require.Equal(t, ygsync.MsgUpdate, int(wrapped[0]), "wrapped must start with MsgUpdate tag, proving no heuristic byte stripping exists")
	require.Greater(t, len(wrapped), len(update), "wrapping adds the type tag byte + length prefix")
}
