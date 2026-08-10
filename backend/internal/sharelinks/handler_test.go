package sharelinks

import (
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
)

func TestPublicRendersCurrentDocumentWithSecurityHeaders(t *testing.T) {
	signer := NewTokenSigner("secret")
	token, err := signer.Sign(uuid.New())
	if err != nil {
		t.Fatalf("sign: %v", err)
	}
	repo := &fakeRepository{publicNote: PublicNote{Document: []byte(`{"schemaVersion":1,"blocks":[{"id":"p","type":"paragraph","delta":[{"insert":"Hello"}],"metadata":{}}]}`)}}
	h := NewHandler(NewService(repo, signer, "https://notes.example"))
	e := echo.New()
	req := httptest.NewRequest(http.MethodGet, "/s/"+token, nil)
	rec := httptest.NewRecorder()
	c := e.NewContext(req, rec)
	c.SetPath("/s/:token")
	c.SetParamNames("token")
	c.SetParamValues(token)

	if err := h.Public(c); err != nil {
		t.Fatalf("public: %v", err)
	}
	if rec.Code != http.StatusOK {
		t.Fatalf("status: got %d", rec.Code)
	}
	if rec.Header().Get("Cache-Control") != "no-store" {
		t.Fatalf("cache header: %q", rec.Header().Get("Cache-Control"))
	}
	if rec.Header().Get("X-Robots-Tag") == "" || rec.Header().Get("Referrer-Policy") != "no-referrer" {
		t.Fatal("privacy headers are incomplete")
	}
	if !strings.Contains(rec.Body.String(), "Hello") {
		t.Fatal("response does not contain rendered document")
	}
}

func TestPublicRejectsInvalidToken(t *testing.T) {
	h := NewHandler(NewService(&fakeRepository{}, NewTokenSigner("secret"), "https://notes.example"))
	e := echo.New()
	req := httptest.NewRequest(http.MethodGet, "/s/invalid", nil)
	rec := httptest.NewRecorder()
	c := e.NewContext(req, rec)
	c.SetPath("/s/:token")
	c.SetParamNames("token")
	c.SetParamValues("invalid")

	if err := h.Public(c); err != nil {
		t.Fatalf("public: %v", err)
	}
	if rec.Code != http.StatusNotFound {
		t.Fatalf("status: got %d", rec.Code)
	}
}

func TestPublicDoesNotHideRepositoryFailureAsNotFound(t *testing.T) {
	signer := NewTokenSigner("secret")
	token, err := signer.Sign(uuid.New())
	if err != nil {
		t.Fatalf("sign: %v", err)
	}
	repo := &fakeRepository{publicErr: errors.New("database unavailable")}
	h := NewHandler(NewService(repo, signer, "https://notes.example"))
	e := echo.New()
	req := httptest.NewRequest(http.MethodGet, "/s/"+token, nil)
	rec := httptest.NewRecorder()
	c := e.NewContext(req, rec)
	c.SetPath("/s/:token")
	c.SetParamNames("token")
	c.SetParamValues(token)

	if err := h.Public(c); err != nil {
		t.Fatalf("public: %v", err)
	}
	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status: got %d, want %d", rec.Code, http.StatusInternalServerError)
	}
}

func TestPublicDocumentRejectsInvalidSnapshotExplicitly(t *testing.T) {
	signer := NewTokenSigner("secret")
	token, err := signer.Sign(uuid.New())
	if err != nil {
		t.Fatalf("sign: %v", err)
	}
	repo := &fakeRepository{publicNote: PublicNote{Document: []byte("not-json")}}
	h := NewHandler(NewService(repo, signer, "https://notes.example"))
	e := echo.New()
	req := httptest.NewRequest(http.MethodGet, "/s/"+token+"/document", nil)
	rec := httptest.NewRecorder()
	c := e.NewContext(req, rec)
	c.SetPath("/s/:token/document")
	c.SetParamNames("token")
	c.SetParamValues(token)

	if err := h.PublicDocument(c); err != nil {
		t.Fatalf("public document: %v", err)
	}
	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status: got %d, want %d", rec.Code, http.StatusInternalServerError)
	}
}

func TestPublicDocumentUsesJSONErrorsForAPIRequests(t *testing.T) {
	h := NewHandler(NewService(&fakeRepository{}, NewTokenSigner("secret"), "https://notes.example"))
	e := echo.New()
	req := httptest.NewRequest(http.MethodGet, "/api/v1/s/invalid/document", nil)
	rec := httptest.NewRecorder()
	c := e.NewContext(req, rec)
	c.SetPath("/api/v1/s/:token/document")
	c.SetParamNames("token")
	c.SetParamValues("invalid")

	if err := h.PublicDocument(c); err != nil {
		t.Fatalf("public document: %v", err)
	}
	if rec.Code != http.StatusNotFound {
		t.Fatalf("status: got %d, want %d", rec.Code, http.StatusNotFound)
	}
	if !strings.Contains(rec.Body.String(), `"error":"share link not found"`) {
		t.Fatalf("response is not a JSON API error: %s", rec.Body.String())
	}
}
