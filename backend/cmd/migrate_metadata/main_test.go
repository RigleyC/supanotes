package main

import (
	"encoding/json"
	"testing"

	"github.com/reearth/ygo/crdt"
	"github.com/stretchr/testify/assert"
)

func TestMetadataMigrationLogic(t *testing.T) {
	// 1. Create a doc with legacy metadata
	doc := crdt.New(crdt.WithGC(false))
	
	node1 := map[string]interface{}{
		"id": "node-1",
		"type": "task",
		"data": map[string]interface{}{
			"text": "Hello World",
			"completed": true,
			"dueDate": "2026-07-20",
		},
	}
	node1Bytes, _ := json.Marshal(node1)

	nodesMapSetup := doc.GetMap("nodes")
	tasksMapSetup := doc.GetMap("tasks")
	doc.Transact(func(txn *crdt.Transaction) {
		nodesMapSetup.Set(txn, "node-1", string(node1Bytes))
		// Create a legacy tasks map
		tasksMapSetup.Set(txn, "node-1", `{"title":"Hello World", "completed":true}`)
	})

	state := crdt.EncodeStateAsUpdateV1(doc, nil)

	// 2. Run the migration logic on the state
	migratedDoc := crdt.New(crdt.WithGC(false))
	migratedDoc.ApplyUpdate(state)

	mutDoc := crdt.New(crdt.WithGC(false))
	mutDoc.ApplyUpdate(state) // Copy for mutation

	nodesMap := mutDoc.GetMap("nodes")
	assert.NotNil(t, nodesMap)

	needsUpdate := false

	for key, raw := range nodesMap.Entries() {
		nodeStr, ok := raw.(string)
		if !ok {
			continue
		}

		var nodeData map[string]interface{}
		err := json.Unmarshal([]byte(nodeStr), &nodeData)
		assert.NoError(t, err)

		data, ok := nodeData["data"].(map[string]interface{})
		if !ok {
			continue
		}

		fieldsToMigrate := []string{"completed", "dueDate", "recurrence", "lastCompletedAt", "hasTime"}
		migratedAny := false

		for _, field := range fieldsToMigrate {
			if val, exists := data[field]; exists {
				nodesMapOut := mutDoc.GetMap("nodes")
				mutDoc.Transact(func(txn *crdt.Transaction) {
					nodesMapOut.Set(txn, key+":"+field, val)
				})
				delete(data, field)
				migratedAny = true
			}
		}

		if migratedAny {
			needsUpdate = true
			nodeData["data"] = data
			updatedJSON, _ := json.Marshal(nodeData)
			nodesMapOut := mutDoc.GetMap("nodes")
			mutDoc.Transact(func(txn *crdt.Transaction) {
				nodesMapOut.Set(txn, key, string(updatedJSON))
			})
		}
	}

	tasksMap := mutDoc.GetMap("tasks")
	if tasksMap != nil && len(tasksMap.Keys()) > 0 {
		needsUpdate = true
		tasksMapOut := mutDoc.GetMap("tasks")
		for _, key := range tasksMap.Keys() {
			mutDoc.Transact(func(txn *crdt.Transaction) {
				tasksMapOut.Delete(txn, key)
			})
		}
	}

	assert.True(t, needsUpdate)

	// Encode and verify the result
	updateBytes := crdt.EncodeStateAsUpdateV1(mutDoc, nil)
	migratedDoc.ApplyUpdate(updateBytes)

	finalNodes := migratedDoc.GetMap("nodes")
	
	// Verify composite keys are set
	compCompleted, ok := finalNodes.Get("node-1:completed")
	assert.True(t, ok)
	assert.Equal(t, true, compCompleted)

	compDueDate, ok := finalNodes.Get("node-1:dueDate")
	assert.True(t, ok)
	assert.Equal(t, "2026-07-20", compDueDate)

	// Verify legacy fields are gone from JSON
	rawNode, ok := finalNodes.Get("node-1")
	assert.True(t, ok)
	
	var finalData map[string]interface{}
	err := json.Unmarshal([]byte(rawNode.(string)), &finalData)
	assert.NoError(t, err)

	dataMap := finalData["data"].(map[string]interface{})
	_, ok = dataMap["completed"]
	assert.False(t, ok, "completed should be removed from JSON")
	_, ok = dataMap["dueDate"]
	assert.False(t, ok, "dueDate should be removed from JSON")

	// Verify tasks map is cleared
	finalTasks := migratedDoc.GetMap("tasks")
	assert.Empty(t, finalTasks.Keys(), "tasks map should be empty")
}
