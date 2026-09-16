package mcpapp

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/google/uuid"
)

type idToolArgs struct {
	ID string `json:"id"`
}

type emptyToolArgs struct{}

type destructiveIDToolArgs struct {
	ID             string `json:"id"`
	ConfirmationID string `json:"confirmation_id,omitempty"`
}

type listNotesToolArgs struct {
	Limit           *int32 `json:"limit,omitempty"`
	CursorUpdatedAt string `json:"cursor_updated_at,omitempty"`
	CursorID        string `json:"cursor_id,omitempty"`
}

type noteRevisionToolArgs struct {
	NoteID        string `json:"note_id"`
	AfterRevision *int64 `json:"after_revision,omitempty"`
}

type noteContentToolArgs struct {
	Content string `json:"content"`
}

type updateBlockToolArgs struct {
	NoteID         string          `json:"note_id"`
	BlockID        string          `json:"block_id,omitempty"`
	BaseRevision   *int64          `json:"base_revision"`
	Payload        json.RawMessage `json:"payload,omitempty"`
	OperationID    string          `json:"operation_id,omitempty"`
	ClientID       string          `json:"client_id,omitempty"`
	ConfirmationID string          `json:"confirmation_id,omitempty"`
}

type taskOccurrenceToolArgs struct {
	NoteID         string  `json:"note_id"`
	BlockID        string  `json:"block_id"`
	BaseRevision   *int64  `json:"base_revision"`
	ScheduledAt    string  `json:"scheduled_at"`
	CompletedAt    *string `json:"completed_at,omitempty"`
	OperationID    string  `json:"operation_id,omitempty"`
	ConfirmationID string  `json:"confirmation_id,omitempty"`
}

type attachmentUploadToolArgs struct {
	NoteID        string `json:"note_id"`
	Filename      string `json:"filename"`
	ContentBase64 string `json:"content_base64"`
}

type attachmentDeleteToolArgs struct {
	AttachmentID   string `json:"attachment_id"`
	ConfirmationID string `json:"confirmation_id,omitempty"`
}

type shareNoteToolArgs struct {
	NoteID         string `json:"note_id"`
	Email          string `json:"email"`
	Permission     string `json:"permission"`
	ConfirmationID string `json:"confirmation_id,omitempty"`
}

type removeNoteShareToolArgs struct {
	NoteID         string `json:"note_id"`
	UserID         string `json:"user_id"`
	ConfirmationID string `json:"confirmation_id,omitempty"`
}

type updateSettingsToolArgs struct {
	Timezone    string         `json:"timezone,omitempty"`
	Preferences map[string]any `json:"preferences,omitempty"`
}

func requiredToolString(value, name string) (string, error) {
	value = strings.TrimSpace(value)
	if value == "" {
		return "", fmt.Errorf("%s is required", name)
	}
	return value, nil
}

func toolUUID(value, name string) (string, error) {
	value, err := requiredToolString(value, name)
	if err != nil {
		return "", err
	}
	if _, err := uuid.Parse(value); err != nil {
		return "", fmt.Errorf("%s must be a UUID", name)
	}
	return value, nil
}

func toolOperationID(value string) (string, error) {
	if strings.TrimSpace(value) == "" {
		return uuid.NewString(), nil
	}
	if _, err := uuid.Parse(value); err != nil {
		return "", fmt.Errorf("operation_id must be a UUID")
	}
	return value, nil
}

func toolBaseRevision(value *int64) (int64, error) {
	if value == nil || *value < 0 {
		return 0, fmt.Errorf("base_revision is required and must be non-negative")
	}
	return *value, nil
}

func toolPermission(value string) (string, error) {
	value = strings.TrimSpace(value)
	if value != "view" && value != "edit" {
		return "", fmt.Errorf("permission must be view or edit")
	}
	return value, nil
}
