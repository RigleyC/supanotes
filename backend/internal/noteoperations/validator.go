package noteoperations

import (
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"strings"
	"time"
)

var (
	ErrInvalidDelta             = errors.New("invalid delta")
	ErrBlockDeleted             = errors.New("block deleted")
	ErrInvalidAnchor            = errors.New("invalid anchor")
	ErrNoteDeleted              = errors.New("note deleted")
	ErrForbidden                = errors.New("forbidden")
	ErrSchemaVersionUnsupported = errors.New("schema version unsupported")
	ErrInvalidKind              = errors.New("invalid operation kind")
	ErrInvalidBlockID           = errors.New("invalid block id")
	ErrInvalidBlockType         = errors.New("invalid block type")
	ErrInvalidPayload           = errors.New("invalid payload")
)

type ValidationError struct {
	Code    string
	Message string
	Err     error
}

func (e *ValidationError) Error() string {
	if e.Err != nil {
		return fmt.Sprintf("%s: %s", e.Code, e.Err.Error())
	}
	return e.Code
}

func (e *ValidationError) Unwrap() error {
	return e.Err
}

func ValidateOperation(req OperationRequest, doc Document, baseRevision int64, currentRevision int64) *ValidationError {
	if !ValidKinds[Kind(req.Kind)] {
		return &ValidationError{
			Code:    "INVALID_KIND",
			Message: fmt.Sprintf("unknown kind: %s", req.Kind),
		}
	}

	if baseRevision < 0 {
		return &ValidationError{
			Code:    "INVALID_BASE_REVISION",
			Message: "base revision must be >= 0",
		}
	}

	if baseRevision > currentRevision {
		return &ValidationError{
			Code:    "INVALID_BASE_REVISION",
			Message: fmt.Sprintf("base revision %d > current revision %d", baseRevision, currentRevision),
		}
	}

	if err := validatePayload(req.Kind, req.BlockID, req.Payload); err != nil {
		return err
	}

	if err := validateAgainstDocument(req.Kind, req.BlockID, doc); err != nil {
		return err
	}

	return nil
}

func validatePayload(kind string, blockID *string, payload json.RawMessage) *ValidationError {
	if payload == nil {
		return &ValidationError{
			Code:    "INVALID_PAYLOAD",
			Message: "payload is required",
		}
	}

	if !json.Valid(payload) {
		return &ValidationError{
			Code:    "INVALID_PAYLOAD",
			Message: "payload is not valid JSON",
		}
	}

	switch Kind(kind) {
	case KindTextDelta:
		return validateTextDeltaPayload(payload)
	case KindCreateBlock:
		return validateCreateBlockPayload(payload, blockID)
	case KindDeleteBlock:
		if blockID == nil || *blockID == "" {
			return &ValidationError{
				Code:    "INVALID_BLOCK_ID",
				Message: "block_id is required for delete_block",
			}
		}
		return nil
	case KindMoveBlock:
		return validateMoveBlockPayload(payload, blockID)
	case KindSetBlockType:
		return validateSetBlockTypePayload(payload)
	case KindSetBlockMetadata:
		return validateSetBlockMetadataPayload(payload, blockID)
	case KindCompleteTaskOccurrence:
		return validateCompleteTaskOccurrencePayload(payload, blockID)
	}
	return nil
}

func validateTextDeltaPayload(payload json.RawMessage) *ValidationError {
	_, err := parseDeltaFromPayload(payload)
	if err != nil {
		return &ValidationError{
			Code:    "INVALID_DELTA",
			Message: "invalid text delta payload",
			Err:     err,
		}
	}
	return nil
}

