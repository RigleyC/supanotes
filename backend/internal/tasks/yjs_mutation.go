package tasks

import (
	"context"
	"time"

	"github.com/reearth/ygo/crdt"
)

// yDocIngest is the minimal interface YDocService must satisfy for task mutations.
type yDocIngest interface {
	ApplyNodeMutation(ctx context.Context, noteID string, update []byte) error
	WithDoc(ctx context.Context, noteID string, fn func(doc *crdt.Doc) error) error
}

// CompleteTaskYjs completes a task by writing composite keys to the `nodes` YMap.
// Uses `$nodeId:completed` and `$nodeId:lastCompletedAt` composite keys
// (current schema). Does not read or rewrite the node entry itself, so it
// works with both YMap and string entries.
func CompleteTaskYjs(ctx context.Context, ydoc yDocIngest, noteID string, nodeID string) error {
	nowStr := time.Now().UTC().Format(time.RFC3339)

	mutDoc := crdt.New(crdt.WithGC(false))
	nodesMap := mutDoc.GetMap("nodes")
	mutDoc.Transact(func(txn *crdt.Transaction) {
		nodesMap.Set(txn, nodeID+":completed", true)
		nodesMap.Set(txn, nodeID+":lastCompletedAt", nowStr)
	})
	update := crdt.EncodeStateAsUpdateV1(mutDoc, nil)

	return ydoc.ApplyNodeMutation(ctx, noteID, update)
}
