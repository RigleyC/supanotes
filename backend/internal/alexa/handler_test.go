package alexa

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/labstack/echo/v4"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/RigleyC/supanotes/internal/shoppinglist"
	"github.com/RigleyC/supanotes/pkg/auth"
)

type commandStub struct {
	mu          sync.Mutex
	err         error
	item        string
	userID      pgtype.UUID
	operationID uuid.UUID
	calls       int
	sideEffects int
	effects     map[uuid.UUID]struct{}
}

func (s *commandStub) AddItem(_ context.Context, userID pgtype.UUID, item string, operationID uuid.UUID) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.calls++
	s.userID, s.item, s.operationID = userID, item, operationID
	if s.effects == nil {
		s.effects = make(map[uuid.UUID]struct{})
	}
	if _, exists := s.effects[operationID]; !exists {
		s.effects[operationID] = struct{}{}
		s.sideEffects++
	}
	return s.err
}

type failFirstCompleteStore struct {
	inner    *memoryIdempotencyStore
	failNext bool
}

func (s *failFirstCompleteStore) Acquire(ctx context.Context, applicationID, requestID, fingerprint string) (idempotencyDecision, error) {
	return s.inner.Acquire(ctx, applicationID, requestID, fingerprint)
}

func (s *failFirstCompleteStore) Complete(ctx context.Context, reservation idempotencyReservation, result response) error {
	if s.failNext {
		s.failNext = false
		return errors.New("complete unavailable")
	}
	return s.inner.Complete(ctx, reservation, result)
}

type acceptingAuthenticator struct {
	err error
}

func (a acceptingAuthenticator) Verify(context.Context, []byte, http.Header) error {
	return a.err
}

func alexaRequest(t *testing.T, token, item string) *http.Request {
	t.Helper()
	body := map[string]any{
		"context": map[string]any{"System": map[string]any{"application": map[string]string{"applicationId": "amzn1.ask.skill.test"}, "user": map[string]string{"accessToken": token}}},
		"request": map[string]any{"type": "IntentRequest", "requestId": "request-123", "timestamp": time.Now().UTC().Format(time.RFC3339), "intent": map[string]any{"name": "AddShoppingItemIntent", "slots": map[string]any{"item": map[string]string{"value": item}}}},
	}
	data, err := json.Marshal(body)
	require.NoError(t, err)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/integrations/alexa", bytes.NewReader(data))
	req.Header.Set(echo.HeaderContentType, echo.MIMEApplicationJSON)
	return req
}

func TestHandlerAddsItemAndSpeaksSuccess(t *testing.T) {
	secret := "test-secret-with-at-least-32-characters"
	options := auth.TokenOptions{Issuer: "supanotes-api", Audience: "supanotes-client"}
	user := uuid.New()
	token, err := auth.GenerateAccessToken(user.String(), secret, auth.AccessTokenTTL, options)
	require.NoError(t, err)
	stub := &commandStub{}
	h := NewHandler(stub, secret, "amzn1.ask.skill.test", options, acceptingAuthenticator{}, newMemoryIdempotencyStore(time.Minute, time.Minute))
	e := echo.New()
	rec := httptest.NewRecorder()
	require.NoError(t, h.Handle(e.NewContext(alexaRequest(t, token, "café"), rec)))

	assert.Equal(t, http.StatusOK, rec.Code)
	assert.Equal(t, "café", stub.item)
	assert.Contains(t, rec.Body.String(), "café foi adicionado")
}

func TestHandlerRequiresAccountLinking(t *testing.T) {
	stub := &commandStub{}
	h := NewHandler(stub, "test-secret-with-at-least-32-characters", "amzn1.ask.skill.test", auth.TokenOptions{Issuer: "supanotes-api", Audience: "supanotes-client"}, acceptingAuthenticator{}, newMemoryIdempotencyStore(time.Minute, time.Minute))
	e := echo.New()
	rec := httptest.NewRecorder()
	require.NoError(t, h.Handle(e.NewContext(alexaRequest(t, "", "café"), rec)))

	assert.Equal(t, http.StatusOK, rec.Code)
	assert.Contains(t, rec.Body.String(), "vincular sua conta")
	assert.Empty(t, stub.item)
}

