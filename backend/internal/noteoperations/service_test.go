package noteoperations

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/stretchr/testify/assert"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

type mockRepository struct {
	ensureNoteFn             func(ctx context.Context, noteID pgtype.UUID, userID pgtype.UUID) error
	lockNoteFn               func(ctx context.Context, noteID pgtype.UUID) (LockNoteResult, error)
	getOperationsSinceFn     func(ctx context.Context, noteID pgtype.UUID, afterRevision int64) ([]Operation, error)
	getOperationsRangeFn     func(ctx context.Context, noteID pgtype.UUID, afterRevision int64, upToRevision int64) ([]Operation, error)
	updateNoteDocumentFn     func(ctx context.Context, arg UpdateNoteDocumentParams) error
	getNoteOperationByOpIDFn func(ctx context.Context, noteID pgtype.UUID, operationID pgtype.UUID) (Operation, error)
	checkNotePermissionFn    func(ctx context.Context, noteID pgtype.UUID, userID pgtype.UUID) (string, error)
	getNoteDocumentFn        func(ctx context.Context, noteID pgtype.UUID) (GetNoteDocumentResult, error)
}

func (m *mockRepository) EnsureNote(ctx context.Context, noteID pgtype.UUID, userID pgtype.UUID) error {
	if m.ensureNoteFn != nil {
		return m.ensureNoteFn(ctx, noteID, userID)
	}
	return nil
}

func (m *mockRepository) LockNote(ctx context.Context, noteID pgtype.UUID) (LockNoteResult, error) {
	if m.lockNoteFn != nil {
		return m.lockNoteFn(ctx, noteID)
	}
	return LockNoteResult{}, nil
}

func (m *mockRepository) InsertOperation(ctx context.Context, arg InsertOperationParams) (Operation, error) {
	return Operation{}, nil
}

func (m *mockRepository) GetOperationsSince(ctx context.Context, noteID pgtype.UUID, afterRevision int64) ([]Operation, error) {
	if m.getOperationsSinceFn != nil {
		return m.getOperationsSinceFn(ctx, noteID, afterRevision)
	}
	return nil, nil
}

func (m *mockRepository) GetOperationsRange(ctx context.Context, noteID pgtype.UUID, afterRevision int64, upToRevision int64) ([]Operation, error) {
	if m.getOperationsRangeFn != nil {
		return m.getOperationsRangeFn(ctx, noteID, afterRevision, upToRevision)
	}
	return nil, nil
}

func (m *mockRepository) GetLastOperation(ctx context.Context, noteID pgtype.UUID) (Operation, error) {
	return Operation{}, nil
}

func (m *mockRepository) UpdateNoteDocument(ctx context.Context, arg UpdateNoteDocumentParams) error {
	if m.updateNoteDocumentFn != nil {
		return m.updateNoteDocumentFn(ctx, arg)
	}
	return nil
}

func (m *mockRepository) GetNoteOperationByOpID(ctx context.Context, noteID pgtype.UUID, operationID pgtype.UUID) (Operation, error) {
	if m.getNoteOperationByOpIDFn != nil {
		return m.getNoteOperationByOpIDFn(ctx, noteID, operationID)
	}
	return Operation{}, pgx.ErrNoRows
}

func (m *mockRepository) CheckNotePermission(ctx context.Context, noteID pgtype.UUID, userID pgtype.UUID) (string, error) {
	if m.checkNotePermissionFn != nil {
		return m.checkNotePermissionFn(ctx, noteID, userID)
	}
	return "owner", nil
}

func (m *mockRepository) GetNoteDocument(ctx context.Context, noteID pgtype.UUID) (GetNoteDocumentResult, error) {
	if m.getNoteDocumentFn != nil {
		return m.getNoteDocumentFn(ctx, noteID)
	}
	return GetNoteDocumentResult{Revision: 0, Document: []byte(`{"schemaVersion":1,"blocks":[]}`)}, nil
}

func (m *mockRepository) WithQuerier(q sqlcgen.Querier) Repository {
	return m
}

func (m *mockRepository) WithTx(tx pgx.Tx) Repository {
	return m
}

func TestGetDocument(t *testing.T) {
	svc := NewService(&mockRepository{}, nil)

	docResp, err := svc.GetDocument(context.Background(), pgtype.UUID{}, pgtype.UUID{})
	assert.NoError(t, err)
	assert.Equal(t, int64(0), docResp.Revision)
}

