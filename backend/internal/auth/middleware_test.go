package auth

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/labstack/echo/v4"

	authpkg "github.com/RigleyC/supanotes/pkg/auth"
	"github.com/RigleyC/supanotes/pkg/config"
)

func newProtectedRoute(t *testing.T) (*echo.Echo, *config.Config) {
	t.Helper()
	cfg := testConfig()
	e := echo.New()
	e.HideBanner = true
	g := e.Group("/api/v1")
	g.Use(JWT(cfg))
	g.GET("/me", func(c echo.Context) error {
		uid, ok := UserIDFromContext(c)
		if !ok {
			return jsonError(c, http.StatusInternalServerError, "no user id in context")
		}
		return c.JSON(http.StatusOK, map[string]string{"user_id": uid})
	})
	return e, cfg
}

func TestMiddleware_MissingHeader(t *testing.T) {
	e, _ := newProtectedRoute(t)
	req := httptest.NewRequest(http.MethodGet, "/api/v1/me", nil)
	rec := httptest.NewRecorder()
	e.ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status: want 401, got %d", rec.Code)
	}
}

func TestMiddleware_WrongScheme(t *testing.T) {
	e, _ := newProtectedRoute(t)
	req := httptest.NewRequest(http.MethodGet, "/api/v1/me", nil)
	req.Header.Set(echo.HeaderAuthorization, "Basic abc123")
	rec := httptest.NewRecorder()
	e.ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status: want 401, got %d", rec.Code)
	}
}

func TestMiddleware_EmptyToken(t *testing.T) {
	e, _ := newProtectedRoute(t)
	req := httptest.NewRequest(http.MethodGet, "/api/v1/me", nil)
	req.Header.Set(echo.HeaderAuthorization, "Bearer   ")
	rec := httptest.NewRecorder()
	e.ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status: want 401, got %d", rec.Code)
	}
}

func TestMiddleware_InvalidToken(t *testing.T) {
	e, _ := newProtectedRoute(t)
	req := httptest.NewRequest(http.MethodGet, "/api/v1/me", nil)
	req.Header.Set(echo.HeaderAuthorization, "Bearer not.a.real.jwt")
	rec := httptest.NewRecorder()
	e.ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status: want 401, got %d (body=%s)", rec.Code, rec.Body.String())
	}
}

func TestMiddleware_WrongSecret(t *testing.T) {
	e, cfg := newProtectedRoute(t)
	tok, err := authpkg.GenerateAccessToken("user-123", "different-secret-at-least-32-characters", time.Minute)
	if err != nil {
		t.Fatalf("GenerateAccessToken: %v", err)
	}
	req := httptest.NewRequest(http.MethodGet, "/api/v1/me", nil)
	req.Header.Set(echo.HeaderAuthorization, "Bearer "+tok)
	rec := httptest.NewRecorder()
	e.ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status: want 401, got %d (body=%s)", rec.Code, rec.Body.String())
	}
	_ = cfg
}

func TestMiddleware_HappyPath(t *testing.T) {
	e, cfg := newProtectedRoute(t)
	const uid = "11111111-1111-1111-1111-111111111111"
	tok, err := authpkg.GenerateAccessToken(uid, cfg.JWTSecret, time.Minute)
	if err != nil {
		t.Fatalf("GenerateAccessToken: %v", err)
	}

	req := httptest.NewRequest(http.MethodGet, "/api/v1/me", nil)
	req.Header.Set(echo.HeaderAuthorization, "Bearer "+tok)
	rec := httptest.NewRecorder()
	e.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status: want 200, got %d (body=%s)", rec.Code, rec.Body.String())
	}
	var body map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("body not JSON: %v", err)
	}
	if body["user_id"] != uid {
		t.Errorf("user_id: want %q, got %q", uid, body["user_id"])
	}
}

func TestMiddleware_ExpiredToken(t *testing.T) {
	e, cfg := newProtectedRoute(t)
	tok, err := authpkg.GenerateAccessToken("u", cfg.JWTSecret, -time.Minute)
	if err != nil {
		t.Fatalf("GenerateAccessToken: %v", err)
	}
	req := httptest.NewRequest(http.MethodGet, "/api/v1/me", nil)
	req.Header.Set(echo.HeaderAuthorization, "Bearer "+tok)
	rec := httptest.NewRecorder()
	e.ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status: want 401, got %d", rec.Code)
	}
}

func TestUserIDFromContext_Missing(t *testing.T) {
	e := echo.New()
	c := e.NewContext(nil, nil)
	if _, ok := UserIDFromContext(c); ok {
		t.Error("UserIDFromContext: want ok=false for empty context")
	}
}
