package notes

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5"
	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/web"
)

func TestMapToNoteResponseIncludesShareMetadata(t *testing.T) {
	response := mapToNoteResponse(NoteResponseFields{
		Permission:    "view",
		SharedByEmail: "owner@example.com",
		SharedByName:  "Owner",
	})

	if response.Permission != "view" {
		t.Fatalf("permission = %q, want %q", response.Permission, "view")
	}
	if response.SharedByEmail != "owner@example.com" {
		t.Fatalf("shared_by_email = %q, want %q", response.SharedByEmail, "owner@example.com")
	}
	if response.SharedByName != "Owner" {
		t.Fatalf("shared_by_name = %q, want %q", response.SharedByName, "Owner")
	}
}

func TestMapToNoteResponseKeepsClearedIconInContract(t *testing.T) {
	payload, err := json.Marshal(mapToNoteResponse(NoteResponseFields{}))
	if err != nil {
		t.Fatalf("marshal response: %v", err)
	}

	var decoded map[string]any
	if err := json.Unmarshal(payload, &decoded); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if value, ok := decoded["note_icon"]; !ok || value != nil {
		t.Fatalf("note_icon = %#v, want explicit null", value)
	}
}

func TestUpdateRejectsInvalidIconPayload(t *testing.T) {
	repo := &mockRepo{
		updateNoteFn: func(_ context.Context, _ sqlcgen.UpdateNoteParams) (sqlcgen.Note, error) {
			t.Fatal("repository should not receive an invalid icon")
			return sqlcgen.Note{}, nil
		},
	}
	recorder := runUpdateRequest(t, NewHandler(NewService(repo, nil)), `{"note_icon":{"kind":"catalog","value":"star"}}`)

	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want %d", recorder.Code, http.StatusBadRequest)
	}
}

func TestUpdateAcceptsExplicitIconClear(t *testing.T) {
	var received sqlcgen.UpdateNoteParams
	repo := &mockRepo{
		updateNoteFn: func(_ context.Context, arg sqlcgen.UpdateNoteParams) (sqlcgen.Note, error) {
			received = arg
			return sqlcgen.Note{ID: arg.ID, UserID: arg.UserID}, nil
		},
	}
	recorder := runUpdateRequest(t, NewHandler(NewService(repo, nil)), `{"note_icon":null}`)

	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", recorder.Code, http.StatusOK)
	}
	if !received.SetNoteIcon.Valid || !received.SetNoteIcon.Bool {
		t.Fatal("explicit null did not request an icon update")
	}
	if len(received.NoteIcon) != 0 {
		t.Fatalf("note icon = %s, want null payload", received.NoteIcon)
	}
}

func TestUpdateMapsPermissionFailureToNotFound(t *testing.T) {
	repo := &mockRepo{
		updateNoteFn: func(_ context.Context, _ sqlcgen.UpdateNoteParams) (sqlcgen.Note, error) {
			return sqlcgen.Note{}, pgx.ErrNoRows
		},
	}
	recorder := runUpdateRequest(t, NewHandler(NewService(repo, nil)), `{"note_icon":{"kind":"emoji","value":"🙂"}}`)

	if recorder.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want %d", recorder.Code, http.StatusNotFound)
	}
}

func runUpdateRequest(t *testing.T, handler *Handler, payload string) *httptest.ResponseRecorder {
	t.Helper()
	e := echo.New()
	req := httptest.NewRequest(
		http.MethodPatch,
		"/notes/00000000-0000-0000-0000-000000000001",
		strings.NewReader(payload),
	)
	req.Header.Set(echo.HeaderContentType, echo.MIMEApplicationJSON)
	recorder := httptest.NewRecorder()
	c := e.NewContext(req, recorder)
	c.SetPath("/notes/:id")
	c.SetParamNames("id")
	c.SetParamValues("00000000-0000-0000-0000-000000000001")
	web.SetUserID(c, "00000000-0000-0000-0000-000000000002")
	if err := handler.Update(c); err != nil {
		t.Fatalf("update: %v", err)
	}
	return recorder
}
