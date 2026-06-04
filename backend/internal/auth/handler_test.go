package auth

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/pkg/auth"
)

type httpCase struct {
	name       string
	body       string
	wantStatus int
	wantErr    string
	checkBody  func(t *testing.T, body []byte)
}

func newTestServer(t *testing.T) (*echo.Echo, *mockQuerier) {
	t.Helper()
	q := newMockQuerier()
	svc := NewService(q, testConfig())
	h := NewHandler(svc)

	e := echo.New()
	e.HideBanner = true
	v1 := e.Group("/api/v1")
	v1.POST("/auth/register", h.Register)
	v1.POST("/auth/login", h.Login)
	v1.POST("/auth/refresh", h.Refresh)
	v1.POST("/auth/logout", h.Logout)
	return e, q
}

func do(t *testing.T, e *echo.Echo, method, path, body string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	req.Header.Set(echo.HeaderContentType, echo.MIMEApplicationJSON)
	rec := httptest.NewRecorder()
	e.ServeHTTP(rec, req)
	return rec
}

func decode[T any](t *testing.T, body []byte) T {
	t.Helper()
	var v T
	if err := json.Unmarshal(body, &v); err != nil {
		t.Fatalf("decode: %v (body=%s)", err, body)
	}
	return v
}

func TestHandler_Register_Success(t *testing.T) {
	e, _ := newTestServer(t)
	rec := do(t, e, http.MethodPost, "/api/v1/auth/register",
		`{"email":"alice@example.com","password":"correct-horse","name":"Alice"}`)

	if rec.Code != http.StatusCreated {
		t.Fatalf("status: want 201, got %d (body=%s)", rec.Code, rec.Body.String())
	}

	var resp AuthResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v (body=%s)", err, rec.Body.String())
	}
	if resp.AccessToken == "" {
		t.Error("access_token empty")
	}
	if len(resp.RefreshToken) != 64 {
		t.Errorf("refresh_token: want 64 chars, got %d", len(resp.RefreshToken))
	}
	if resp.User == nil {
		t.Fatal("user is nil")
	}
	if resp.User.Email != "alice@example.com" {
		t.Errorf("user.email: %q", resp.User.Email)
	}
}

func TestHandler_Register_DuplicateEmail(t *testing.T) {
	e, _ := newTestServer(t)
	body := `{"email":"dup@example.com","password":"correct-horse","name":"X"}`
	_ = do(t, e, http.MethodPost, "/api/v1/auth/register", body)
	rec := do(t, e, http.MethodPost, "/api/v1/auth/register", body)

	if rec.Code != http.StatusConflict {
		t.Fatalf("status: want 409, got %d", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), `"error"`) {
		t.Errorf("body missing error key: %s", rec.Body.String())
	}
}

func TestHandler_Register_Validation(t *testing.T) {
	cases := []struct {
		name string
		body string
	}{
		{"empty body", `{}`},
		{"bad email", `{"email":"not-an-email","password":"correct-horse","name":"X"}`},
		{"short password", `{"email":"a@b.com","password":"short","name":"X"}`},
		{"empty name", `{"email":"a@b.com","password":"correct-horse","name":""}`},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			e, _ := newTestServer(t)
			rec := do(t, e, http.MethodPost, "/api/v1/auth/register", tc.body)
			if rec.Code != http.StatusBadRequest {
				t.Errorf("status: want 400, got %d (body=%s)", rec.Code, rec.Body.String())
			}
		})
	}
}

func TestHandler_Register_BadJSON(t *testing.T) {
	e, _ := newTestServer(t)
	rec := do(t, e, http.MethodPost, "/api/v1/auth/register", `{not-json`)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("status: want 400, got %d", rec.Code)
	}
}

