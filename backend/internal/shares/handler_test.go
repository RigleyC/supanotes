package shares

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/go-playground/validator/v10"
	"github.com/jackc/pgx/v5"
	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/web"
)

type testValidator struct {
	v *validator.Validate
}

func (tv *testValidator) Validate(i any) error {
	return tv.v.Struct(i)
}

func newTestServer(t *testing.T, repo *mockRepository) *echo.Echo {
	t.Helper()
	svc := NewService(repo)
	h := NewHandler(svc)

	e := echo.New()
	e.HideBanner = true
	e.Validator = &testValidator{v: validator.New(validator.WithRequiredStructEnabled())}
	protected := e.Group("/api/v1")
	protected.Use(func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			web.SetUserID(c, "00000000-0000-0000-0000-000000000000")
			return next(c)
		}
	})
	protected.POST("/notes/:id/share", h.ShareNote)
	protected.GET("/notes/:id/shares", h.ListNoteShares)
	protected.DELETE("/notes/:id/shares/:user_id", h.DeleteNoteShare)
	return e
}

func do(t *testing.T, e *echo.Echo, method, path, body string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	req.Header.Set(echo.HeaderContentType, echo.MIMEApplicationJSON)
	rec := httptest.NewRecorder()
	e.ServeHTTP(rec, req)
	return rec
}

func TestShareNote_Success(t *testing.T) {
	repo := &mockRepository{
		ownerID: testUUID(),
		user: sqlcgen.User{
			ID:    otherUUID(),
			Email: "friend@example.com",
			Name:  "Friend",
		},
		createdShare: sqlcgen.NoteShare{
			ID:         testUUID(),
			NoteID:     testUUID(),
			UserID:     otherUUID(),
			Permission: "view",
		},
	}
	e := newTestServer(t, repo)
	rec := do(t, e, http.MethodPost, "/api/v1/notes/00000000-0000-0000-0000-000000000000/share",
		`{"email":"friend@example.com","permission":"view"}`)

	if rec.Code != http.StatusCreated {
		t.Fatalf("status: want 201, got %d (body=%s)", rec.Code, rec.Body.String())
	}

	var result ShareResult
	if err := json.Unmarshal(rec.Body.Bytes(), &result); err != nil {
		t.Fatalf("decode: %v (body=%s)", err, rec.Body.String())
	}
	if result.Email != "friend@example.com" {
		t.Errorf("email: want friend@example.com, got %q", result.Email)
	}
	if result.Permission != "view" {
		t.Errorf("permission: want view, got %q", result.Permission)
	}
	var raw map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &raw); err != nil {
		t.Fatalf("decode raw: %v (body=%s)", err, rec.Body.String())
	}
	if _, ok := raw["note_id"]; !ok {
		t.Fatalf("response missing note_id key: %s", rec.Body.String())
	}
	if _, ok := raw["user_id"]; !ok {
		t.Fatalf("response missing user_id key: %s", rec.Body.String())
	}
}

func TestShareNote_InvalidNoteID(t *testing.T) {
	e := newTestServer(t, &mockRepository{})
	rec := do(t, e, http.MethodPost, "/api/v1/notes/invalid/share", `{}`)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status: want 400, got %d (body=%s)", rec.Code, rec.Body.String())
	}
}

func TestShareNote_NoteNotFound(t *testing.T) {
	repo := &mockRepository{ownerErr: pgx.ErrNoRows}
	e := newTestServer(t, repo)
	rec := do(t, e, http.MethodPost, "/api/v1/notes/00000000-0000-0000-0000-000000000000/share",
		`{"email":"friend@example.com","permission":"view"}`)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("status: want 404, got %d (body=%s)", rec.Code, rec.Body.String())
	}
}

func TestShareNote_NotOwner(t *testing.T) {
	repo := &mockRepository{ownerID: otherUUID()}
	e := newTestServer(t, repo)
	rec := do(t, e, http.MethodPost, "/api/v1/notes/00000000-0000-0000-0000-000000000000/share",
		`{"email":"friend@example.com","permission":"view"}`)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("status: want 403, got %d (body=%s)", rec.Code, rec.Body.String())
	}
}

