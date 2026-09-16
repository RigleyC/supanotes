package mcpapp

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
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
	mu                  sync.Mutex
	confirmationID      pgtype.UUID
	created             bool
	reserved            bool
	committed           bool
	released            bool
	executionLeaseUntil time.Time
	ownerSequence       int
	currentOwnerToken   string
	commitErr           error
	result              json.RawMessage
}

func (s *confirmationStore) Audit(context.Context, AuditEvent) error { return nil }

func (s *confirmationStore) CreateConfirmation(context.Context, pgtype.UUID, string, string, json.RawMessage) (Confirmation, error) {
	s.created = true
	return Confirmation{ID: s.confirmationID, ExpiresAt: time.Now().UTC().Add(time.Minute)}, nil
}

type confirmationLease struct {
	store      *confirmationStore
	ownerToken string
	replay     json.RawMessage
}

func (l *confirmationLease) Commit(_ context.Context, result json.RawMessage) error {
	l.store.mu.Lock()
	defer l.store.mu.Unlock()
	if l.store.commitErr != nil {
		return l.store.commitErr
	}
	if !l.store.reserved || l.ownerToken == "" || l.ownerToken != l.store.currentOwnerToken {
		return ErrConfirmationDenied
	}
	l.store.committed = true
	l.store.reserved = false
	l.store.currentOwnerToken = ""
	l.store.executionLeaseUntil = time.Time{}
	l.store.result = append(json.RawMessage(nil), result...)
	return nil
}

func (l *confirmationLease) CommitMutation(ctx context.Context, mutation ConfirmationMutation) (json.RawMessage, error) {
	if mutation == nil {
		return nil, errors.New("mutation is missing")
	}
	result, err := mutation(ctx, nil)
	if err != nil {
		return nil, err
	}
	payload, err := json.Marshal(result)
	if err != nil {
		return nil, err
	}
	if err := l.Commit(ctx, payload); err != nil {
		return nil, err
	}
	return payload, nil
}

func (l *confirmationLease) Release(context.Context) error {
	l.store.mu.Lock()
	defer l.store.mu.Unlock()
	if !l.store.reserved || l.ownerToken == "" || l.ownerToken != l.store.currentOwnerToken {
		return ErrConfirmationDenied
	}
	l.store.released = true
	l.store.reserved = false
	l.store.currentOwnerToken = ""
	l.store.executionLeaseUntil = time.Time{}
	return nil
}

func (l *confirmationLease) ReplayResult() (json.RawMessage, bool) {
	if len(l.replay) == 0 {
		return nil, false
	}
	return append(json.RawMessage(nil), l.replay...), true
}

func (s *confirmationStore) ReserveConfirmation(_ context.Context, _ pgtype.UUID, confirmationID pgtype.UUID, _ string, _ string, _ json.RawMessage) (ConfirmationLease, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if confirmationID != s.confirmationID {
		return nil, ErrConfirmationDenied
	}
	if s.committed {
		return &confirmationLease{store: s, replay: append(json.RawMessage(nil), s.result...)}, nil
	}
	if s.reserved && time.Now().Before(s.executionLeaseUntil) {
		return nil, ErrConfirmationPending
	}
	s.reserved = true
	s.ownerSequence++
	ownerToken := fmt.Sprintf("owner-%d", s.ownerSequence)
	s.currentOwnerToken = ownerToken
	s.executionLeaseUntil = time.Now().Add(mcpConfirmationExecutionLease)
	return &confirmationLease{store: s, ownerToken: ownerToken}, nil
}

