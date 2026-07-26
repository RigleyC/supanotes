package noteoperations

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestSyncOperationsPersistsCreateBlocksAndReopensDocument(t *testing.T) {
	_, currentFile, _, ok := runtime.Caller(0)
	require.True(t, ok)
	fixturePath := filepath.Join(filepath.Dir(currentFile), "../../../test/fixtures/ot_create_blocks_contract.json")
	fixtureData, err := os.ReadFile(fixturePath)
	require.NoError(t, err)

	var fixture struct {
		Blocks []CreateBlockPayload `json:"blocks"`
	}
	require.NoError(t, json.Unmarshal(fixtureData, &fixture))

	noteID := mustParseUUID("550e8400-e29b-41d4-a716-446655440001")
	userID := mustParseUUID("550e8400-e29b-41d4-a716-446655440002")
	emptyDocument, err := json.Marshal(NewEmptyDocument())
	require.NoError(t, err)

	storedDocument := emptyDocument
	storedRevision := int64(0)
	storedOperations := map[uuid.UUID]Operation{}
	repo := &mockRepository{
		lockNoteFn: func(context.Context, pgtype.UUID) (LockNoteResult, error) {
			return LockNoteResult{
				ID:       noteID,
				Revision: storedRevision,
				Document: storedDocument,
			}, nil
		},
		getNoteOperationByOpIDFn: func(_ context.Context, _ pgtype.UUID, operationID pgtype.UUID) (Operation, error) {
			operation, exists := storedOperations[uuid.UUID(operationID.Bytes)]
			if !exists {
				return Operation{}, pgx.ErrNoRows
			}
			return operation, nil
		},
		updateNoteDocumentFn: func(_ context.Context, update UpdateNoteDocumentParams) error {
			storedDocument = update.Document
			storedRevision = update.Revision
			return nil
		},
		getNoteDocumentFn: func(context.Context, pgtype.UUID) (GetNoteDocumentResult, error) {
			return GetNoteDocumentResult{
				Revision: storedRevision,
				Document: storedDocument,
			}, nil
		},
		getOperationsRangeFn: func(_ context.Context, _ pgtype.UUID, afterRevision int64, upToRevision int64) ([]Operation, error) {
			operations := make([]Operation, 0, len(storedOperations))
			for _, operation := range storedOperations {
				if operation.Revision > afterRevision && operation.Revision <= upToRevision {
					operations = append(operations, operation)
				}
			}
			return operations, nil
		},
	}
	repo.insertOperationFn = func(_ context.Context, insert InsertOperationParams) (Operation, error) {
		operation := Operation{
			NoteID:       insert.NoteID,
			Revision:     insert.Revision,
			OperationID:  insert.OperationID,
			ActorID:      insert.ActorID,
			BaseRevision: insert.BaseRevision,
			Kind:         insert.Kind,
			BlockID:      insert.BlockID,
			Payload:      insert.Payload,
		}
		storedOperations[uuid.UUID(insert.OperationID.Bytes)] = operation
		return operation, nil
	}

	operations := make([]OperationRequest, 0, len(fixture.Blocks))
	for index, block := range fixture.Blocks {
		payload, err := json.Marshal(block)
		require.NoError(t, err)
		operations = append(operations, OperationRequest{
			OperationID:  uuid.NewString(),
			BaseRevision: int64(index),
			Kind:         string(KindCreateBlock),
			BlockID:      &block.ID,
			Payload:      payload,
		})
	}

	response, err := syncOperationsInRepository(
		context.Background(),
		repo,
		noteID,
		userID,
		SyncRequest{KnownRevision: 0, Operations: operations, ClientID: "integration-test"},
	)
	require.NoError(t, err)
	assert.Len(t, response.Accepted, len(fixture.Blocks))
	assert.Equal(t, int64(len(fixture.Blocks)), response.FinalRevision)

	reopened, err := NewService(repo, nil).GetDocument(context.Background(), noteID, userID)
	require.NoError(t, err)
	assert.Equal(t, response.FinalRevision, reopened.Revision)

	document, err := UnmarshalDocument(reopened.Document)
	require.NoError(t, err)
	for _, expected := range fixture.Blocks {
		var actual *Block
		for index := range document.Blocks {
			if document.Blocks[index].ID == expected.ID {
				actual = &document.Blocks[index]
				break
			}
		}
		require.NotNil(t, actual, expected.ID)
		assert.Equal(t, expected.Type, actual.Type)
		assert.Equal(t, deltaText(expected.Delta), deltaText(actual.Delta))
	}

	_, err = syncOperationsInRepository(
		context.Background(),
		repo,
		noteID,
		userID,
		SyncRequest{KnownRevision: storedRevision, Operations: operations, ClientID: "integration-test"},
	)
	require.NoError(t, err)
	assert.Equal(t, int64(len(fixture.Blocks)), storedRevision)
}

