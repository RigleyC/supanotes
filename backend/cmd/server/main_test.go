package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/pkg/config"
)

func TestRegisterRoutesDoesNotExposeGoroutineDebugInProduction(t *testing.T) {
	e := echo.New()
	registerRoutes(e, &config.Config{Environment: "production"}, nil, context.Background())

	recorder := httptest.NewRecorder()
	e.ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, "/debug/goroutine", nil))

	if recorder.Code != http.StatusNotFound {
		t.Fatalf("production debug endpoint status = %d, want %d", recorder.Code, http.StatusNotFound)
	}
}

func TestRegisterRoutesExposesGoroutineDebugOnlyWhenExplicitlyEnabledInDev(t *testing.T) {
	e := echo.New()
	registerRoutes(e, &config.Config{Environment: "dev", EnableDebugEndpoints: true}, nil, context.Background())

	recorder := httptest.NewRecorder()
	e.ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, "/debug/goroutine", nil))

	if recorder.Code != http.StatusOK {
		t.Fatalf("explicit dev debug endpoint status = %d, want %d", recorder.Code, http.StatusOK)
	}
}
