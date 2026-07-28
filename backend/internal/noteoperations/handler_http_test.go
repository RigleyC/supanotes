package noteoperations

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/go-playground/validator/v10"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/labstack/echo/v4"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/RigleyC/supanotes/internal/web"
)

type testValidator struct {
	v *validator.Validate
}

func (tv *testValidator) Validate(i any) error {
	return tv.v.Struct(i)
}

func TestGoBackendRealHttpServerRoutes(t *testing.T) {
	noteID := mustParseUUID("550e8400-e29b-41d4-a716-446655440001")
	userEdit := mustParseUUID("550e8400-e29b-41d4-a716-446655440002")
	userForbidden := mustParseUUID("550e8400-e29b-41d4-a716-446655440003")

	emptyDoc, err := json.Marshal(NewEmptyDocument())
	require.NoError(t, err)

	storedDocument := emptyDoc
	storedRevision := int64(0)
	storedOperations := map[uuid.UUID]Operation{}
	operationLog := []Operation{}

	repo := &mockRepository{
		checkNotePermissionFn: func(_ context.Context, _ pgtype.UUID, userID pgtype.UUID) (string, error) {
			if userID == userEdit {
				return "edit", nil
			}
			return "none", nil
		},
		lockNoteFn: func(context.Context, pgtype.UUID) (LockNoteResult, error) {
			return LockNoteResult{
				ID:       noteID,
				Revision: storedRevision,
				Document: storedDocument,
			}, nil
		},
		getNoteOperationByOpIDFn: func(_ context.Context, _ pgtype.UUID, operationID pgtype.UUID) (Operation, error) {
			op, exists := storedOperations[uuid.UUID(operationID.Bytes)]
			if !exists {
				return Operation{}, pgx.ErrNoRows
			}
			return op, nil
		},
		getNoteDocumentFn: func(context.Context, pgtype.UUID) (GetNoteDocumentResult, error) {
			return GetNoteDocumentResult{
				Revision: storedRevision,
				Document: storedDocument,
			}, nil
		},
		getOperationsSinceFn: func(_ context.Context, _ pgtype.UUID, afterRevision int64) ([]Operation, error) {
			ops := []Operation{}
			for _, op := range operationLog {
				if op.Revision > afterRevision {
					ops = append(ops, op)
				}
			}
			return ops, nil
		},
		getOperationsRangeFn: func(_ context.Context, _ pgtype.UUID, afterRevision int64, upToRevision int64) ([]Operation, error) {
			ops := []Operation{}
			for _, op := range operationLog {
				if op.Revision > afterRevision && op.Revision <= upToRevision {
					ops = append(ops, op)
				}
			}
			return ops, nil
		},
		updateNoteDocumentFn: func(_ context.Context, update UpdateNoteDocumentParams) error {
			storedDocument = update.Document
			storedRevision = update.Revision
			return nil
		},
	}
	repo.insertOperationFn = func(_ context.Context, insert InsertOperationParams) (Operation, error) {
		op := Operation{
			NoteID:       insert.NoteID,
			Revision:     insert.Revision,
			OperationID:  insert.OperationID,
			ActorID:      insert.ActorID,
			BaseRevision: insert.BaseRevision,
			Kind:         insert.Kind,
			BlockID:      insert.BlockID,
			Payload:      insert.Payload,
		}
		storedOperations[uuid.UUID(insert.OperationID.Bytes)] = op
		operationLog = append(operationLog, op)
		return op, nil
	}

	svc := NewServiceWithTransactionRunner(repo, immediateTransactionRunner{})
	handler := NewHandler(svc)

	e := echo.New()
	e.Validator = &testValidator{v: validator.New(validator.WithRequiredStructEnabled())}
	v1 := e.Group("/api/v1")
	v1.Use(func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			token := c.Request().Header.Get("X-Test-User")
			if token == "edit" {
				web.SetUserID(c, userEdit.String())
			} else if token == "forbidden" {
				web.SetUserID(c, userForbidden.String())
			} else {
				return web.JSONError(c, http.StatusUnauthorized, "UNAUTHORIZED")
			}
			return next(c)
		}
	})
	handler.RegisterRoutes(v1)

	ts := httptest.NewServer(e)
	defer ts.Close()

	client := ts.Client()

	t.Run("GET /api/v1/notes/:noteId/document over HTTP", func(t *testing.T) {
		req, err := http.NewRequest(http.MethodGet, ts.URL+"/api/v1/notes/"+noteID.String()+"/document", nil)
		require.NoError(t, err)
		req.Header.Set("X-Test-User", "edit")

		resp, err := client.Do(req)
		require.NoError(t, err)
		defer resp.Body.Close()

		assert.Equal(t, http.StatusOK, resp.StatusCode)

		var res DocumentResponse
		require.NoError(t, json.NewDecoder(resp.Body).Decode(&res))
		assert.Equal(t, int64(0), res.Revision)
	})

	t.Run("POST /api/v1/notes/:noteId/operations:sync over HTTP", func(t *testing.T) {
		blockID := "b1"
		syncReq := SyncRequest{
			KnownRevision: 0,
			ClientID:      "test-client",
			Operations: []OperationRequest{
				{
					OperationID:  uuid.NewString(),
					BaseRevision: 0,
					Kind:         string(KindCreateBlock),
					BlockID:      &blockID,
					Payload:      json.RawMessage(`{"id":"b1","type":"paragraph","delta":[{"insert":"Go HTTP real test"}]}`),
				},
			},
		}
		bodyBytes, err := json.Marshal(syncReq)
		require.NoError(t, err)

		req, err := http.NewRequest(http.MethodPost, ts.URL+"/api/v1/notes/"+noteID.String()+"/operations:sync", bytes.NewReader(bodyBytes))
		require.NoError(t, err)
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("X-Test-User", "edit")

		resp, err := client.Do(req)
		require.NoError(t, err)
		defer resp.Body.Close()

		assert.Equal(t, http.StatusOK, resp.StatusCode)

		var syncRes SyncResponse
		require.NoError(t, json.NewDecoder(resp.Body).Decode(&syncRes))
		assert.Len(t, syncRes.Accepted, 1)
		assert.Equal(t, int64(1), syncRes.FinalRevision)
	})

	t.Run("POST /api/v1/notes/:noteId/operations:sync 403 Forbidden over HTTP", func(t *testing.T) {
		syncReq := SyncRequest{
			KnownRevision: 0,
			ClientID:      "test-client",
			Operations:    []OperationRequest{},
		}
		bodyBytes, err := json.Marshal(syncReq)
		require.NoError(t, err)

		req, err := http.NewRequest(http.MethodPost, ts.URL+"/api/v1/notes/"+noteID.String()+"/operations:sync", bytes.NewReader(bodyBytes))
		require.NoError(t, err)
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("X-Test-User", "forbidden")

		resp, err := client.Do(req)
		require.NoError(t, err)
		defer resp.Body.Close()

		assert.Equal(t, http.StatusForbidden, resp.StatusCode)
	})

	t.Run("POST /api/v1/notes/:noteId/operations:sync 401 Unauthorized when missing auth", func(t *testing.T) {
		req, err := http.NewRequest(http.MethodPost, ts.URL+"/api/v1/notes/"+noteID.String()+"/operations:sync", bytes.NewReader([]byte("{}")))
		require.NoError(t, err)
		req.Header.Set("Content-Type", "application/json")

		resp, err := client.Do(req)
		require.NoError(t, err)
		defer resp.Body.Close()

		assert.Equal(t, http.StatusUnauthorized, resp.StatusCode)
	})
}
