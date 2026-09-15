package tasks

import (
	"encoding/json"
	"time"

	"github.com/jackc/pgx/v5/pgtype"
)

type Mutation struct {
	OperationID        string          `json:"operationId" validate:"required"`
	ObservedRevision   int64           `json:"observedRevision"`
	ScheduleGeneration int64           `json:"scheduleGeneration"`
	Kind               string          `json:"kind" validate:"required"`
	Payload            json.RawMessage `json:"payload"`
}

type Task struct {
	ID                 string          `json:"id"`
	OwnerUserID        string          `json:"ownerUserId"`
	Title              string          `json:"title"`
	DueDate            *string         `json:"dueDate,omitempty"`
	HasTime            bool            `json:"hasTime"`
	RecurrenceRule     *string         `json:"recurrenceRule,omitempty"`
	Reminder           *string         `json:"reminder,omitempty"`
	Completions        json.RawMessage `json:"completions"`
	IsCompleted        bool            `json:"isCompleted"`
	LastCompletedAt    *string         `json:"lastCompletedAt,omitempty"`
	Revision           int64           `json:"revision"`
	ScheduleGeneration int64           `json:"scheduleGeneration"`
	CreatedAt          string          `json:"createdAt"`
	UpdatedAt          string          `json:"updatedAt"`
	DeletedAt          *string         `json:"deletedAt,omitempty"`
}

type MutationResult struct {
	OperationID string `json:"operationId"`
	Revision    int64  `json:"revision"`
	Task        Task   `json:"task"`
}

type BootstrapResult struct {
	Watermark int64  `json:"watermark"`
	Tasks     []Task `json:"tasks"`
}

type taskState struct {
	id                   pgtype.UUID
	owner                pgtype.UUID
	title                string
	dueDate              pgtype.Timestamp
	hasTime              bool
	recurrence, reminder pgtype.Text
	completions          []byte
	completed            bool
	lastCompleted        pgtype.Timestamptz
	revision, generation int64
	created, updated     pgtype.Timestamptz
	deleted              pgtype.Timestamptz
}

func formatTimestamp(v pgtype.Timestamptz) *string {
	if !v.Valid {
		return nil
	}
	s := v.Time.UTC().Format(time.RFC3339Nano)
	return &s
}
func formatDate(v pgtype.Timestamp) *string {
	if !v.Valid {
		return nil
	}
	s := v.Time.Format("2006-01-02T15:04:05.999999999")
	return &s
}
