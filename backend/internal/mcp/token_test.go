package mcpapp

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/labstack/echo/v4"
	"github.com/stretchr/testify/assert"

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

func TestPropagateUserContext(t *testing.T) {
	e := echo.New()
	req := httptest.NewRequest(http.MethodGet, "/mcp", nil)
	rec := httptest.NewRecorder()
	c := e.NewContext(req, rec)

	var extractedUserID pgtype.UUID
	var extractionErr error

	nextHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		extractedUserID, extractionErr = UserIDFromContext(r.Context())
	})

	handler := PropagateUserContext(nextHandler)
	err := handler(c)

	assert.NoError(t, err)
	assert.Error(t, extractionErr)

	assert.Equal(t, pgtype.UUID{}, extractedUserID)
	assert.Error(t, extractionErr)
}
