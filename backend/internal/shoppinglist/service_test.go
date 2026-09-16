package shoppinglist

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/noteoperations"
)

type noteReaderStub struct {
	rows []sqlcgen.GetNotesRow
}

func (s noteReaderStub) GetNotes(context.Context, pgtype.UUID, *bool, int32, *time.Time, *pgtype.UUID) ([]sqlcgen.GetNotesRow, error) {
	return s.rows, nil
}

type documentServiceStub struct {
	document noteoperations.Document
	revision int64
	requests []noteoperations.SyncRequest
}

func (s *documentServiceStub) SyncOperations(_ context.Context, _ pgtype.UUID, _ pgtype.UUID, request noteoperations.SyncRequest) (noteoperations.SyncResponse, error) {
	s.requests = append(s.requests, request)
	for _, operation := range request.Operations {
		if err := s.document.ApplyOperation(noteoperations.Kind(operation.Kind), valueOrEmpty(operation.BlockID), operation.Payload); err != nil {
			return noteoperations.SyncResponse{}, err
		}
	}
	s.revision++
	return noteoperations.SyncResponse{}, nil
}

func (s *documentServiceStub) GetDocument(context.Context, pgtype.UUID, pgtype.UUID) (noteoperations.DocumentResponse, error) {
	document, err := json.Marshal(s.document)
	return noteoperations.DocumentResponse{Revision: s.revision, Document: document}, err
}

func (s *documentServiceStub) GetOperationsSince(context.Context, pgtype.UUID, pgtype.UUID, int64) (noteoperations.OperationsListResponse, error) {
	return noteoperations.OperationsListResponse{}, nil
}

func TestAddItemUsesStableOperationAndBlockIDs(t *testing.T) {
	noteID := uuid.New()
	operationID := uuid.MustParse("550e8400-e29b-41d4-a716-446655440000")
	reader := noteReaderStub{rows: []sqlcgen.GetNotesRow{{ID: pgtype.UUID{Bytes: noteID, Valid: true}, Title: ShoppingListTitle}}}
	commands := &documentServiceStub{document: noteoperations.NewEmptyDocument()}
	service := NewService(reader, commands)

	userID := pgtype.UUID{Bytes: uuid.New(), Valid: true}
	require.NoError(t, service.AddItem(context.Background(), userID, "café", operationID))
	require.NoError(t, service.AddItem(context.Background(), userID, "café", operationID))

	require.Len(t, commands.requests, 1)
	first := commands.requests[0].Operations[0]
	assert.Equal(t, operationID.String(), first.OperationID)

	var payload noteoperations.CreateBlockPayload
	require.NoError(t, json.Unmarshal(first.Payload, &payload))
	assert.Equal(t, *first.BlockID, payload.ID)
	assert.Len(t, commands.document.Blocks, 2)
}

func valueOrEmpty(value *string) string {
	if value == nil {
		return ""
	}
	return *value
}
