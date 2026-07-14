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

// CompleteTaskYjs completes a task by writing to both YMap("tasks") and YMap("nodes").
// Under the P4 two-level CRDT schema, task completion state lives in YMap("tasks"),
// not in the node data. The projection pipeline reads from YMap("tasks") and syncs
// to the tasks and task_completions tables.
//
// For legacy (pre-P4) docs that lack a YMap("tasks") entry, this function creates one,
// effectively migrating the doc on completion.
func CompleteTaskYjs(ctx context.Context, ydoc yDocIngest, noteID string, nodeID string) error {
	var rawNodeJSON string
	var title string
	var existingTaskData map[string]interface{}
	var hasTask bool

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

		// Read title from YText (outside Transact, safe)
		if textType := doc.GetText("content/" + nodeID); textType != nil {
			title = textType.ToString()
		}

		// Read existing task entry from YMap("tasks") if present (P4 schema)
		if tasksMap := doc.GetMap("tasks"); tasksMap != nil {
			if rawTask, ok := tasksMap.Get(nodeID); ok {
				if taskStr, ok := rawTask.(string); ok {
					if err := json.Unmarshal([]byte(taskStr), &existingTaskData); err == nil {
						hasTask = true
					}
				}
			}
		}

		return nil
	})
	if err != nil {
		return err
	}

	// Build task entry for YMap("tasks")
	now := time.Now().UTC()
	taskEntry := map[string]interface{}{
		"nodeId":          nodeID,
		"title":           title,
		"completed":       true,
		"dueDate":         "",
		"recurrence":      "",
		"lastCompletedAt": now.Format(time.RFC3339),
	}

	// Preserve existing dueDate and recurrence if the task entry already exists
	if hasTask {
		if dueDate, ok := existingTaskData["dueDate"]; ok {
			if ds, ok := dueDate.(string); ok && ds != "" {
				taskEntry["dueDate"] = ds
			}
		}
		if recurrence, ok := existingTaskData["recurrence"]; ok {
			if rs, ok := recurrence.(string); ok && rs != "" {
				taskEntry["recurrence"] = rs
			}
		}
	}

	taskJSON, err := json.Marshal(taskEntry)
	if err != nil {
		return fmt.Errorf("marshal task entry: %w", err)
	}

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

	// Create a mutation doc with both the task entry and updated node
	mutDoc := crdt.New(crdt.WithGC(false))
	mutDoc.Transact(func(txn *crdt.Transaction) {
		mutDoc.GetMap("tasks").Set(txn, nodeID, string(taskJSON))
		mutDoc.GetMap("nodes").Set(txn, nodeID, string(updatedNodeJSON))
	})
	update := crdt.EncodeStateAsUpdateV1(mutDoc, nil)

	return ydoc.ApplyNodeMutation(ctx, noteID, update)
}