func (s *confirmationStore) replayRequest() *mcp.CallToolRequest {
	return &mcp.CallToolRequest{Params: &mcp.CallToolParamsRaw{Arguments: json.RawMessage(`{"id":"note-1","confirmation_id":"123e4567-e89b-12d3-a456-426614174001"}`)}}
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
	mutations := 0
	mutations++
	require.NoError(t, finishConfirmation(ctx, lease, "deleted", nil))
	assert.True(t, store.committed)
	assert.False(t, store.released)
	replayed, ok, replayErr := replayConfirmationMust(t, func() (ConfirmationLease, error) {
		return requireConfirmation(ctx, store, store.replayRequest(), "delete_note", "note:note-1")
	})
	require.NoError(t, replayErr)
	assert.True(t, ok)
	require.Len(t, replayed.Content, 1)
	assert.JSONEq(t, `"deleted"`, replayed.Content[0].(*mcp.TextContent).Text)
	assert.Equal(t, 1, mutations, "a committed replay must not execute the mutation again")
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

func TestFinishConfirmation_keepsReservationPendingWhenOperationFails(t *testing.T) {
	store := &confirmationStore{}
	lease := &confirmationLease{store: store}
	operationErr := errors.New("side effect failed")

	err := finishConfirmation(context.Background(), lease, nil, operationErr)

	assert.ErrorIs(t, err, operationErr)
	assert.False(t, store.released)
	assert.False(t, store.committed)
}

func TestConfirmation_crashBetweenMutationAndCommitLeavesRetryPending(t *testing.T) {
	userID, err := uid.UUIDFromString("123e4567-e89b-12d3-a456-426614174000")
	require.NoError(t, err)
	confirmationID, err := uid.UUIDFromString("123e4567-e89b-12d3-a456-426614174001")
	require.NoError(t, err)
	store := &confirmationStore{confirmationID: confirmationID, commitErr: errors.New("database connection lost")}
	ctx := context.WithValue(context.Background(), userContextKey, userID)
	lease, err := requireConfirmation(ctx, store, store.replayRequest(), "delete_note", "note:note-1")
	require.NoError(t, err)

	// The mutation has already happened; the persistence step simulates a crash.
	mutations := 0
	mutations++
	err = finishConfirmation(ctx, lease, "deleted", nil)
	assert.Error(t, err)

	_, err = requireConfirmation(ctx, store, store.replayRequest(), "delete_note", "note:note-1")
	assert.ErrorIs(t, err, ErrConfirmationPending)
	assert.Equal(t, 1, mutations, "a pending retry must not execute the mutation again")
}

func TestConfirmation_retryAfterExpiredLeaseDoesNotRepeatStableMutation(t *testing.T) {
	userID, err := uid.UUIDFromString("123e4567-e89b-12d3-a456-426614174000")
	require.NoError(t, err)
	confirmationID, err := uid.UUIDFromString("123e4567-e89b-12d3-a456-426614174001")
	require.NoError(t, err)
	store := &confirmationStore{
		confirmationID: confirmationID,
		commitErr:      errors.New("confirmation result persistence failed"),
	}
	ctx := context.WithValue(context.Background(), userContextKey, userID)

	first, err := requireConfirmation(ctx, store, store.replayRequest(), "delete_note", "note:note-1")
	require.NoError(t, err)
	applied := map[pgtype.UUID]bool{}
	mutations := 0
	applyStableMutation := func(lease ConfirmationLease) error {
		_, mutationErr := lease.CommitMutation(ctx, func(_ context.Context, _ pgx.Tx) (any, error) {
			// The confirmation ID is the stable operation key. The first owner
			// has already applied the effect when result persistence fails.
			if !applied[confirmationID] {
				applied[confirmationID] = true
				mutations++
			}
			return "deleted", nil
		})
		return mutationErr
	}

	assert.Error(t, applyStableMutation(first))
	store.mu.Lock()
	store.executionLeaseUntil = time.Now().Add(-time.Second)
	store.commitErr = nil
	store.mu.Unlock()

	second, err := requireConfirmation(ctx, store, store.replayRequest(), "delete_note", "note:note-1")
	require.NoError(t, err)
	require.NoError(t, applyStableMutation(second))
	assert.Equal(t, 1, mutations, "an expired-lease retry must not repeat an applied stable mutation")
}

func TestConfirmation_reclaimsExpiredLeaseAndFencesPreviousOwner(t *testing.T) {
	userID, err := uid.UUIDFromString("123e4567-e89b-12d3-a456-426614174000")
	require.NoError(t, err)
	confirmationID, err := uid.UUIDFromString("123e4567-e89b-12d3-a456-426614174001")
	require.NoError(t, err)
	store := &confirmationStore{confirmationID: confirmationID}
	ctx := context.WithValue(context.Background(), userContextKey, userID)

	first, err := requireConfirmation(ctx, store, store.replayRequest(), "delete_note", "note:note-1")
	require.NoError(t, err)
	store.mu.Lock()
	store.executionLeaseUntil = time.Now().Add(-time.Second)
	store.mu.Unlock()

	second, err := requireConfirmation(ctx, store, store.replayRequest(), "delete_note", "note:note-1")
	require.NoError(t, err)
	assert.ErrorIs(t, finishConfirmation(ctx, first, "stale", nil), ErrConfirmationDenied)
	assert.ErrorIs(t, first.Release(ctx), ErrConfirmationDenied)
	require.NoError(t, finishConfirmation(ctx, second, "deleted", nil))
}

func TestConfirmation_concurrentReservationsAllowOnlyOneExecutor(t *testing.T) {
	userID, err := uid.UUIDFromString("123e4567-e89b-12d3-a456-426614174000")
	require.NoError(t, err)
	confirmationID, err := uid.UUIDFromString("123e4567-e89b-12d3-a456-426614174001")
	require.NoError(t, err)
	store := &confirmationStore{confirmationID: confirmationID}
	ctx := context.WithValue(context.Background(), userContextKey, userID)

	const callers = 2
	results := make(chan error, callers)
	var wg sync.WaitGroup
	for range callers {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, reserveErr := requireConfirmation(ctx, store, store.replayRequest(), "delete_note", "note:note-1")
			results <- reserveErr
		}()
	}
	wg.Wait()
	close(results)

	var reserved, pending int
	for reserveErr := range results {
		if reserveErr == nil {
			reserved++
		}
		if errors.Is(reserveErr, ErrConfirmationPending) {
			pending++
		}
	}
	assert.Equal(t, 1, reserved)
	assert.Equal(t, 1, pending)
}

