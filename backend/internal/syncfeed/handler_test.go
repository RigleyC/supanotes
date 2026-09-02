package syncfeed

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/web"
)

type fakeChangeReader struct {
	userID pgtype.UUID
	after  int64
	limit  int
	page   Page
}

func (f *fakeChangeReader) ListChanges(_ context.Context, userID pgtype.UUID, after int64, limit int) (Page, error) {
	f.userID = userID
	f.after = after
	f.limit = limit
	return f.page, nil
}

func TestListChangesUsesAuthenticatedActorAndCursor(t *testing.T) {
	reader := &fakeChangeReader{page: Page{
		Cursor:    43,
		Watermark: 51,
		HasMore:   true,
		Changes: []Change{{
			Sequence: 43,
			Type: "note_changed",
			NoteID: "00000000-0000-0000-0000-000000000010",
			Revision: 7,
			CreatedAt: time.Date(2026, 9, 1, 20, 0, 0, 0, time.UTC),
		}},
	}}
	e := echo.New()
	req := httptest.NewRequest(http.MethodGet, "/sync/changes?after=41&limit=50", nil)
	rec := httptest.NewRecorder()
	c := e.NewContext(req, rec)
	web.SetUserID(c, "00000000-0000-0000-0000-000000000002")

	if err := NewHandler(reader).ListChanges(c); err != nil {
		t.Fatalf("list changes: %v", err)
	}
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusOK)
	}
	if reader.after != 41 || reader.limit != 50 {
		t.Fatalf("reader args = after %d limit %d", reader.after, reader.limit)
	}
	if !reader.userID.Valid || reader.userID.Bytes[15] != 2 {
		t.Fatalf("wrong actor: %+v", reader.userID)
	}

	var payload struct {
		Cursor    int64    `json:"cursor"`
		Watermark int64    `json:"watermark"`
		HasMore   bool     `json:"hasMore"`
		Changes   []Change `json:"changes"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if payload.Cursor != 43 || payload.Watermark != 51 || !payload.HasMore || len(payload.Changes) != 1 {
		t.Fatalf("response = %+v", payload)
	}
}

func TestListChangesRejectsInvalidCursor(t *testing.T) {
	reader := &fakeChangeReader{}
	e := echo.New()
	req := httptest.NewRequest(http.MethodGet, "/sync/changes?after=-1", nil)
	rec := httptest.NewRecorder()
	c := e.NewContext(req, rec)
	web.SetUserID(c, "00000000-0000-0000-0000-000000000002")

	if err := NewHandler(reader).ListChanges(c); err != nil {
		t.Fatalf("list changes: %v", err)
	}
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusBadRequest)
	}
}
