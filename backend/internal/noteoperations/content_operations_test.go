package noteoperations

import (
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestBuildReplaceContentOperationsUsesEmptyDeltaForEmptyContent(t *testing.T) {
	operations, err := BuildReplaceContentOperations(NewEmptyDocument(), "", 0)
	require.NoError(t, err)
	require.NotEmpty(t, operations)

	var payload CreateBlockPayload
	require.NoError(t, json.Unmarshal(operations[len(operations)-1].Payload, &payload))
	assert.Empty(t, payload.Delta)
	assert.JSONEq(
		t,
		`{"id":"init","type":"paragraph","delta":[],"metadata":{},"afterBlockId":""}`,
		string(operations[len(operations)-1].Payload),
	)
}
