package tasks

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/reearth/ygo/crdt"
)

// yDocIngest is the minimal interface YDocService must satisfy for task mutations.
type yDocIngest interface {
	ApplyNodeMutation(ctx context.Context, noteID string, update []byte) error
	WithDoc(ctx context.Context, noteID string, fn func(doc *crdt.Doc) error) error
}

// CompleteTaskYjs completes a task by writing to the `nodes` YMap directly using
// composite keys (`$nodeId:completed`, `$nodeId:lastCompletedAt`), which avoids
// a separate `tasks` map. This simplifies the projection pipeline and aligns with
// the dual-write avoidance rule.
func CompleteTaskYjs(ctx context.Context, ydoc yDocIngest, noteID string, nodeID string) error {
	var rawNodeJSON string

	err := ydoc.WithDoc(ctx, noteID, func(doc *crdt.Doc) error {
		nodesMap := doc.GetMap("nodes")
		if nodesMap == nil {
			return fmt.Errorf("nodes map not found in doc %s", noteID)
		}
		raw, ok := nodesMap.Get(nodeID)
		if !ok {
			return fmt.Errorf("node %s not found in doc %s", nodeID, noteID)
		}
		nodeStr, ok := raw.(string)
		if !ok {
			return fmt.Errorf("node %s is not a string", nodeID)
		}
		rawNodeJSON = nodeStr
		return nil
	})
	if err != nil {
		return err
	}

	nowStr := time.Now().UTC().Format(time.RFC3339)

	// Build updated node JSON with taskId pointing to the task entry
	var fullNode map[string]interface{}
	if err := json.Unmarshal([]byte(rawNodeJSON), &fullNode); err != nil {
		return fmt.Errorf("unmarshal full node: %w", err)
	}

	nodeData, ok := fullNode["data"].(map[string]interface{})
	if !ok {
		nodeData = make(map[string]interface{})
	}
	nodeData["taskId"] = nodeID
	nodeData["completed"] = true
	fullNode["data"] = nodeData

	updatedNodeJSON, err := json.Marshal(fullNode)
	if err != nil {
		return fmt.Errorf("marshal updated node: %w", err)
	}

	// Create a mutation doc to update the JSON payload and composite keys
	mutDoc := crdt.New(crdt.WithGC(false))
	nodesMap := mutDoc.GetMap("nodes")
	mutDoc.Transact(func(txn *crdt.Transaction) {
		nodesMap.Set(txn, nodeID, string(updatedNodeJSON))
		nodesMap.Set(txn, nodeID+":completed", true)
		nodesMap.Set(txn, nodeID+":lastCompletedAt", nowStr)
		// Clean up old tasks map entry if it existed?
		// We could do `mutDoc.GetMap("tasks").Delete(txn, nodeID)` but the migration
		// script will handle dropping the tasks map anyway.
	})
	update := crdt.EncodeStateAsUpdateV1(mutDoc, nil)

	return ydoc.ApplyNodeMutation(ctx, noteID, update)
}
