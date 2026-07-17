package sync

import (
	"strings"
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

func deriveTasksFromDoc(doc *crdt.Doc) []projectedTask {
	entries := nodesFromDoc(doc)

	var tasks []projectedTask
	for _, nd := range entries {
		if nd.Type != "task" {
			continue
		}

		taskUUID, err := parseUUIDStr(nd.ID)
		if err != nil {
			continue
		}

		completed, _ := nd.Metadata["completed"].(bool)

		var dueDate pgtype.Date
		if dd, ok := nd.Metadata["dueDate"].(string); ok && dd != "" {
			if strings.Contains(dd, "T") {
				if t, err := time.Parse("2006-01-02T15:04", dd); err == nil {
					dueDate = pgtype.Date{Time: t, Valid: true}
				}
			} else {
				if t, err := time.Parse("2006-01-02", dd); err == nil {
					dueDate = pgtype.Date{Time: t, Valid: true}
				}
			}
		}

		var recurrence pgtype.Text
		if rec, ok := nd.Metadata["recurrence"].(string); ok && rec != "" {
			recurrence = pgtype.Text{String: rec, Valid: true}
		}

		var completedAt pgtype.Timestamptz
		if lc, ok := nd.Metadata["lastCompletedAt"].(string); ok && lc != "" {
			if t, err := time.Parse(time.RFC3339, lc); err == nil {
				completedAt = pgtype.Timestamptz{Time: t, Valid: true}
			}
		}

		status := "open"
		if completed {
			status = "done"
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
