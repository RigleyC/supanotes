package tasks

import (
	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/web"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/labstack/echo/v4"
	"net/http/httptest"
	"testing"
)

func TestHandlerNeverLeaksOtherOwnerTask(t *testing.T) {
	id := pgtype.UUID{Bytes: [16]byte{0x77}, Valid: true}
	f := &fakeRepo{task: sqlcgen.Task{ID: id, OwnerUserID: id, Title: "secret"}}
	h := NewHandler(NewService(f))
	e := echo.New()
	req := httptest.NewRequest("GET", "/tasks/77777777-7777-4777-8777-777777777777", nil)
	rec := httptest.NewRecorder()
	c := e.NewContext(req, rec)
	c.SetPath("/tasks/:id")
	c.SetParamNames("id")
	c.SetParamValues("77777777-7777-4777-8777-777777777777")
	web.SetUserID(c, "88888888-8888-4888-8888-888888888888")
	if err := h.Get(c); err != nil {
		t.Fatal(err)
	}
	if rec.Code != 404 {
		t.Fatalf("status=%d body=%s", rec.Code, rec.Body.String())
	}
}
