package sync

import (
	"encoding/json"
	"time"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/reearth/ygo/crdt"
)

type projectedTask struct {
	ID          pgtype.UUID
	UserID      pgtype.UUID
	Title       string
	Status      string
	Position    string
	Recurrence  pgtype.Text
	DueDate     pgtype.Date
	CompletedAt pgtype.Timestamptz
	CreatedAt   pgtype.Timestamptz
}

type taskDataEntry struct {
	NodeID        string `json:"nodeId"`
	Title         string `json:"title"`
	Completed     bool   `json:"completed"`
	DueDate       string `json:"dueDate"`
	Recurrence    string `json:"recurrence"`
	LastCompleted string `json:"lastCompletedAt"`
}

// readTaskFromYMap reads task state from YMap("tasks") for the given nodeID.
// Returns nil if the entry doesn't exist or can't be parsed.
func readTaskFromYMap(doc *crdt.Doc, nodeID string) *taskDataEntry {
	tasksMap := doc.GetMap("tasks")
	if tasksMap == nil {
		return nil
	}
	raw, ok := tasksMap.Get(nodeID)
	if !ok {
		return nil
	}
	rawStr, ok := raw.(string)
	if !ok {
		return nil
	}
	var entry taskDataEntry
	if err := json.Unmarshal([]byte(rawStr), &entry); err != nil {
		return nil
	}
	return &entry
}

func writeTaskEntry(doc *crdt.Doc, taskID string, entry taskDataEntry) {
	tasksMap := doc.GetMap("tasks")
	if tasksMap == nil {
		return
	}
	data, _ := json.Marshal(entry)
	doc.Transact(func(txn *crdt.Transaction) {
		tasksMap.Set(txn, taskID, string(data))
	})
}

func readTaskCompleted(doc *crdt.Doc, key string) bool {
	if entry := readTaskFromYMap(doc, key); entry != nil {
		return entry.Completed
	}
	nodesMap := doc.GetMap("nodes")
	if nodesMap == nil {
		return false
	}
	rawNode, ok := nodesMap.Get(key)
	if !ok {
		return false
	}
	nodeStr, ok := rawNode.(string)
	if !ok {
		return false
	}
	var nd struct {
		Data struct {
			Completed bool `json:"completed"`
		} `json:"data"`
	}
	if json.Unmarshal([]byte(nodeStr), &nd) != nil {
		return false
	}
	return nd.Data.Completed
}

func deriveTasksFromDoc(doc *crdt.Doc) []projectedTask {
	entries := nodesFromDoc(doc)

	var tasks []projectedTask
	for _, nd := range entries {
		if nd.Type != "task" {
			continue
		}

		var dataMap map[string]interface{}
		if err := json.Unmarshal(nd.Data, &dataMap); err != nil {
			continue
		}

		taskUUID, err := parseUUIDStr(nd.ID)
		if err != nil {
			continue
		}

		// Read from YMap("tasks") first (P4 schema), fall back to node data (legacy)
		taskEntry := readTaskFromYMap(doc, nd.ID)

		completed := false
		if taskEntry != nil {
			completed = taskEntry.Completed
		} else if c, ok := dataMap["completed"].(bool); ok {
			completed = c
		}

		status := "open"
		if completed {
			status = "done"
		}

		var dueDate pgtype.Date
		if taskEntry != nil && taskEntry.DueDate != "" {
			t, err := time.Parse("2006-01-02", taskEntry.DueDate)
			if err == nil {
				dueDate = pgtype.Date{Time: t, Valid: true}
			}
		} else if dd, ok := dataMap["dueDate"].(string); ok && dd != "" {
			t, err := time.Parse("2006-01-02", dd)
			if err == nil {
				dueDate = pgtype.Date{Time: t, Valid: true}
			}
		}

		var recurrence pgtype.Text
		if taskEntry != nil && taskEntry.Recurrence != "" {
			recurrence = pgtype.Text{String: taskEntry.Recurrence, Valid: true}
		} else if rec, ok := dataMap["recurrence"].(string); ok && rec != "" {
			recurrence = pgtype.Text{String: rec, Valid: true}
		}

		var completedAt pgtype.Timestamptz
		if taskEntry != nil && taskEntry.LastCompleted != "" {
			t, err := time.Parse(time.RFC3339, taskEntry.LastCompleted)
			if err == nil {
				completedAt = pgtype.Timestamptz{Time: t, Valid: true}
			}
		}
		if lc, ok := dataMap["lastCompletedAt"].(string); ok && lc != "" && !completedAt.Valid {
			t, err := time.Parse(time.RFC3339, lc)
			if err == nil {
				completedAt = pgtype.Timestamptz{Time: t, Valid: true}
			}
		}
		if !completedAt.Valid && completed {
			completedAt = pgtype.Timestamptz{Time: time.Now(), Valid: true}
		}

		tasks = append(tasks, projectedTask{
			ID:          taskUUID,
			Title:       nd.Text,
			Status:      status,
			Position:    nd.Position,
			Recurrence:  recurrence,
			DueDate:     dueDate,
			CompletedAt: completedAt,
			CreatedAt:   pgtype.Timestamptz{Time: time.Now(), Valid: true},
		})
	}

	return tasks
}
