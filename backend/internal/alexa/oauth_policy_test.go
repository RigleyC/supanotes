package alexa

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/RigleyC/supanotes/pkg/config"
	"github.com/labstack/echo/v4"
)

func TestOAuthHandlerValidRedirect_UsesExactAllowlist(t *testing.T) {
	h := &OAuthHandler{cfg: &config.Config{
		AlexaRedirectURIs: []string{"https://example.com/alexa/callback"},
	}}

	if got, err := h.validRedirect("https://example.com/alexa/callback"); err != nil || got == "" {
		t.Fatalf("registered redirect rejected: got=%q err=%v", got, err)
	}
	for _, redirect := range []string{
		"https://example.com/alexa/other",
		"https://attacker.example/callback",
		"http://example.com/alexa/callback",
		"https://user:pass@example.com/alexa/callback",
	} {
		if _, err := h.validRedirect(redirect); err == nil {
			t.Errorf("unregistered redirect accepted: %q", redirect)
		}
	}
}

func TestOAuthHandlerRejectsMissingConfiguration(t *testing.T) {
	h := &OAuthHandler{cfg: &config.Config{}}
	recorder := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/oauth/token", nil)

	if err := h.Token(echo.New().NewContext(req, recorder)); err != nil {
		t.Fatalf("Token() returned error: %v", err)
	}
	if recorder.Code != http.StatusServiceUnavailable {
		t.Fatalf("Token() status = %d, want %d", recorder.Code, http.StatusServiceUnavailable)
	}
}
