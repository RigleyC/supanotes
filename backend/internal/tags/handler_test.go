package tags

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/go-playground/validator/v10"
	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/web"
)

type testValidator struct {
	v *validator.Validate
}

func (tv *testValidator) Validate(i any) error {
	return tv.v.Struct(i)
}

func newTestServer(t *testing.T) (*echo.Echo, *mockQuerier) {
	t.Helper()
	q := newMockQuerier()
	svc := NewService(q)
	h := NewHandler(svc)

	e := echo.New()
	e.HideBanner = true
	e.Validator = &testValidator{v: validator.New(validator.WithRequiredStructEnabled())}
	protected := e.Group("/api/v1")
	protected.Use(func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			web.SetUserID(c, "00000000-0000-0000-0000-000000000001")
			return next(c)
		}
	})
	protected.DELETE("/tags/:id", h.Delete)
	protected.GET("/tags", h.List)
	protected.POST("/tags", h.Create)
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

func TestHandler_DeleteTag_Success(t *testing.T) {
	e, _ := newTestServer(t)
	rec := do(t, e, http.MethodDelete, "/api/v1/tags/00000000-0000-0000-0000-000000000001", "")
	if rec.Code != http.StatusNoContent {
		t.Fatalf("status: want 204, got %d", rec.Code)
	}
}

func TestHandler_DeleteTag_InvalidID(t *testing.T) {
	e, _ := newTestServer(t)
	rec := do(t, e, http.MethodDelete, "/api/v1/tags/not-a-uuid", "")
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status: want 400, got %d", rec.Code)
	}
}

