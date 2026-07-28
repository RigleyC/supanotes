package alexa

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/labstack/echo/v4"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/RigleyC/supanotes/internal/shoppinglist"
	"github.com/RigleyC/supanotes/pkg/auth"
)

type commandStub struct {
	err    error
	item   string
	userID pgtype.UUID
}

func (s *commandStub) AddItem(_ context.Context, userID pgtype.UUID, item string) error {
	s.userID, s.item = userID, item
	return s.err
}

func alexaRequest(t *testing.T, token, item string) *http.Request {
	t.Helper()
	body := map[string]any{
		"context": map[string]any{"System": map[string]any{"user": map[string]string{"accessToken": token}}},
		"request": map[string]any{"type": "IntentRequest", "intent": map[string]any{"name": "AddShoppingItemIntent", "slots": map[string]any{"item": map[string]string{"value": item}}}},
	}
	data, err := json.Marshal(body)
	require.NoError(t, err)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/integrations/alexa", bytes.NewReader(data))
	req.Header.Set(echo.HeaderContentType, echo.MIMEApplicationJSON)
	return req
}

func TestHandlerAddsItemAndSpeaksSuccess(t *testing.T) {
	secret := "test-secret-with-at-least-32-characters"
	user := uuid.New()
	token, err := auth.GenerateAccessToken(user.String(), secret, auth.AccessTokenTTL)
	require.NoError(t, err)
	stub := &commandStub{}
	h := NewHandler(stub, secret, "")
	e := echo.New()
	rec := httptest.NewRecorder()
	require.NoError(t, h.Handle(e.NewContext(alexaRequest(t, token, "café"), rec)))

	assert.Equal(t, http.StatusOK, rec.Code)
	assert.Equal(t, "café", stub.item)
	assert.Contains(t, rec.Body.String(), "café foi adicionado")
}

func TestHandlerRequiresAccountLinking(t *testing.T) {
	stub := &commandStub{}
	h := NewHandler(stub, "test-secret-with-at-least-32-characters", "")
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
			token, err := auth.GenerateAccessToken(uuid.NewString(), secret, auth.AccessTokenTTL)
			require.NoError(t, err)
			h := NewHandler(&commandStub{err: tc.err}, secret, "")
			e := echo.New()
			rec := httptest.NewRecorder()
			require.NoError(t, h.Handle(e.NewContext(alexaRequest(t, token, "café"), rec)))
			assert.Equal(t, http.StatusOK, rec.Code)
			assert.Contains(t, rec.Body.String(), tc.want)
		})
	}
}