func TestSyncOperationsSharedNoteEditViewAndPollingContract(t *testing.T) {
	noteID := mustParseUUID("550e8400-e29b-41d4-a716-446655440101")
	userA := mustParseUUID("550e8400-e29b-41d4-a716-446655440102")
	userB := mustParseUUID("550e8400-e29b-41d4-a716-446655440103")
	viewer := mustParseUUID("550e8400-e29b-41d4-a716-446655440104")

	storedDocument := []byte(`{"schemaVersion":1,"blocks":[{"id":"b1","type":"paragraph","delta":[],"metadata":{}}]}`)
	storedRevision := int64(0)
	storedOperations := map[uuid.UUID]Operation{}
	operationLog := []Operation{}

	repo := &mockRepository{
		checkNotePermissionFn: func(_ context.Context, _ pgtype.UUID, userID pgtype.UUID) (string, error) {
			switch userID {
			case userA:
				return "edit", nil
			case userB:
				return "edit", nil
			case viewer:
				return "view", nil
			default:
				return "none", nil
			}
		},
		lockNoteFn: func(context.Context, pgtype.UUID) (LockNoteResult, error) {
			return LockNoteResult{
				ID:       noteID,
				Revision: storedRevision,
				Document: storedDocument,
			}, nil
		},
		getNoteOperationByOpIDFn: func(_ context.Context, _ pgtype.UUID, operationID pgtype.UUID) (Operation, error) {
			operation, exists := storedOperations[uuid.UUID(operationID.Bytes)]
			if !exists {
				return Operation{}, pgx.ErrNoRows
			}
			return operation, nil
		},
		getOperationsSinceFn: func(_ context.Context, _ pgtype.UUID, afterRevision int64) ([]Operation, error) {
			operations := []Operation{}
			for _, operation := range operationLog {
				if operation.Revision > afterRevision {
					operations = append(operations, operation)
				}
			}
			return operations, nil
		},
		getOperationsRangeFn: func(_ context.Context, _ pgtype.UUID, afterRevision int64, upToRevision int64) ([]Operation, error) {
			operations := []Operation{}
			for _, operation := range operationLog {
				if operation.Revision > afterRevision && operation.Revision <= upToRevision {
					operations = append(operations, operation)
				}
			}
			return operations, nil
		},
		updateNoteDocumentFn: func(_ context.Context, update UpdateNoteDocumentParams) error {
			storedDocument = update.Document
			storedRevision = update.Revision
			return nil
		},
		getNoteDocumentFn: func(context.Context, pgtype.UUID) (GetNoteDocumentResult, error) {
			return GetNoteDocumentResult{
				Revision: storedRevision,
				Document: storedDocument,
			}, nil
		},
	}
	repo.insertOperationFn = func(_ context.Context, insert InsertOperationParams) (Operation, error) {
		operation := Operation{
			NoteID:       insert.NoteID,
			Revision:     insert.Revision,
			OperationID:  insert.OperationID,
			ActorID:      insert.ActorID,
			BaseRevision: insert.BaseRevision,
			Kind:         insert.Kind,
			BlockID:      insert.BlockID,
			Payload:      insert.Payload,
		}
		storedOperations[uuid.UUID(insert.OperationID.Bytes)] = operation
		operationLog = append(operationLog, operation)
		return operation, nil
	}

	blockID := "b1"
	responseA, err := syncOperationsInRepository(
		context.Background(),
		repo,
		noteID,
		userA,
		SyncRequest{
			KnownRevision: 0,
			ClientID:      "client-a",
			Operations: []OperationRequest{{
				OperationID:  "550e8400-e29b-41d4-a716-446655441001",
				BaseRevision: 0,
				Kind:         string(KindTextDelta),
				BlockID:      &blockID,
				Payload:      json.RawMessage(`{"ops":[{"insert":"A"}]}`),
			}},
		},
	)
	require.NoError(t, err)
	assert.Equal(t, int64(1), responseA.FinalRevision)

	responseB, err := syncOperationsInRepository(
		context.Background(),
		repo,
		noteID,
		userB,
		SyncRequest{
			KnownRevision: 0,
			ClientID:      "client-b",
			Operations: []OperationRequest{{
				OperationID:  "550e8400-e29b-41d4-a716-446655441002",
				BaseRevision: 0,
				Kind:         string(KindTextDelta),
				BlockID:      &blockID,
				Payload:      json.RawMessage(`{"ops":[{"insert":"B"}]}`),
			}},
		},
	)
	require.NoError(t, err)
	assert.Equal(t, int64(2), responseB.FinalRevision)
	assert.Len(t, responseB.RemoteOperations, 1)

	_, err = syncOperationsInRepository(
		context.Background(),
		repo,
		noteID,
		viewer,
		SyncRequest{
			KnownRevision: 2,
			ClientID:      "viewer-client",
			Operations: []OperationRequest{{
				OperationID:  "550e8400-e29b-41d4-a716-446655441003",
				BaseRevision: 2,
				Kind:         string(KindTextDelta),
				BlockID:      &blockID,
				Payload:      json.RawMessage(`{"ops":[{"insert":"VIEW"}]}`),
			}},
		},
	)
	assert.ErrorIs(t, err, ErrNoPermission)

	polled, err := NewService(repo, nil).GetOperationsSince(context.Background(), noteID, viewer, 1)
	require.NoError(t, err)
	assert.Len(t, polled.Operations, 1)
	assert.Equal(t, int64(2), storedRevision)
	assert.Contains(t, string(storedDocument), "A")
	assert.Contains(t, string(storedDocument), "B")
}
