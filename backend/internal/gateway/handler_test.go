package gateway

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/labstack/echo/v4"
)

func TestWebhook_SecretToken(t *testing.T) {
	tests := []struct {
		name       string
		secret     string
		headerVal  string
		wantStatus int
	}{
		{
			name:       "no secret configured passes through",
			secret:     "",
			headerVal:  "",
			wantStatus: http.StatusOK,
		},
		{
			name:       "missing header rejected",
			secret:     "s3cret",
			headerVal:  "",
			wantStatus: http.StatusUnauthorized,
		},
		{
			name:       "wrong token rejected",
			secret:     "s3cret",
			headerVal:  "wrong-token",
			wantStatus: http.StatusUnauthorized,
		},
		{
			name:       "correct token allowed",
			secret:     "s3cret",
			headerVal:  "s3cret",
			wantStatus: http.StatusOK,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			h := NewHandler(nil, nil, nil, tt.secret)

			e := echo.New()
			req := httptest.NewRequest(http.MethodPost, "/", strings.NewReader("{}"))
			req.Header.Set(echo.HeaderContentType, echo.MIMEApplicationJSON)
			if tt.headerVal != "" {
				req.Header.Set("X-Telegram-Bot-Api-Secret-Token", tt.headerVal)
			}
			rec := httptest.NewRecorder()
			c := e.NewContext(req, rec)
			c.SetPath("/api/v1/gateway/telegram/webhook")

			err := h.Webhook(c)
			if err != nil {
				t.Fatalf("Webhook returned error: %v", err)
			}

			if rec.Code != tt.wantStatus {
				t.Errorf("status: want %d, got %d", tt.wantStatus, rec.Code)
			}
		})
	}
}