func validateCreateBlockPayload(payload json.RawMessage, blockID *string) *ValidationError {
	p, err := parseCreateBlockPayload(payload)
	if err != nil {
		return &ValidationError{
			Code:    "INVALID_PAYLOAD",
			Message: "invalid create_block payload",
			Err:     err,
		}
	}
	if p.ID == "" {
		return &ValidationError{
			Code:    "INVALID_BLOCK_ID",
			Message: "block id is required for create_block",
		}
	}
	if blockID != nil && *blockID != p.ID {
		return &ValidationError{
			Code:    "INVALID_BLOCK_ID",
			Message: "block_id must match id for create_block",
		}
	}
	if !ValidBlockTypes[BlockType(p.Type)] {
		return &ValidationError{
			Code:    "INVALID_BLOCK_TYPE",
			Message: fmt.Sprintf("invalid block type: %s", p.Type),
		}
	}
	if err := rejectLegacyTaskMetadata(p.Metadata); err != nil {
		return err
	}
	if p.Delta == nil {
		return &ValidationError{
			Code:    "INVALID_PAYLOAD",
			Message: "delta is required for create_block",
		}
	}
	return nil
}

func validateMoveBlockPayload(payload json.RawMessage, blockID *string) *ValidationError {
	var p struct {
		BlockID string `json:"blockId"`
		AfterID string `json:"afterBlockId"`
	}
	if err := json.Unmarshal(payload, &p); err != nil {
		return &ValidationError{
			Code:    "INVALID_PAYLOAD",
			Message: "invalid move_block payload",
			Err:     err,
		}
	}
	if p.BlockID == "" {
		return &ValidationError{
			Code:    "INVALID_BLOCK_ID",
			Message: "blockId is required in payload for move_block",
		}
	}
	if blockID == nil || *blockID == "" {
		return &ValidationError{
			Code:    "INVALID_BLOCK_ID",
			Message: "block_id is required for move_block",
		}
	}
	if p.BlockID != *blockID {
		return &ValidationError{
			Code:    "INVALID_BLOCK_ID",
			Message: "payload blockId must match block_id for move_block",
		}
	}
	return nil
}

func validateSetBlockTypePayload(payload json.RawMessage) *ValidationError {
	var p struct {
		Type string `json:"type"`
	}
	if err := json.Unmarshal(payload, &p); err != nil {
		return &ValidationError{
			Code:    "INVALID_PAYLOAD",
			Message: "invalid set_block_type payload",
			Err:     err,
		}
	}
	if !ValidBlockTypes[BlockType(p.Type)] {
		return &ValidationError{
			Code:    "INVALID_BLOCK_TYPE",
			Message: fmt.Sprintf("invalid block type: %s", p.Type),
		}
	}
	return nil
}

func validateSetBlockMetadataPayload(payload json.RawMessage, blockID *string) *ValidationError {
	if blockID == nil || *blockID == "" {
		return &ValidationError{
			Code:    "INVALID_BLOCK_ID",
			Message: "block_id is required for set_block_metadata",
		}
	}

	var envelope map[string]json.RawMessage
	if err := json.Unmarshal(payload, &envelope); err != nil {
		return &ValidationError{
			Code:    "INVALID_PAYLOAD",
			Message: "invalid set_block_metadata payload",
			Err:     err,
		}
	}
	rawMetadata, ok := envelope["metadata"]
	if !ok || string(rawMetadata) == "null" {
		return &ValidationError{
			Code:    "INVALID_PAYLOAD",
			Message: "metadata is required for set_block_metadata",
		}
	}
	var metadata map[string]any
	if err := json.Unmarshal(rawMetadata, &metadata); err != nil || metadata == nil {
		return &ValidationError{
			Code:    "INVALID_PAYLOAD",
			Message: "metadata must be an object",
			Err:     err,
		}
	}
	if err := rejectLegacyTaskMetadata(metadata); err != nil {
		return err
	}
	return nil
}

func rejectLegacyTaskMetadata(metadata map[string]any) *ValidationError {
	for _, key := range []string{"checked", "recurrence"} {
		if _, exists := metadata[key]; exists {
			return &ValidationError{
				Code:    "INVALID_PAYLOAD",
				Message: fmt.Sprintf("legacy %s metadata is not allowed; run the task document backfill", key),
			}
		}
	}
	return nil
}