func TestHandlerMapsCommandErrorsToVoice(t *testing.T) {
	tests := []struct {
		name string
		err  error
		want string
	}{
		{"missing list", shoppinglist.ErrShoppingNotFound, "Não encontrei uma nota"},
		{"ambiguous list", shoppinglist.ErrShoppingAmbiguous, "mais de uma nota"},
		{"empty item", shoppinglist.ErrEmptyItem, "Qual item"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			secret := "test-secret-with-at-least-32-characters"
			options := auth.TokenOptions{Issuer: "supanotes-api", Audience: "supanotes-client"}
			token, err := auth.GenerateAccessToken(uuid.NewString(), secret, auth.AccessTokenTTL, options)
			require.NoError(t, err)
			h := NewHandler(&commandStub{err: tc.err}, secret, "amzn1.ask.skill.test", options, acceptingAuthenticator{}, newMemoryIdempotencyStore(time.Minute, time.Minute))
			e := echo.New()
			rec := httptest.NewRecorder()
			require.NoError(t, h.Handle(e.NewContext(alexaRequest(t, token, "café"), rec)))
			assert.Equal(t, http.StatusOK, rec.Code)
			assert.Contains(t, rec.Body.String(), tc.want)
		})
	}
}

func TestHandlerCompletesIdempotencyReservationWhenCommandFails(t *testing.T) {
	secret := "test-secret-with-at-least-32-characters"
	options := auth.TokenOptions{Issuer: "supanotes-api", Audience: "supanotes-client"}
	token, err := auth.GenerateAccessToken(uuid.NewString(), secret, auth.AccessTokenTTL, options)
	require.NoError(t, err)
	stub := &commandStub{err: errors.New("shopping list unavailable")}
	h := NewHandler(stub, secret, "amzn1.ask.skill.test", options, acceptingAuthenticator{}, newMemoryIdempotencyStore(time.Minute, time.Minute))
	e := echo.New()

	request := alexaRequest(t, token, "café")
	body, err := io.ReadAll(request.Body)
	require.NoError(t, err)

	first := httptest.NewRecorder()
	request.Body = io.NopCloser(bytes.NewReader(body))
	require.NoError(t, h.Handle(e.NewContext(request, first)))
	second := httptest.NewRecorder()
	require.NoError(t, h.Handle(e.NewContext(httptest.NewRequest(http.MethodPost, "/", bytes.NewReader(body)), second)))

	assert.Equal(t, http.StatusOK, first.Code)
	assert.Equal(t, http.StatusOK, second.Code)
	assert.Equal(t, first.Body.String(), second.Body.String())
	assert.Equal(t, 1, stub.calls)
}

func TestHandlerRejectsUnsignedRequestBeforeBusinessLogic(t *testing.T) {
	stub := &commandStub{}
	h := NewHandler(stub, "test-secret-with-at-least-32-characters", "amzn1.ask.skill.test", auth.TokenOptions{}, acceptingAuthenticator{err: errors.New("invalid signature")}, newMemoryIdempotencyStore(time.Minute, time.Minute))
	recorder := httptest.NewRecorder()
	require.NoError(t, h.Handle(echo.New().NewContext(alexaRequest(t, "", "café"), recorder)))

	assert.Equal(t, http.StatusBadRequest, recorder.Code)
	assert.Zero(t, stub.calls)
}

func TestHandlerProcessesAnAlexaRequestIDOnlyOnce(t *testing.T) {
	secret := "test-secret-with-at-least-32-characters"
	options := auth.TokenOptions{Issuer: "supanotes-api", Audience: "supanotes-client"}
	token, err := auth.GenerateAccessToken(uuid.NewString(), secret, auth.AccessTokenTTL, options)
	require.NoError(t, err)
	stub := &commandStub{}
	h := NewHandler(stub, secret, "amzn1.ask.skill.test", options, acceptingAuthenticator{}, newMemoryIdempotencyStore(time.Minute, time.Minute))
	e := echo.New()

	first := httptest.NewRecorder()
	require.NoError(t, h.Handle(e.NewContext(alexaRequest(t, token, "café"), first)))
	second := httptest.NewRecorder()
	require.NoError(t, h.Handle(e.NewContext(alexaRequest(t, token, "café"), second)))

	assert.Equal(t, http.StatusOK, first.Code)
	assert.Equal(t, http.StatusOK, second.Code)
	assert.Equal(t, 1, stub.calls)
	assert.Equal(t, first.Body.String(), second.Body.String())
}

