package noteoperations

import (
	"encoding/json"
	"errors"
	"fmt"
)

var (
	ErrInvalidDelta      = errors.New("invalid delta")
	ErrBlockDeleted        = errors.New("block deleted")
	ErrInvalidAnchor       = errors.New("invalid anchor")
	ErrNoteDeleted         = errors.New("note deleted")
	ErrForbidden           = errors.New("forbidden")
	ErrSchemaVersionUnsupported = errors.New("schema version unsupported")
	ErrInvalidKind         = errors.New("invalid operation kind")
	ErrInvalidBlockID      = errors.New("invalid block id")
	ErrInvalidBlockType    = errors.New("invalid block type")
	ErrInvalidPayload      = errors.New("invalid payload")
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

func ValidateOperation(req OperationRequest, doc Document, baseRevision int64) *ValidationError {
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
		return validateMoveBlockPayload(payload)
	case KindSetBlockType:
		return validateSetBlockTypePayload(payload)
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
	var p struct {
		ID       string          `json:"id"`
		Type     string          `json:"type"`
		Delta    json.RawMessage `json:"delta"`
		AfterID  string          `json:"afterBlockId"`
	}
	if err := json.Unmarshal(payload, &p); err != nil {
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
	if !ValidBlockTypes[BlockType(p.Type)] {
		return &ValidationError{
			Code:    "INVALID_BLOCK_TYPE",
			Message: fmt.Sprintf("invalid block type: %s", p.Type),
		}
	}
	return nil
}

func validateMoveBlockPayload(payload json.RawMessage) *ValidationError {
	var p struct {
		BlockID     string `json:"blockId"`
		AfterID     string `json:"afterBlockId"`
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

func validateAgainstDocument(kind string, blockID *string, doc Document) *ValidationError {
	switch Kind(kind) {
	case KindTextDelta:
		if blockID == nil || *blockID == "" {
			return &ValidationError{
				Code:    "INVALID_BLOCK_ID",
				Message: "block_id is required for text_delta",
			}
		}
		for _, b := range doc.Blocks {
			if b.ID == *blockID {
				return nil
			}
		}
		return &ValidationError{
			Code:    "BLOCK_DELETED",
			Message: fmt.Sprintf("block %s not found", *blockID),
		}
	case KindDeleteBlock:
		for _, b := range doc.Blocks {
			if b.ID == *blockID {
				return nil
			}
		}
		return &ValidationError{
			Code:    "BLOCK_DELETED",
			Message: fmt.Sprintf("block %s not found", *blockID),
		}
	case KindMoveBlock:
		for _, b := range doc.Blocks {
			if b.ID == *blockID {
				return nil
			}
		}
		return &ValidationError{
			Code:    "BLOCK_DELETED",
			Message: fmt.Sprintf("block %s not found", *blockID),
		}
	case KindSetBlockType:
		if blockID == nil || *blockID == "" {
			return &ValidationError{
				Code:    "INVALID_BLOCK_ID",
				Message: "block_id is required for set_block_type",
			}
		}
		for _, b := range doc.Blocks {
			if b.ID == *blockID {
				return nil
			}
		}
		return &ValidationError{
			Code:    "BLOCK_DELETED",
			Message: fmt.Sprintf("block %s not found", *blockID),
		}
	}
	return nil
}