func validateCompleteTaskOccurrencePayload(payload json.RawMessage, blockID *string) *ValidationError {
	if blockID == nil || *blockID == "" {
		return &ValidationError{
			Code:    "INVALID_BLOCK_ID",
			Message: "block_id is required for complete_task_occurrence",
		}
	}

	var p CompleteTaskOccurrencePayload
	if err := json.Unmarshal(payload, &p); err != nil {
		return &ValidationError{
			Code:    "INVALID_PAYLOAD",
			Message: "invalid complete_task_occurrence payload",
			Err:     err,
		}
	}
	if p.TaskID == "" || p.TaskID != *blockID {
		return &ValidationError{
			Code:    "INVALID_BLOCK_ID",
			Message: "taskId must match block_id for complete_task_occurrence",
		}
	}
	if strings.TrimSpace(p.ScheduledAt) == "" {
		return &ValidationError{
			Code:    "INVALID_PAYLOAD",
			Message: "scheduledAt is required for complete_task_occurrence",
		}
	}
	if !isCanonicalScheduledAt(p.ScheduledAt) {
		return &ValidationError{
			Code:    "INVALID_PAYLOAD",
			Message: "scheduledAt must be a canonical calendar timestamp without an offset",
		}
	}
	if p.CompletedAt != nil && strings.TrimSpace(*p.CompletedAt) == "" {
		return &ValidationError{
			Code:    "INVALID_PAYLOAD",
			Message: "completedAt must be null or non-empty",
		}
	}
	if p.CompletedAt != nil && !isCanonicalCompletedAt(*p.CompletedAt) {
		return &ValidationError{
			Code:    "INVALID_PAYLOAD",
			Message: "completedAt must be a UTC timestamp",
		}
	}
	return nil
}

var canonicalScheduledAtPattern = regexp.MustCompile(
	`^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}([0-9]{3})?$`,
)

func isCanonicalScheduledAt(value string) bool {
	if !canonicalScheduledAtPattern.MatchString(value) {
		return false
	}
	layout := "2006-01-02T15:04:05.000"
	if len(value) == len("2006-01-02T15:04:05.000000") {
		layout = "2006-01-02T15:04:05.000000"
	}
	_, err := time.Parse(layout, value)
	return err == nil
}

func isCanonicalCompletedAt(value string) bool {
	if !canonicalCompletedAtPattern.MatchString(value) {
		return false
	}
	_, err := time.Parse(time.RFC3339Nano, value)
	return err == nil
}

var canonicalCompletedAtPattern = regexp.MustCompile(
	`^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}([0-9]{3})?Z$`,
)

func validateAgainstDocument(kind string, blockID *string, doc Document) *ValidationError {
	switch Kind(kind) {
	case KindTextDelta:
		if blockID == nil || *blockID == "" {
			return &ValidationError{
				Code:    "INVALID_BLOCK_ID",
				Message: "block_id is required for text_delta",
			}
		}
	case KindDeleteBlock:
		if blockID == nil || *blockID == "" {
			return &ValidationError{
				Code:    "INVALID_BLOCK_ID",
				Message: "block_id is required for delete_block",
			}
		}
	case KindMoveBlock:
		if blockID == nil || *blockID == "" {
			return &ValidationError{
				Code:    "INVALID_BLOCK_ID",
				Message: "block_id is required for move_block",
			}
		}
	case KindSetBlockType:
		if blockID == nil || *blockID == "" {
			return &ValidationError{
				Code:    "INVALID_BLOCK_ID",
				Message: "block_id is required for set_block_type",
			}
		}
	case KindSetBlockMetadata:
		if blockID == nil || *blockID == "" {
			return &ValidationError{
				Code:    "INVALID_BLOCK_ID",
				Message: "block_id is required for set_block_metadata",
			}
		}
	case KindCompleteTaskOccurrence:
		if blockID == nil || *blockID == "" {
			return &ValidationError{
				Code:    "INVALID_BLOCK_ID",
				Message: "block_id is required for complete_task_occurrence",
			}
		}
		for _, block := range doc.Blocks {
			if block.ID != *blockID {
				continue
			}
			if block.Type != string(BlockTask) {
				return &ValidationError{
					Code:    "INVALID_BLOCK_TYPE",
					Message: "complete_task_occurrence requires a task block",
				}
			}
			return nil
		}
		return &ValidationError{
			Code:    "INVALID_BLOCK_ID",
			Message: "task block not found",
		}
	}
	return nil
}
