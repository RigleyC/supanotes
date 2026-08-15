package notes

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
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

func TestUpdateAcceptsColoredCatalogIcon(t *testing.T) {
	var received sqlcgen.UpdateNoteParams
	repo := &mockRepo{
		updateNoteFn: func(_ context.Context, arg sqlcgen.UpdateNoteParams) (sqlcgen.Note, error) {
			received = arg
			return sqlcgen.Note{ID: arg.ID, UserID: arg.UserID}, nil
		},
	}
	recorder := runUpdateRequest(t, NewHandler(NewService(repo, nil)), `{"note_icon":{"kind":"catalog","value":"star","color_key":"blue"}}`)

	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", recorder.Code, http.StatusOK)
	}
	if string(received.NoteIcon) != `{"kind":"catalog","value":"star","color_key":"blue"}` {
		t.Fatalf("note icon = %s, want catalog payload", received.NoteIcon)
	}
}

func TestUpdateMapsStaleVersionToConflict(t *testing.T) {
	repo := &mockRepo{
		getNoteByIDFn: func(_ context.Context, id pgtype.UUID, userID pgtype.UUID) (sqlcgen.GetNoteByIDRow, error) {
			return sqlcgen.GetNoteByIDRow{ID: id, UserID: userID}, nil
		},
		updateNoteFn: func(_ context.Context, _ sqlcgen.UpdateNoteParams) (sqlcgen.Note, error) {
			return sqlcgen.Note{}, pgx.ErrNoRows
		},
	}
	recorder := runUpdateRequest(t, NewHandler(NewService(repo, nil)), `{"note_icon":null,"expected_updated_at":"2026-07-31T12:01:00Z"}`)

	if recorder.Code != http.StatusConflict {
		t.Fatalf("status = %d, want %d", recorder.Code, http.StatusConflict)
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

func runUpdatePreferencesRequest(t *testing.T, handler *Handler, id string, userID string, payload string) *httptest.ResponseRecorder {
	t.Helper()
	e := echo.New()
	req := httptest.NewRequest(
		http.MethodPatch,
		"/notes/"+id+"/preferences",
		strings.NewReader(payload),
	)
	req.Header.Set(echo.HeaderContentType, echo.MIMEApplicationJSON)
	recorder := httptest.NewRecorder()
	c := e.NewContext(req, recorder)
	c.SetPath("/notes/:id/preferences")
	c.SetParamNames("id")
	c.SetParamValues(id)
	web.SetUserID(c, userID)
	if err := handler.UpdatePreferences(c); err != nil {
		t.Fatalf("update preferences: %v", err)
	}
	return recorder
}

func decodePreferencesResponse(t *testing.T, body string) NotePreferencesResponse {
	t.Helper()
	var resp NotePreferencesResponse
	if err := json.Unmarshal([]byte(body), &resp); err != nil {
		t.Fatalf("decode preference response: %v", err)
	}
	return resp
}

func TestUpdatePreferencesAcceptedForOwner(t *testing.T) {
	var received sqlcgen.UpsertUserNotePreferenceParams
	repo := &mockRepo{
		getNoteByIDFn: func(_ context.Context, id pgtype.UUID, userID pgtype.UUID) (sqlcgen.GetNoteByIDRow, error) {
			return sqlcgen.GetNoteByIDRow{ID: id, UserID: userID}, nil
		},
		upsertUserNotePreferenceFn: func(_ context.Context, arg sqlcgen.UpsertUserNotePreferenceParams) (sqlcgen.UserNotePreference, error) {
			received = arg
			return sqlcgen.UserNotePreference{
				UserID: arg.UserID, NoteID: arg.NoteID,
				Favorite: arg.Favorite, Archived: arg.Archived,
				HideCompleted: arg.HideCompleted, CollapseImages: arg.CollapseImages,
				UpdatedAt: pgtype.Timestamptz{Time: time.Now(), Valid: true},
			}, nil
		},
	}
	recorder := runUpdatePreferencesRequest(
		t,
		NewHandler(NewService(repo, nil)),
		"00000000-0000-0000-0000-000000000001",
		"00000000-0000-0000-0000-000000000002",
		`{"favorite":true,"archived":false,"hide_completed":true,"collapse_images":false}`,
	)

	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", recorder.Code, http.StatusOK)
	}
	if repo.updateNotesCalls != 0 {
		t.Fatal("note update was invoked for a preference change")
	}
	if !received.Favorite || received.Archived || !received.HideCompleted || received.CollapseImages {
		t.Fatalf("upsert params = %+v, want favorite/archived/hide_completed/collapse_images of true/false/true/false", received)
	}

	resp := decodePreferencesResponse(t, recorder.Body.String())
	if !resp.Favorite || resp.Archived || !resp.HideCompleted || resp.CollapseImages {
		t.Fatalf("response = %+v, want all four fields", resp)
	}
	if resp.UpdatedAt == "" {
		t.Fatal("response is missing updated_at")
	}
}

func TestUpdatePreferencesAcceptedForSharedReadOnly(t *testing.T) {
	repo := &mockRepo{
		getNoteByIDFn: func(_ context.Context, id pgtype.UUID, userID pgtype.UUID) (sqlcgen.GetNoteByIDRow, error) {
			return sqlcgen.GetNoteByIDRow{ID: id, UserID: userID, Permission: "view"}, nil
		},
		upsertUserNotePreferenceFn: func(_ context.Context, arg sqlcgen.UpsertUserNotePreferenceParams) (sqlcgen.UserNotePreference, error) {
			return sqlcgen.UserNotePreference{
				UserID: arg.UserID, NoteID: arg.NoteID,
				Favorite: arg.Favorite, Archived: arg.Archived,
				HideCompleted: arg.HideCompleted, CollapseImages: arg.CollapseImages,
			}, nil
		},
	}
	recorder := runUpdatePreferencesRequest(
		t,
		NewHandler(NewService(repo, nil)),
		"00000000-0000-0000-0000-000000000001",
		"00000000-0000-0000-0000-000000000003",
		`{"favorite":false,"archived":true,"hide_completed":false,"collapse_images":true}`,
	)

	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", recorder.Code, http.StatusOK)
	}
}

func TestUpdatePreferencesRejectsInaccessibleUser(t *testing.T) {
	repo := &mockRepo{
		getNoteByIDFn: func(_ context.Context, _ pgtype.UUID, _ pgtype.UUID) (sqlcgen.GetNoteByIDRow, error) {
			return sqlcgen.GetNoteByIDRow{}, pgx.ErrNoRows
		},
	}
	recorder := runUpdatePreferencesRequest(
		t,
		NewHandler(NewService(repo, nil)),
		"00000000-0000-0000-0000-000000000001",
		"00000000-0000-0000-0000-000000000004",
		`{"favorite":true,"archived":false,"hide_completed":false,"collapse_images":false}`,
	)

	if recorder.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want %d", recorder.Code, http.StatusNotFound)
	}
	if repo.updatePreferencesCalls != 0 {
		t.Fatal("preference upsert ran even though access was rejected")
	}
}

func TestUpdatePreferencesRejectsMissingFields(t *testing.T) {
	repo := &mockRepo{}
	recorder := runUpdatePreferencesRequest(
		t,
		NewHandler(NewService(repo, nil)),
		"00000000-0000-0000-0000-000000000001",
		"00000000-0000-0000-0000-000000000002",
		`{}`,
	)

	if recorder.Code == http.StatusOK {
		t.Fatal("accepted empty preference payload; full row is required")
	}
	if repo.updatePreferencesCalls != 0 {
		t.Fatal("preference upsert ran for a rejected payload")
	}
}
