package noteoperations

import (
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestValidKindConstants(t *testing.T) {
	assert.True(t, ValidKinds[KindTextDelta])
	assert.True(t, ValidKinds[KindCreateBlock])
	assert.True(t, ValidKinds[KindDeleteBlock])
	assert.True(t, ValidKinds[KindMoveBlock])
	assert.True(t, ValidKinds[KindSetBlockType])
	assert.False(t, ValidKinds["invalid"])
}

func TestValidBlockTypeConstants(t *testing.T) {
	assert.True(t, ValidBlockTypes[BlockParagraph])
	assert.True(t, ValidBlockTypes[BlockHeader1])
	assert.True(t, ValidBlockTypes[BlockHeader2])
	assert.True(t, ValidBlockTypes[BlockHeader3])
	assert.True(t, ValidBlockTypes[BlockQuote])
	assert.True(t, ValidBlockTypes[BlockBulletList])
	assert.True(t, ValidBlockTypes[BlockOrderedList])
	assert.True(t, ValidBlockTypes[BlockDivider])
	assert.False(t, ValidBlockTypes["invalid"])
}

func TestSyncRequestMarshalUnmarshal(t *testing.T) {
	req := SyncRequest{
		KnownRevision: 5,
		Operations: []OperationRequest{
			{
				OperationID:  "550e8400-e29b-41d4-a716-446655440000",
				BaseRevision: 5,
				Kind:         "text_delta",
				BlockID:      strPtr("block1"),
				Payload:      json.RawMessage(`{"ops":[{"retain":2},{"insert":"a"}]}`),
			},
		},
		ClientID: "test-client",
	}

	data, err := json.Marshal(req)
	require.NoError(t, err)

	var decoded SyncRequest
	err = json.Unmarshal(data, &decoded)
	require.NoError(t, err)

	assert.Equal(t, req.KnownRevision, decoded.KnownRevision)
	assert.Equal(t, req.ClientID, decoded.ClientID)
	assert.Len(t, decoded.Operations, 1)
	assert.Equal(t, req.Operations[0].OperationID, decoded.Operations[0].OperationID)
	assert.Equal(t, req.Operations[0].Kind, decoded.Operations[0].Kind)
}

func TestSyncResponseMarshalUnmarshal(t *testing.T) {
	resp := SyncResponse{
		Accepted: []AcceptedOperation{
			{OperationID: "550e8400-e29b-41d4-a716-446655440000", Revision: 6, Kind: "text_delta", BlockID: "block1"},
		},
		FinalRevision: 6,
		RemoteOperations: []Operation{
			{Revision: 6, Kind: "text_delta"},
		},
	}

	data, err := json.Marshal(resp)
	require.NoError(t, err)

	var decoded SyncResponse
	err = json.Unmarshal(data, &decoded)
	require.NoError(t, err)

	assert.Equal(t, resp.FinalRevision, decoded.FinalRevision)
	assert.Len(t, decoded.Accepted, 1)
	assert.Len(t, decoded.RemoteOperations, 1)
}

func TestDocumentResponseMarshal(t *testing.T) {
	resp := DocumentResponse{
		NoteID:   "note1",
		Revision: 10,
		Document: json.RawMessage(`{"schemaVersion":1,"blocks":[]}`),
	}

	data, err := json.Marshal(resp)
	require.NoError(t, err)

	var decoded DocumentResponse
	err = json.Unmarshal(data, &decoded)
	require.NoError(t, err)

	assert.Equal(t, resp.NoteID, decoded.NoteID)
	assert.Equal(t, resp.Revision, decoded.Revision)
}

func strPtr(s string) *string { return &s }
