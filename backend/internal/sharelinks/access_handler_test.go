package sharelinks

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
)

func TestAccessValidatesTokenAndReturnsNoteID(t *testing.T) {
	noteID := uuid.New()
	signer := NewTokenSigner("secret")
	token, err := signer.Sign(uuid.New())
	if err != nil {
		t.Fatalf("sign: %v", err)
	}
	repo := &fakeRepository{publicNote: PublicNote{ID: noteID}}
	h := NewHandler(NewService(repo, signer, "https://notes.example"))

	e := echo.New()
	req := httptest.NewRequest(http.MethodGet, "/s/"+token+"/access", nil)
	rec := httptest.NewRecorder()
	c := e.NewContext(req, rec)
	c.SetPath("/s/:token/access")
	c.SetParamNames("token")
	c.SetParamValues(token)

	if err := h.Access(c); err != nil {
		t.Fatalf("access: %v", err)
	}
	if rec.Code != http.StatusOK {
		t.Fatalf("status: got %d", rec.Code)
	}
	if rec.Body.String() != `{"note_id":"`+noteID.String()+`"}`+"\n" {
		t.Fatalf("body: got %q", rec.Body.String())
	}
}

func TestAccessRejectsInvalidToken(t *testing.T) {
	h := NewHandler(NewService(&fakeRepository{}, NewTokenSigner("secret"), ""))
	e := echo.New()
	req := httptest.NewRequest(http.MethodGet, "/s/invalid/access", nil)
	rec := httptest.NewRecorder()
	c := e.NewContext(req, rec)
	c.SetPath("/s/:token/access")
	c.SetParamNames("token")
	c.SetParamValues("invalid")

	if err := h.Access(c); err != nil {
		t.Fatalf("access: %v", err)
	}
	if rec.Code != http.StatusNotFound {
		t.Fatalf("status: got %d", rec.Code)
	}
}