func replayConfirmationMust(t *testing.T, reserve func() (ConfirmationLease, error)) (*mcp.CallToolResult, bool, error) {
	t.Helper()
	lease, err := reserve()
	if err != nil {
		return nil, false, err
	}
	return replayConfirmation(lease)
}

func TestRequestedMCPScopes_validatesIndependentReadAndWriteScopes(t *testing.T) {
	scopes, err := requestedMCPScopes("")
	require.NoError(t, err)
	assert.Equal(t, []string{"read"}, scopes)

	scopes, err = requestedMCPScopes("read")
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

type issueTokenRow struct {
	id  pgtype.UUID
	err error
}

func (r issueTokenRow) Scan(dest ...any) error {
	if r.err != nil {
		return r.err
	}
	if len(dest) != 1 {
		return errors.New("unexpected issue token scan arguments")
	}
	target, ok := dest[0].(*pgtype.UUID)
	if !ok {
		return errors.New("unexpected issue token scan destination")
	}
	*target = r.id
	return nil
}

type issueTokenDB struct {
	id pgtype.UUID
}

func (d issueTokenDB) QueryRow(context.Context, string, ...any) pgx.Row {
	return issueTokenRow{id: d.id}
}

func TestIssueMCPToken_returnsTheTokenFieldConsumedByClients(t *testing.T) {
	userID, err := uid.UUIDFromString("123e4567-e89b-12d3-a456-426614174000")
	require.NoError(t, err)
	tokenID, err := uid.UUIDFromString("123e4567-e89b-12d3-a456-426614174001")
	require.NoError(t, err)

	result, err := issueMCPToken(
		context.Background(),
		issueTokenDB{id: tokenID},
		userID,
		"test client",
		[]string{"read", "write"},
	)

	require.NoError(t, err)
	assert.Equal(t, tokenID.String(), result["id"])
	assert.Equal(t, "test client", result["name"])
	assert.Equal(t, []string{"read", "write"}, result["scopes"])
	token, ok := result["token"].(string)
	require.True(t, ok)
	assert.True(t, strings.HasPrefix(token, "sn_mcp_"))
	assert.NotContains(t, result, "mcp_token")
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