func TestGetDocumentNoteNotFound(t *testing.T) {
	svc := NewService(&mockRepository{
		getNoteDocumentFn: func(ctx context.Context, noteID pgtype.UUID) (GetNoteDocumentResult, error) {
			return GetNoteDocumentResult{}, pgx.ErrNoRows
		},
	}, nil)

	_, err := svc.GetDocument(context.Background(), pgtype.UUID{}, pgtype.UUID{})
	assert.ErrorIs(t, err, ErrNoteNotFound)
}

func TestGetDocumentForbidden(t *testing.T) {
	svc := NewService(&mockRepository{
		checkNotePermissionFn: func(ctx context.Context, noteID pgtype.UUID, userID pgtype.UUID) (string, error) {
			return "none", nil
		},
	}, nil)

	_, err := svc.GetDocument(context.Background(), pgtype.UUID{}, pgtype.UUID{})
	assert.ErrorIs(t, err, ErrNoPermission)
}

func TestGetOperationsSince(t *testing.T) {
	svc := NewService(&mockRepository{
		getOperationsSinceFn: func(ctx context.Context, noteID pgtype.UUID, afterRevision int64) ([]Operation, error) {
			return []Operation{
				{Revision: 6, Kind: "text_delta"},
			}, nil
		},
	}, nil)

	resp, err := svc.GetOperationsSince(context.Background(), pgtype.UUID{}, pgtype.UUID{}, 5)
	assert.NoError(t, err)
	assert.Len(t, resp.Operations, 1)
}

func TestGetOperationsSinceForbidden(t *testing.T) {
	svc := NewService(&mockRepository{
		checkNotePermissionFn: func(ctx context.Context, noteID pgtype.UUID, userID pgtype.UUID) (string, error) {
			return "none", nil
		},
	}, nil)

	_, err := svc.GetOperationsSince(context.Background(), pgtype.UUID{}, pgtype.UUID{}, 0)
	assert.ErrorIs(t, err, ErrNoPermission)
}

func TestValidateAndTransformNoConcurrentOps(t *testing.T) {
	doc := Document{
		SchemaVersion: 1,
		Blocks: []Block{
			{ID: "b1", Type: string(BlockParagraph), Delta: nil, Metadata: map[string]any{}},
		},
	}
	opReq := OperationRequest{
		OperationID:  "550e8400-e29b-41d4-a716-446655440000",
		BaseRevision: 0,
		Kind:         "text_delta",
		BlockID:      strPtr("b1"),
		Payload:      json.RawMessage(`{"ops":[{"insert":"hello"}]}`),
	}

	err := validateAndTransform(context.Background(), &mockRepository{}, &opReq, pgtype.UUID{}, pgtype.UUID{}, &doc, pgtype.UUID{}, 0)
	assert.NoError(t, err)
}

func TestValidateAndTransformDetectsInvalidKind(t *testing.T) {
	doc := NewEmptyDocument()
	opReq := OperationRequest{
		OperationID:  "550e8400-e29b-41d4-a716-446655440000",
		BaseRevision: 0,
		Kind:         "invalid_kind",
		Payload:      json.RawMessage(`{}`),
	}

	err := validateAndTransform(context.Background(), &mockRepository{}, &opReq, pgtype.UUID{}, pgtype.UUID{}, &doc, pgtype.UUID{}, 0)
	assert.NotNil(t, err)
}

func TestMustParseUUID(t *testing.T) {
	u := mustParseUUID("550e8400-e29b-41d4-a716-446655440000")
	assert.True(t, u.Valid)
}

func TestMustParseUUIDInvalid(t *testing.T) {
	u := mustParseUUID("invalid")
	assert.False(t, u.Valid)
}

func TestPtrStr(t *testing.T) {
	s := "hello"
	assert.Equal(t, "hello", ptrStr(&s))
	assert.Equal(t, "", ptrStr(nil))
}

func TestBlockIDToString(t *testing.T) {
	assert.Equal(t, "b1", blockIDToString(pgtype.Text{String: "b1", Valid: true}))
	assert.Equal(t, "", blockIDToString(pgtype.Text{Valid: false}))
}

func TestPgtypeUUIDToString(t *testing.T) {
	id := mustParseUUID("550e8400-e29b-41d4-a716-446655440000")
	s := pgtypeUUIDToString(id)
	assert.Equal(t, "550e8400-e29b-41d4-a716-446655440000", s)

	assert.Equal(t, "", pgtypeUUIDToString(pgtype.UUID{Valid: false}))
}