func TestShareNote_UserNotFound(t *testing.T) {
	repo := &mockRepository{
		ownerID: testUUID(),
		userErr: pgx.ErrNoRows,
	}
	e := newTestServer(t, repo)
	rec := do(t, e, http.MethodPost, "/api/v1/notes/00000000-0000-0000-0000-000000000000/share",
		`{"email":"missing@example.com","permission":"view"}`)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("status: want 404, got %d (body=%s)", rec.Code, rec.Body.String())
	}
}

func TestShareNote_SelfShare(t *testing.T) {
	repo := &mockRepository{
		ownerID: testUUID(),
		user: sqlcgen.User{
			ID:    testUUID(),
			Email: "me@example.com",
		},
	}
	e := newTestServer(t, repo)
	rec := do(t, e, http.MethodPost, "/api/v1/notes/00000000-0000-0000-0000-000000000000/share",
		`{"email":"me@example.com","permission":"view"}`)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status: want 400, got %d (body=%s)", rec.Code, rec.Body.String())
	}
}

func TestListNoteShares_Success(t *testing.T) {
	repo := &mockRepository{
		ownerID: testUUID(),
		shares: []sqlcgen.GetNoteSharesRow{
			{
				ID:         testUUID(),
				NoteID:     testUUID(),
				UserID:     otherUUID(),
				Email:      "friend@example.com",
				Name:       "Friend",
				Permission: "view",
			},
		},
	}
	e := newTestServer(t, repo)
	rec := do(t, e, http.MethodGet, "/api/v1/notes/00000000-0000-0000-0000-000000000000/shares", "")

	if rec.Code != http.StatusOK {
		t.Fatalf("status: want 200, got %d (body=%s)", rec.Code, rec.Body.String())
	}

	var shares []ShareResult
	if err := json.Unmarshal(rec.Body.Bytes(), &shares); err != nil {
		t.Fatalf("decode: %v (body=%s)", err, rec.Body.String())
	}
	if len(shares) != 1 {
		t.Fatalf("len: want 1, got %d", len(shares))
	}
	if shares[0].Email != "friend@example.com" {
		t.Errorf("email: want friend@example.com, got %q", shares[0].Email)
	}
}

func TestListNoteShares_NotOwner(t *testing.T) {
	repo := &mockRepository{ownerID: otherUUID()}
	e := newTestServer(t, repo)
	rec := do(t, e, http.MethodGet, "/api/v1/notes/00000000-0000-0000-0000-000000000000/shares", "")

	if rec.Code != http.StatusForbidden {
		t.Fatalf("status: want 403, got %d (body=%s)", rec.Code, rec.Body.String())
	}
}

func TestDeleteNoteShare_Success(t *testing.T) {
	repo := &mockRepository{ownerID: testUUID()}
	e := newTestServer(t, repo)
	rec := do(t, e, http.MethodDelete,
		"/api/v1/notes/00000000-0000-0000-0000-000000000000/shares/00000000-0000-0000-0000-000000000001", "")

	if rec.Code != http.StatusNoContent {
		t.Fatalf("status: want 204, got %d (body=%s)", rec.Code, rec.Body.String())
	}
}

func TestDeleteNoteShare_InvalidUserID(t *testing.T) {
	e := newTestServer(t, &mockRepository{})
	rec := do(t, e, http.MethodDelete,
		"/api/v1/notes/00000000-0000-0000-0000-000000000000/shares/not-a-uuid", "")

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status: want 400, got %d (body=%s)", rec.Code, rec.Body.String())
	}
}

func TestDeleteNoteShare_NotOwner(t *testing.T) {
	repo := &mockRepository{ownerID: otherUUID()}
	e := newTestServer(t, repo)
	rec := do(t, e, http.MethodDelete,
		"/api/v1/notes/00000000-0000-0000-0000-000000000000/shares/00000000-0000-0000-0000-000000000001", "")

	if rec.Code != http.StatusForbidden {
		t.Fatalf("status: want 403, got %d (body=%s)", rec.Code, rec.Body.String())
	}
}
