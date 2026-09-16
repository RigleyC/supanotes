package noteoperations

import (
	"context"
	"encoding/json"
	"sync"
	"testing"

	"github.com/fmpwizard/go-quilljs-delta/delta"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

type mockRepository struct {
	ensureNoteFn                 func(ctx context.Context, noteID pgtype.UUID, userID pgtype.UUID) error
	lockNoteFn                   func(ctx context.Context, noteID pgtype.UUID) (LockNoteResult, error)
	getOperationsSinceFn         func(ctx context.Context, noteID pgtype.UUID, afterRevision int64) ([]Operation, error)
	getOperationsRangeFn         func(ctx context.Context, noteID pgtype.UUID, afterRevision int64, upToRevision int64) ([]Operation, error)
	updateNoteDocumentFn         func(ctx context.Context, arg UpdateNoteDocumentParams) error
	insertOperationFn            func(ctx context.Context, arg InsertOperationParams) (Operation, error)
	getNoteOperationByOpIDFn     func(ctx context.Context, noteID pgtype.UUID, operationID pgtype.UUID) (Operation, error)
	checkNotePermissionFn        func(ctx context.Context, noteID pgtype.UUID, userID pgtype.UUID) (string, error)
	getNoteDocumentFn            func(ctx context.Context, noteID pgtype.UUID) (GetNoteDocumentResult, error)
	reserveSharedLinkIngestionFn func(ctx context.Context, userID, shareID, noteID, operationID pgtype.UUID) (sqlcgen.SharedLinkIngestion, error)
}

type immediateTransactionRunner struct{}

func (immediateTransactionRunner) InTx(ctx context.Context, repo Repository, fn func(Repository) error) error {
	return fn(repo)
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
	if m.insertOperationFn != nil {
		return m.insertOperationFn(ctx, arg)
	}
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
	document, err := json.Marshal(NewEmptyDocument())
	if err != nil {
		return GetNoteDocumentResult{}, err
	}
	return GetNoteDocumentResult{Revision: 0, Document: document}, nil
}

func (m *mockRepository) ReserveSharedLinkIngestion(ctx context.Context, userID, shareID, noteID, operationID pgtype.UUID) (sqlcgen.SharedLinkIngestion, error) {
	if m.reserveSharedLinkIngestionFn != nil {
		return m.reserveSharedLinkIngestionFn(ctx, userID, shareID, noteID, operationID)
	}
	return sqlcgen.SharedLinkIngestion{
		UserID:      userID,
		ShareID:     shareID,
		NoteID:      noteID,
		OperationID: operationID,
	}, nil
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

func TestGetDocumentRejectsNonCanonicalDeltaOperations(t *testing.T) {
	svc := NewService(&mockRepository{
		getNoteDocumentFn: func(context.Context, pgtype.UUID) (GetNoteDocumentResult, error) {
			return GetNoteDocumentResult{
				Revision: 7,
				Document: []byte(`{
					"schemaVersion":1,
					"blocks":[{
						"id":"b1",
						"type":"paragraph",
						"delta":[{"insert":"kept"},{"delete":4}],
						"metadata":{}
					}]
				}`),
			}, nil
		},
	}, nil)

	_, err := svc.GetDocument(context.Background(), pgtype.UUID{}, pgtype.UUID{})
	assert.Error(t, err)
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

func TestSyncOperationsReplaysSameOperationIdentityIdempotently(t *testing.T) {
	blockID := "b1"
	payload := json.RawMessage(`{"ops":[{"insert":"hello"}]}`)
	existing := Operation{
		Revision:     4,
		BaseRevision: 2,
		Kind:         string(KindTextDelta),
		BlockID:      pgtype.Text{String: blockID, Valid: true},
		Payload:      payload,
	}
	inserted := false
	repo := &mockRepository{
		lockNoteFn: func(context.Context, pgtype.UUID) (LockNoteResult, error) {
			document, err := json.Marshal(NewEmptyDocument())
			return LockNoteResult{Revision: 4, Document: document}, err
		},
		getNoteOperationByOpIDFn: func(context.Context, pgtype.UUID, pgtype.UUID) (Operation, error) {
			return existing, nil
		},
		insertOperationFn: func(context.Context, InsertOperationParams) (Operation, error) {
			inserted = true
			return Operation{}, nil
		},
	}

	response, err := syncOperationsInRepository(context.Background(), repo, pgtype.UUID{}, pgtype.UUID{}, SyncRequest{
		Operations: []OperationRequest{{
			OperationID:  "550e8400-e29b-41d4-a716-446655440000",
			BaseRevision: existing.BaseRevision,
			Kind:         existing.Kind,
			BlockID:      &blockID,
			Payload:      payload,
		}},
	})

	require.NoError(t, err)
	assert.False(t, inserted)
	require.Len(t, response.Accepted, 1)
	assert.Equal(t, existing.Revision, response.Accepted[0].Revision)
}

func TestSyncOperationsRejectsOperationIDReuseWithDifferentIdentity(t *testing.T) {
	blockID := "b1"
	payload := json.RawMessage(`{"ops":[{"insert":"hello"}]}`)
	existing := Operation{
		Revision:     4,
		BaseRevision: 2,
		Kind:         string(KindTextDelta),
		BlockID:      pgtype.Text{String: blockID, Valid: true},
		Payload:      payload,
	}
	repo := &mockRepository{
		lockNoteFn: func(context.Context, pgtype.UUID) (LockNoteResult, error) {
			document, err := json.Marshal(NewEmptyDocument())
			return LockNoteResult{Revision: 4, Document: document}, err
		},
		getNoteOperationByOpIDFn: func(context.Context, pgtype.UUID, pgtype.UUID) (Operation, error) {
			return existing, nil
		},
	}

	tests := map[string]func(*OperationRequest){
		"payload": func(request *OperationRequest) {
			request.Payload = json.RawMessage(`{"ops":[{"insert":"different"}]}`)
		},
		"kind": func(request *OperationRequest) {
			request.Kind = string(KindSetBlockType)
		},
		"block id": func(request *OperationRequest) {
			otherBlockID := "b2"
			request.BlockID = &otherBlockID
		},
		"base revision": func(request *OperationRequest) {
			request.BaseRevision++
		},
	}

	for name, mutate := range tests {
		t.Run(name, func(t *testing.T) {
			request := OperationRequest{
				OperationID:  "550e8400-e29b-41d4-a716-446655440000",
				BaseRevision: existing.BaseRevision,
				Kind:         existing.Kind,
				BlockID:      &blockID,
				Payload:      payload,
			}
			mutate(&request)

			_, err := syncOperationsInRepository(context.Background(), repo, pgtype.UUID{}, pgtype.UUID{}, SyncRequest{Operations: []OperationRequest{request}})
			var conflict *OperationIDConflictError
			require.ErrorAs(t, err, &conflict)
			assert.Equal(t, request.OperationID, conflict.OperationID)
		})
	}
}

func TestSyncOperationsRejectsInvalidSnapshotWithoutRepairingIt(t *testing.T) {
	updated := false
	repo := &mockRepository{
		lockNoteFn: func(context.Context, pgtype.UUID) (LockNoteResult, error) {
			return LockNoteResult{Revision: 2, Document: []byte(`{
				"schemaVersion":1,
				"blocks":[{"id":"b1","type":"paragraph","delta":[{"insert":"kept"},{"delete":4}],"metadata":{}}]
			}`)}, nil
		},
		updateNoteDocumentFn: func(context.Context, UpdateNoteDocumentParams) error {
			updated = true
			return nil
		},
	}

	_, err := syncOperationsInRepository(context.Background(), repo, pgtype.UUID{}, pgtype.UUID{}, SyncRequest{})
	require.Error(t, err)
	assert.False(t, updated)
	assert.Contains(t, err.Error(), "non-text delta")
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

type serializedOperationRepository struct {
	*mockRepository
	mu         sync.Mutex
	document   []byte
	revision   int64
	operations map[uuid.UUID]Operation
	insertions int
}

func (r *serializedOperationRepository) LockNote(context.Context, pgtype.UUID) (LockNoteResult, error) {
	return LockNoteResult{Revision: r.revision, Document: r.document}, nil
}

func (r *serializedOperationRepository) GetNoteOperationByOpID(_ context.Context, _ pgtype.UUID, operationID pgtype.UUID) (Operation, error) {
	operation, ok := r.operations[uuid.UUID(operationID.Bytes)]
	if !ok {
		return Operation{}, pgx.ErrNoRows
	}
	return operation, nil
}

func (r *serializedOperationRepository) InsertOperation(_ context.Context, arg InsertOperationParams) (Operation, error) {
	operation := Operation{
		NoteID:       arg.NoteID,
		Revision:     arg.Revision,
		OperationID:  arg.OperationID,
		ActorID:      arg.ActorID,
		BaseRevision: arg.BaseRevision,
		Kind:         arg.Kind,
		BlockID:      arg.BlockID,
		Payload:      arg.Payload,
	}
	r.operations[uuid.UUID(arg.OperationID.Bytes)] = operation
	r.insertions++
	return operation, nil
}

func (r *serializedOperationRepository) UpdateNoteDocument(_ context.Context, arg UpdateNoteDocumentParams) error {
	r.document = arg.Document
	r.revision = arg.Revision
	return nil
}

func (r *serializedOperationRepository) WithTx(_ pgx.Tx) Repository { return r }

type serializedOperationRunner struct {
	repo *serializedOperationRepository
}

func (r serializedOperationRunner) InTx(ctx context.Context, repo Repository, fn func(Repository) error) error {
	r.repo.mu.Lock()
	defer r.repo.mu.Unlock()
	return fn(repo)
}

func TestSyncOperationsConcurrentReplayPersistsOneMutation(t *testing.T) {
	document, err := json.Marshal(NewEmptyDocument())
	require.NoError(t, err)
	repo := &serializedOperationRepository{
		mockRepository: &mockRepository{},
		document:       document,
		operations:     make(map[uuid.UUID]Operation),
	}
	service := NewServiceWithTransactionRunner(repo, serializedOperationRunner{repo: repo})
	noteID := mustParseUUID("550e8400-e29b-41d4-a716-446655440001")
	userID := mustParseUUID("550e8400-e29b-41d4-a716-446655440002")
	operationID := "550e8400-e29b-41d4-a716-446655440003"
	blockID := "shopping-list-item-" + operationID
	payload, err := json.Marshal(CreateBlockPayload{
		ID: blockID, Type: string(BlockTask), Delta: []delta.Op{{Insert: []rune("café")}},
	})
	require.NoError(t, err)
	request := SyncRequest{Operations: []OperationRequest{{
		OperationID: operationID,
		Kind:        string(KindCreateBlock),
		BlockID:     &blockID,
		Payload:     payload,
	}}}

	responses := make(chan SyncResponse, 2)
	errors := make(chan error, 2)
	var waitGroup sync.WaitGroup
	for range 2 {
		waitGroup.Add(1)
		go func() {
			defer waitGroup.Done()
			response, syncErr := service.SyncOperations(context.Background(), noteID, userID, request)
			responses <- response
			errors <- syncErr
		}()
	}
	waitGroup.Wait()
	close(responses)
	close(errors)

	for syncErr := range errors {
		require.NoError(t, syncErr)
	}
	for response := range responses {
		require.Len(t, response.Accepted, 1)
		assert.Equal(t, int64(1), response.Accepted[0].Revision)
	}
	assert.Equal(t, 1, repo.insertions)
	assert.Equal(t, int64(1), repo.revision)
	assert.Len(t, repo.operations, 1)
}
