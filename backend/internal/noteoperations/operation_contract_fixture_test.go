package noteoperations

import (
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/fmpwizard/go-quilljs-delta/delta"
	"github.com/stretchr/testify/require"
)

type operationContractFixture struct {
	Operations []struct {
		Kind    string          `json:"kind"`
		BlockID *string         `json:"blockId"`
		Payload json.RawMessage `json:"payload"`
	} `json:"operations"`
}

func TestOperationContractFixture_isAcceptedByGoValidator(t *testing.T) {
	_, currentFile, _, ok := runtime.Caller(0)
	require.True(t, ok)
	fixturePath := filepath.Join(filepath.Dir(currentFile), "../../../test/fixtures/operation_contract.json")
	fixtureData, err := os.ReadFile(fixturePath)
	require.NoError(t, err)

	var fixture operationContractFixture
	require.NoError(t, json.Unmarshal(fixtureData, &fixture))
	require.Len(t, fixture.Operations, len(ValidKinds))

	doc := Document{
		SchemaVersion: 1,
		Blocks: []Block{
			{ID: "b1", Type: string(BlockParagraph), Delta: []delta.Op{{Insert: []rune("hello")}}, Metadata: map[string]any{}},
			{ID: "b2", Type: string(BlockParagraph), Delta: []delta.Op{{Insert: []rune("world")}}, Metadata: map[string]any{}},
			{ID: "task-1", Type: string(BlockTask), Delta: []delta.Op{{Insert: []rune("task")}}, Metadata: map[string]any{}},
		},
	}

	for _, operation := range fixture.Operations {
		op := OperationRequest{
			OperationID:  "550e8400-e29b-41d4-a716-446655440000",
			BaseRevision: 0,
			Kind:         operation.Kind,
			BlockID:      operation.BlockID,
			Payload:      operation.Payload,
		}
		if validationErr := ValidateOperation(op, doc, 0, 0); validationErr != nil {
			t.Fatalf("%s: %s", operation.Kind, validationErr.Error())
		}
	}
}