func TestHandlerRejectsRequestIDPayloadReuse(t *testing.T) {
	secret := "test-secret-with-at-least-32-characters"
	options := auth.TokenOptions{Issuer: "supanotes-api", Audience: "supanotes-client"}
	token, err := auth.GenerateAccessToken(uuid.NewString(), secret, auth.AccessTokenTTL, options)
	require.NoError(t, err)
	h := NewHandler(&commandStub{}, secret, "amzn1.ask.skill.test", options, acceptingAuthenticator{}, newMemoryIdempotencyStore(time.Minute, time.Minute))
	e := echo.New()

	first := httptest.NewRecorder()
	require.NoError(t, h.Handle(e.NewContext(alexaRequest(t, token, "café"), first)))
	second := httptest.NewRecorder()
	require.NoError(t, h.Handle(e.NewContext(alexaRequest(t, token, "chá"), second)))

	assert.Equal(t, http.StatusBadRequest, second.Code)
}

func TestValidateRequestTimestampRejectsReplay(t *testing.T) {
	now := time.Date(2026, 9, 16, 12, 0, 0, 0, time.UTC)
	for _, timestamp := range []string{
		now.Add(-151 * time.Second).Format(time.RFC3339),
		now.Add(151 * time.Second).Format(time.RFC3339),
		"not-a-timestamp",
	} {
		if err := validateRequestTimestamp(timestamp, now); err == nil {
			t.Errorf("validateRequestTimestamp(%q): want error", timestamp)
		}
	}
}

func TestOperationIDForRequestIsDeterministicAndScoped(t *testing.T) {
	first := operationIDForRequest("application", "request-123")
	second := operationIDForRequest("application", "request-123")
	otherRequest := operationIDForRequest("application", "request-124")
	otherApplication := operationIDForRequest("other-application", "request-123")

	assert.Equal(t, first, second)
	assert.NotEqual(t, first, otherRequest)
	assert.NotEqual(t, first, otherApplication)
}

func TestHandlerRetriesAfterCompletionFailureWithoutRepeatingCommandEffect(t *testing.T) {
	secret := "test-secret-with-at-least-32-characters"
	options := auth.TokenOptions{Issuer: "supanotes-api", Audience: "supanotes-client"}
	token, err := auth.GenerateAccessToken(uuid.NewString(), secret, auth.AccessTokenTTL, options)
	require.NoError(t, err)
	clock := time.Now().UTC()
	inner := newMemoryIdempotencyStore(time.Minute, time.Second)
	inner.now = func() time.Time { return clock }
	store := &failFirstCompleteStore{inner: inner, failNext: true}
	stub := &commandStub{}
	h := NewHandler(stub, secret, "amzn1.ask.skill.test", options, acceptingAuthenticator{}, store)
	e := echo.New()

	request := alexaRequest(t, token, "café")
	body, err := io.ReadAll(request.Body)
	require.NoError(t, err)
	request.Body = io.NopCloser(bytes.NewReader(body))
	first := httptest.NewRecorder()
	require.Error(t, h.Handle(e.NewContext(request, first)))

	clock = clock.Add(2 * time.Second)
	second := httptest.NewRecorder()
	require.NoError(t, h.Handle(e.NewContext(httptest.NewRequest(http.MethodPost, "/", bytes.NewReader(body)), second)))

	assert.Equal(t, http.StatusOK, second.Code)
	assert.Equal(t, 2, stub.calls)
	assert.Equal(t, 1, stub.sideEffects)
}
