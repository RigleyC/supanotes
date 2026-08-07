package noteoperations

import (
	"encoding/json"
	"testing"

	"github.com/fmpwizard/go-quilljs-delta/delta"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestValidateOperationSetBlockMetadata_requiresObjectPayload(t *testing.T) {
	doc := Document{Blocks: []Block{{ID: "b1", Type: string(BlockParagraph)}}}
	req := OperationRequest{
		OperationID: "550e8400-e29b-41d4-a716-446655440000",
		Kind:        string(KindSetBlockMetadata),
		BlockID:     strPtr("b1"),
		Payload:     json.RawMessage(`{"metadata":[]}`),
	}

	err := ValidateOperation(req, doc, 0, 0)
	require.NotNil(t, err)
	assert.Equal(t, "INVALID_PAYLOAD", err.Code)
}

func TestValidateOperationCreateBlock_requiresDeltaArray(t *testing.T) {
	doc := Document{Blocks: []Block{{ID: "b1", Type: string(BlockParagraph)}}}
	for name, delta := range map[string]string{
		"missing": "null",
		"object":  `{"insert":"text"}`,
	} {
		t.Run(name, func(t *testing.T) {
			req := OperationRequest{
				OperationID: "550e8400-e29b-41d4-a716-446655440000",
				Kind:        string(KindCreateBlock),
				BlockID:     strPtr("b2"),
				Payload: json.RawMessage(
					`{"id":"b2","type":"paragraph","delta":` + delta + `}`,
				),
			}

			err := ValidateOperation(req, doc, 0, 0)
			require.NotNil(t, err)
			assert.Equal(t, "INVALID_PAYLOAD", err.Code)
		})
	}
}

func TestValidateOperationCompleteTaskOccurrence_requiresMatchingTaskAndTimestamp(t *testing.T) {
	doc := Document{Blocks: []Block{{ID: "task-1", Type: string(BlockTask)}}}

	for name, payload := range map[string]string{
		"missing scheduledAt": `{"taskId":"task-1"}`,
		"mismatched task":     `{"taskId":"task-2","scheduledAt":"2026-07-27T09:00:00Z"}`,
		"empty completedAt":   `{"taskId":"task-1","scheduledAt":"2026-07-27T09:00:00Z","completedAt":""}`,
	} {
		t.Run(name, func(t *testing.T) {
			req := OperationRequest{
				OperationID: "550e8400-e29b-41d4-a716-446655440000",
				Kind:        string(KindCompleteTaskOccurrence),
				BlockID:     strPtr("task-1"),
				Payload:     json.RawMessage(payload),
			}

			err := ValidateOperation(req, doc, 0, 0)
			require.NotNil(t, err)
		})
	}
}

func TestValidateOperationCompleteTaskOccurrence_requiresTaskBlock(t *testing.T) {
	doc := Document{
		Blocks: []Block{
			{ID: "b1", Type: string(BlockParagraph), Delta: []delta.Op{{Insert: []rune("text")}}},
		},
	}
	req := OperationRequest{
		OperationID: "550e8400-e29b-41d4-a716-446655440000",
		Kind:        string(KindCompleteTaskOccurrence),
		BlockID:     strPtr("b1"),
		Payload:     json.RawMessage(`{"taskId":"b1","scheduledAt":"2026-07-27T09:00:00Z","completedAt":null}`),
	}

	err := ValidateOperation(req, doc, 0, 0)
	require.NotNil(t, err)
	assert.Equal(t, "INVALID_BLOCK_TYPE", err.Code)
}
