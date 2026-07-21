package noteoperations

import (
	"encoding/json"
	"testing"

	"github.com/fmpwizard/go-quilljs-delta/delta"
	"github.com/stretchr/testify/assert"
)

func TestValidateOperationValidTextDelta(t *testing.T) {
	doc := Document{
		SchemaVersion: 1,
		Blocks: []Block{
			{ID: "b1", Type: string(BlockParagraph), Delta: []delta.Op{{Insert: []rune("hi")}}, Metadata: map[string]any{}},
		},
	}
	req := OperationRequest{
		OperationID:  "550e8400-e29b-41d4-a716-446655440000",
		BaseRevision: 0,
		Kind:         "text_delta",
		BlockID:      strPtr("b1"),
		Payload:      json.RawMessage(`{"ops":[{"retain":2},{"insert":"a"}]}`),
	}

	err := ValidateOperation(req, doc, 0)
	assert.Nil(t, err)
}

func TestValidateOperationInvalidKind(t *testing.T) {
	doc := NewEmptyDocument()
	req := OperationRequest{
		OperationID:  "550e8400-e29b-41d4-a716-446655440000",
		BaseRevision: 0,
		Kind:         "invalid",
		Payload:      json.RawMessage(`{}`),
	}

	err := ValidateOperation(req, doc, 0)
	assert.NotNil(t, err)
	assert.Equal(t, "INVALID_KIND", err.Code)
}

func TestValidateOperationTextDeltaBlockDeleted(t *testing.T) {
	doc := NewEmptyDocument()
	req := OperationRequest{
		OperationID:  "550e8400-e29b-41d4-a716-446655440000",
		BaseRevision: 0,
		Kind:         "text_delta",
		BlockID:      strPtr("nonexistent"),
		Payload:      json.RawMessage(`{"ops":[{"insert":"a"}]}`),
	}

	err := ValidateOperation(req, doc, 0)
	assert.NotNil(t, err)
	assert.Equal(t, "BLOCK_DELETED", err.Code)
}

func TestValidateOperationDeleteBlockValid(t *testing.T) {
	doc := Document{
		SchemaVersion: 1,
		Blocks: []Block{
			{ID: "b1", Type: string(BlockParagraph), Metadata: map[string]any{}},
		},
	}
	req := OperationRequest{
		OperationID:  "550e8400-e29b-41d4-a716-446655440000",
		BaseRevision: 0,
		Kind:         "delete_block",
		BlockID:      strPtr("b1"),
		Payload:      json.RawMessage(`{}`),
	}

	err := ValidateOperation(req, doc, 0)
	assert.Nil(t, err)
}

func TestValidateOperationDeleteBlockAlreadyDeleted(t *testing.T) {
	doc := NewEmptyDocument()
	req := OperationRequest{
		OperationID:  "550e8400-e29b-41d4-a716-446655440000",
		BaseRevision: 0,
		Kind:         "delete_block",
		BlockID:      strPtr("nonexistent"),
		Payload:      json.RawMessage(`{}`),
	}

	err := ValidateOperation(req, doc, 0)
	assert.NotNil(t, err)
	assert.Equal(t, "BLOCK_DELETED", err.Code)
}

func TestValidateOperationCreateBlock(t *testing.T) {
	doc := NewEmptyDocument()
	req := OperationRequest{
		OperationID:  "550e8400-e29b-41d4-a716-446655440000",
		BaseRevision: 0,
		Kind:         "create_block",
		Payload:      json.RawMessage(`{"id":"new1","type":"paragraph","delta":[{"insert":""}]}`),
	}

	err := ValidateOperation(req, doc, 0)
	assert.Nil(t, err)
}

func TestValidateOperationCreateBlockInvalidType(t *testing.T) {
	doc := NewEmptyDocument()
	req := OperationRequest{
		OperationID:  "550e8400-e29b-41d4-a716-446655440000",
		BaseRevision: 0,
		Kind:         "create_block",
		Payload:      json.RawMessage(`{"id":"new1","type":"invalid_type","delta":[{"insert":""}]}`),
	}

	err := ValidateOperation(req, doc, 0)
	assert.NotNil(t, err)
	assert.Equal(t, "INVALID_BLOCK_TYPE", err.Code)
}

func TestValidateOperationSetBlockType(t *testing.T) {
	doc := Document{
		SchemaVersion: 1,
		Blocks: []Block{
			{ID: "b1", Type: string(BlockParagraph), Metadata: map[string]any{}},
		},
	}
	req := OperationRequest{
		OperationID:  "550e8400-e29b-41d4-a716-446655440000",
		BaseRevision: 0,
		Kind:         "set_block_type",
		BlockID:      strPtr("b1"),
		Payload:      json.RawMessage(`{"type":"header1"}`),
	}

	err := ValidateOperation(req, doc, 0)
	assert.Nil(t, err)
}

func TestValidateOperationInvalidPayloadJSON(t *testing.T) {
	doc := NewEmptyDocument()
	req := OperationRequest{
		OperationID:  "550e8400-e29b-41d4-a716-446655440000",
		BaseRevision: 0,
		Kind:         "text_delta",
		BlockID:      strPtr("init"),
		Payload:      json.RawMessage(`invalid json`),
	}

	err := ValidateOperation(req, doc, 0)
	assert.NotNil(t, err)
	assert.Equal(t, "INVALID_PAYLOAD", err.Code)
}

func TestValidateOperationMoveBlock(t *testing.T) {
	doc := Document{
		SchemaVersion: 1,
		Blocks: []Block{
			{ID: "b1", Type: string(BlockParagraph), Metadata: map[string]any{}},
			{ID: "b2", Type: string(BlockParagraph), Metadata: map[string]any{}},
		},
	}
	req := OperationRequest{
		OperationID:  "550e8400-e29b-41d4-a716-446655440000",
		BaseRevision: 0,
		Kind:         "move_block",
		BlockID:      strPtr("b1"),
		Payload:      json.RawMessage(`{"blockId":"b1","afterBlockId":"b2"}`),
	}

	err := ValidateOperation(req, doc, 0)
	assert.Nil(t, err)
}
