package handler

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/labstack/echo/v4"
)

func TestHealth(t *testing.T) {
	e := echo.New()
	req := httptest.NewRequest(http.MethodGet, "/api/v1/health", nil)
	rec := httptest.NewRecorder()
	c := e.NewContext(req, rec)

	if err := Health(nil)(c); err != nil {
		t.Fatalf("Health() returned error: %v", err)
	}

	if rec.Code != http.StatusOK {
		t.Errorf("status: want %d, got %d", http.StatusOK, rec.Code)
	}

	ct := rec.Header().Get("Content-Type")
	if ct == "" || ct[:16] != "application/json" {
		t.Errorf("Content-Type: want application/json..., got %q", ct)
	}

	var body map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("body is not valid JSON: %v (raw: %q)", err, rec.Body.String())
	}
	if body["status"] != "ok" {
		t.Errorf("body.status: want ok, got %q", body["status"])
	}
}
