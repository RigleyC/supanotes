package noteoperations

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/stretchr/testify/require"
)

func TestAppendRichLinkAppendsToLatestDocumentAndDeduplicatesRetry(t *testing.T) {
	noteID := mustParseUUID("550e8400-e29b-41d4-a716-446655440001")
	userID := mustParseUUID("550e8400-e29b-41d4-a716-446655440002")
	operationID := "550e8400-e29b-41d4-a716-446655440003"
	document, err := json.Marshal(Document{
		SchemaVersion: 1,
		Blocks: []Block{
			{ID: "paragraph-1", Type: string(BlockParagraph), Metadata: map[string]any{}},
		},
	})
	require.NoError(t, err)

	storedDocument := document
	storedRevision := int64(4)
	operations := map[uuid.UUID]Operation{}
	repo := &mockRepository{
		lockNoteFn: func(context.Context, pgtype.UUID) (LockNoteResult, error) {
			return LockNoteResult{ID: noteID, Revision: storedRevision, Document: storedDocument}, nil
		},
		getNoteOperationByOpIDFn: func(_ context.Context, _ pgtype.UUID, id pgtype.UUID) (Operation, error) {
			if operation, ok := operations[uuid.UUID(id.Bytes)]; ok {
				return operation, nil
			}
			return Operation{}, pgx.ErrNoRows
		},
		insertOperationFn: func(_ context.Context, params InsertOperationParams) (Operation, error) {
			operation := Operation{
				NoteID: params.NoteID, Revision: params.Revision,
				OperationID: params.OperationID, ActorID: params.ActorID,
				BaseRevision: params.BaseRevision, Kind: params.Kind,
				BlockID: params.BlockID, Payload: params.Payload,
			}
			operations[uuid.UUID(params.OperationID.Bytes)] = operation
			return operation, nil
		},
		updateNoteDocumentFn: func(_ context.Context, params UpdateNoteDocumentParams) error {
			storedDocument = params.Document
			storedRevision = params.Revision
			return nil
		},
	}

	svc := NewServiceWithTransactionRunner(repo, immediateTransactionRunner{})
	metadata := map[string]any{
		"url": "https://example.com/post", "domain": "example.com",
		"title": "Example",
	}

	first, err := svc.AppendRichLink(context.Background(), noteID, userID, operationID, metadata)
	require.NoError(t, err)
	require.Equal(t, int64(5), first.Revision)

	decoded, err := UnmarshalDocument(first.Document)
	require.NoError(t, err)
	require.Len(t, decoded.Blocks, 2)
	require.Equal(t, string(BlockRichLink), decoded.Blocks[1].Type)
	require.Equal(t, metadata, decoded.Blocks[1].Metadata)

	second, err := svc.AppendRichLink(context.Background(), noteID, userID, operationID, metadata)
	require.NoError(t, err)
	require.True(t, second.AlreadyAccepted)
	require.Equal(t, int64(5), second.Revision)
}