func TestHandler_Login_Success(t *testing.T) {
	e, _ := newTestServer(t)
	_ = do(t, e, http.MethodPost, "/api/v1/auth/register",
		`{"email":"login@example.com","password":"correct-horse","name":"L"}`)

	rec := do(t, e, http.MethodPost, "/api/v1/auth/login",
		`{"email":"login@example.com","password":"correct-horse"}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("status: want 200, got %d (body=%s)", rec.Code, rec.Body.String())
	}
	var resp AuthResponse
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	if resp.User == nil {
		t.Error("user nil on login")
	}
}

func TestHandler_Login_InvalidCredentials(t *testing.T) {
	e, _ := newTestServer(t)
	_ = do(t, e, http.MethodPost, "/api/v1/auth/register",
		`{"email":"x@example.com","password":"correct-horse","name":"X"}`)

	rec := do(t, e, http.MethodPost, "/api/v1/auth/login",
		`{"email":"x@example.com","password":"wrong"}`)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status: want 401, got %d (body=%s)", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "invalid credentials") {
		t.Errorf("body: %s", rec.Body.String())
	}
}

func TestHandler_Refresh_Success(t *testing.T) {
	e, q := newTestServer(t)
	rec := do(t, e, http.MethodPost, "/api/v1/auth/register",
		`{"email":"r@example.com","password":"correct-horse","name":"R"}`)

	var reg AuthResponse
	_ = json.Unmarshal(rec.Body.Bytes(), &reg)

	rec2 := do(t, e, http.MethodPost, "/api/v1/auth/refresh",
		`{"refresh_token":"`+reg.RefreshToken+`"}`)
	if rec2.Code != http.StatusOK {
		t.Fatalf("status: want 200, got %d (body=%s)", rec2.Code, rec2.Body.String())
	}
	var ref RefreshResponse
	_ = json.Unmarshal(rec2.Body.Bytes(), &ref)
	if ref.AccessToken == "" || ref.RefreshToken == "" {
		t.Error("empty tokens on refresh")
	}
	if ref.RefreshToken == reg.RefreshToken {
		t.Error("refresh did not rotate token")
	}
	_ = q
}

func TestHandler_Refresh_Invalid(t *testing.T) {
	e, _ := newTestServer(t)
	rec := do(t, e, http.MethodPost, "/api/v1/auth/refresh",
		`{"refresh_token":"not-a-real-token"}`)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status: want 401, got %d", rec.Code)
	}
}

func TestHandler_Refresh_MissingToken(t *testing.T) {
	e, _ := newTestServer(t)
	rec := do(t, e, http.MethodPost, "/api/v1/auth/refresh", `{}`)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("status: want 400, got %d", rec.Code)
	}
}

func TestHandler_Logout_Success(t *testing.T) {
	e, _ := newTestServer(t)
	rec := do(t, e, http.MethodPost, "/api/v1/auth/register",
		`{"email":"lo@example.com","password":"correct-horse","name":"L"}`)
	var reg AuthResponse
	_ = json.Unmarshal(rec.Body.Bytes(), &reg)

	rec2 := do(t, e, http.MethodPost, "/api/v1/auth/logout",
		`{"refresh_token":"`+reg.RefreshToken+`"}`)
	if rec2.Code != http.StatusNoContent {
		t.Fatalf("status: want 204, got %d (body=%s)", rec2.Code, rec2.Body.String())
	}

	rec3 := do(t, e, http.MethodPost, "/api/v1/auth/refresh",
		`{"refresh_token":"`+reg.RefreshToken+`"}`)
	if rec3.Code != http.StatusUnauthorized {
		t.Errorf("post-logout refresh: want 401, got %d", rec3.Code)
	}
}

func TestHandler_Logout_UnknownTokenIsNoop(t *testing.T) {
	e, _ := newTestServer(t)
	rec := do(t, e, http.MethodPost, "/api/v1/auth/logout",
		`{"refresh_token":"definitely-not-real"}`)
	if rec.Code != http.StatusNoContent {
		t.Errorf("status: want 204, got %d", rec.Code)
	}
}

func TestHandler_Login_Validation(t *testing.T) {
	e, _ := newTestServer(t)
	cases := []string{
		`{}`,
		`{"email":"not-an-email","password":"x"}`,
		`{"email":"a@b.com","password":""}`,
	}
	for i, body := range cases {
		rec := do(t, e, http.MethodPost, "/api/v1/auth/login", body)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("case %d: want 400, got %d (body=%s)", i, rec.Code, rec.Body.String())
		}
	}
}

func TestHandler_ErrorResponse_Shape(t *testing.T) {
	e, _ := newTestServer(t)
	rec := do(t, e, http.MethodPost, "/api/v1/auth/register", `{not-json`)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status: want 400, got %d", rec.Code)
	}
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("body not JSON: %v", err)
	}
	if _, ok := body["error"]; !ok {
		t.Errorf("error key missing: %v", body)
	}
	if _, ok := body["access_token"]; ok {
		t.Error("leaked token in error body")
	}
}

func TestRefreshToken_HashFormat(t *testing.T) {
	plain, hash, err := auth.GenerateRefreshToken()
	if err != nil {
		t.Fatalf("GenerateRefreshToken: %v", err)
	}
	if len(plain) != 64 {
		t.Errorf("plain: want 64 hex chars, got %d", len(plain))
	}
	if len(hash) != 64 {
		t.Errorf("hash: want 64 hex chars, got %d", len(hash))
	}
	if auth.HashRefreshToken(plain) != hash {
		t.Error("HashRefreshToken inconsistent with GenerateRefreshToken")
	}
}
