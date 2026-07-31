package mcpapp

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/labstack/echo/v4"
	"github.com/modelcontextprotocol/go-sdk/mcp"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/RigleyC/supanotes/pkg/uid"

	"github.com/RigleyC/supanotes/internal/web"
)

func TestGenerateMCPTokenHandler(t *testing.T) {
	e := echo.New()
	req := httptest.NewRequest(http.MethodPost, "/auth/mcp-token", nil)
	rec := httptest.NewRecorder()
	c := e.NewContext(req, rec)

	userID := "123e4567-e89b-12d3-a456-426614174000"
	web.SetUserID(c, userID)

	handler := GenerateMCPTokenHandler(nil)
	err := handler(c)

	assert.NoError(t, err)
	assert.Equal(t, http.StatusInternalServerError, rec.Code)
}

type confirmationStore struct {
	confirmationID pgtype.UUID
	created        bool
	reserved       bool
	committed      bool
	released       bool
}

func (s *confirmationStore) Audit(context.Context, AuditEvent) error { return nil }

func (s *confirmationStore) CreateConfirmation(context.Context, pgtype.UUID, string, string, json.RawMessage) (Confirmation, error) {
	s.created = true
	return Confirmation{ID: s.confirmationID, ExpiresAt: time.Now().UTC().Add(time.Minute)}, nil
}

type confirmationLease struct {
	store *confirmationStore
}

func (l *confirmationLease) Commit(context.Context) error {
	l.store.committed = true
	return nil
}

func (l *confirmationLease) Release(context.Context) error {
	l.store.released = true
	return nil
}

func (s *confirmationStore) ReserveConfirmation(_ context.Context, _ pgtype.UUID, confirmationID pgtype.UUID, _ string, _ string, _ json.RawMessage) (ConfirmationLease, error) {
	if confirmationID != s.confirmationID {
		return nil, ErrConfirmationDenied
	}
	s.reserved = true
	return &confirmationLease{store: s}, nil
}

func TestRequireConfirmation_requiresAndCommitsOneTimeID(t *testing.T) {
	userID, err := uid.UUIDFromString("123e4567-e89b-12d3-a456-426614174000")
	require.NoError(t, err)
	confirmationID, err := uid.UUIDFromString("123e4567-e89b-12d3-a456-426614174001")
	require.NoError(t, err)
	store := &confirmationStore{confirmationID: confirmationID}
	ctx := context.WithValue(context.Background(), userContextKey, userID)
	first := &mcp.CallToolRequest{Params: &mcp.CallToolParamsRaw{Arguments: json.RawMessage(`{"id":"note-1"}`)}}
	lease, err := requireConfirmation(ctx, store, first, "delete_note", "note:note-1")
	assert.Nil(t, lease)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "confirmation_required")
	assert.True(t, store.created)

	second := &mcp.CallToolRequest{Params: &mcp.CallToolParamsRaw{Arguments: json.RawMessage(`{"id":"note-1","confirmation_id":"123e4567-e89b-12d3-a456-426614174001"}`)}}
	lease, err = requireConfirmation(ctx, store, second, "delete_note", "note:note-1")
	require.NoError(t, err)
	assert.True(t, store.reserved)
	require.NoError(t, finishConfirmation(ctx, lease, nil))
	assert.True(t, store.committed)
	assert.False(t, store.released)
}

func TestRequireConfirmation_rejectsUnknownID(t *testing.T) {
	userID, err := uid.UUIDFromString("123e4567-e89b-12d3-a456-426614174000")
	require.NoError(t, err)
	knownID, err := uid.UUIDFromString("123e4567-e89b-12d3-a456-426614174001")
	require.NoError(t, err)
	store := &confirmationStore{confirmationID: knownID}
	ctx := context.WithValue(context.Background(), userContextKey, userID)
	request := &mcp.CallToolRequest{Params: &mcp.CallToolParamsRaw{Arguments: json.RawMessage(`{"id":"note-1","confirmation_id":"123e4567-e89b-12d3-a456-426614174002"}`)}}
	_, err = requireConfirmation(ctx, store, request, "delete_note", "note:note-1")
	assert.ErrorIs(t, err, ErrConfirmationDenied)
}

func TestFinishConfirmation_releasesLeaseWhenOperationFails(t *testing.T) {
	store := &confirmationStore{}
	lease := &confirmationLease{store: store}
	operationErr := errors.New("side effect failed")

	err := finishConfirmation(context.Background(), lease, operationErr)

	assert.ErrorIs(t, err, operationErr)
	assert.True(t, store.released)
	assert.False(t, store.committed)
}

func TestRequestedMCPScopes_validatesIndependentReadAndWriteScopes(t *testing.T) {
	scopes, err := requestedMCPScopes("read")
	require.NoError(t, err)
	assert.Equal(t, []string{"read"}, scopes)
	scopes, err = requestedMCPScopes("write,read,write")
	require.NoError(t, err)
	assert.Equal(t, []string{"write", "read"}, scopes)
	_, err = requestedMCPScopes("admin")
	assert.Error(t, err)
}

func TestRequireScopes_rejectsInsufficientScope(t *testing.T) {
	readOnly := context.WithValue(context.Background(), mcpScopesKey, []string{"read"})
	writeOnly := context.WithValue(context.Background(), mcpScopesKey, []string{"write"})
	assert.NoError(t, requireReadScope(readOnly))
	assert.Error(t, requireWriteScope(readOnly))
	assert.NoError(t, requireWriteScope(writeOnly))
	assert.Error(t, requireReadScope(writeOnly))
}

type tokenLookupRow struct{ err error }

func (r tokenLookupRow) Scan(...any) error { return r.err }

type tokenLookupDB struct {
	query string
	err   error
}

func (d *tokenLookupDB) QueryRow(_ context.Context, query string, _ ...any) pgx.Row {
	d.query = query
	return tokenLookupRow{err: d.err}
}

func TestAuthenticateMCPToken_rejectsExpiredAndRevokedRows(t *testing.T) {
	for _, name := range []string{"expired", "revoked"} {
		t.Run(name, func(t *testing.T) {
			db := &tokenLookupDB{err: pgx.ErrNoRows}
			_, _, _, err := authenticateMCPToken(context.Background(), db, "sn_mcp_test")
			assert.ErrorIs(t, err, ErrMCPTokenInvalid)
			assert.Contains(t, db.query, "revoked_at IS NULL")
			assert.Contains(t, db.query, "expires_at > NOW()")
		})
	}
}

func TestMCPAuth_rejectsMissingBearerToken(t *testing.T) {
	e := echo.New()
	req := httptest.NewRequest(http.MethodPost, "/mcp", nil)
	rec := httptest.NewRecorder()
	c := e.NewContext(req, rec)
	next := MCPAuth(nil)(func(c echo.Context) error { return c.NoContent(http.StatusNoContent) })
	require.NoError(t, next(c))
	assert.Equal(t, http.StatusUnauthorized, rec.Code)
}
