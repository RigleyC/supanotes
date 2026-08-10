package attachments

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/pkg/uid"
)

func TestPublicDownloadStreamsTheAuthorizedPrivateObject(t *testing.T) {
	noteID := testUUID(1)
	attachmentID := testUUID(2)
	repo := &fakeAttachmentRepo{attachment: sqlcgen.Attachment{
		ID:         attachmentID,
		NoteID:     noteID,
		Filename:   "note.txt",
		StorageKey: "attachments/note/note.txt",
		MimeType:   "text/plain",
	}}
	h := NewPublicHandler(repo, &fakeStorage{}, func(context.Context, string) (pgtype.UUID, error) {
		return noteID, nil
	})
	e := echo.New()
	attachmentPath := uid.UUIDToString(attachmentID)
	req := httptest.NewRequest(http.MethodGet, "/api/v1/s/token/attachments/"+attachmentPath, nil)
	rec := httptest.NewRecorder()
	c := e.NewContext(req, rec)
	c.SetPath("/api/v1/s/:token/attachments/:attachment_id")
	c.SetParamNames("token", "attachment_id")
	c.SetParamValues("token", attachmentPath)

	if err := h.Download(c); err != nil {
		t.Fatalf("download: %v", err)
	}
	if rec.Code != http.StatusOK || rec.Body.String() != "attachment" {
		t.Fatalf("response: status=%d body=%q", rec.Code, rec.Body.String())
	}
	if rec.Header().Get("Cache-Control") != "no-store" {
		t.Fatalf("cache-control: %q", rec.Header().Get("Cache-Control"))
	}
}

func TestPublicDownloadReturnsJSONForRevokedLinks(t *testing.T) {
	h := NewPublicHandler(&fakeAttachmentRepo{}, &fakeStorage{}, func(context.Context, string) (pgtype.UUID, error) {
		return pgtype.UUID{}, ErrPublicLinkNotFound
	})
	e := echo.New()
	req := httptest.NewRequest(http.MethodGet, "/api/v1/s/token/attachments/invalid", nil)
	rec := httptest.NewRecorder()
	c := e.NewContext(req, rec)
	c.SetPath("/api/v1/s/:token/attachments/:attachment_id")
	c.SetParamNames("token", "attachment_id")
	c.SetParamValues("token", "invalid")

	if err := h.Download(c); err != nil {
		t.Fatalf("download: %v", err)
	}
	if rec.Code != http.StatusNotFound || !strings.Contains(rec.Body.String(), `"error":"share link not found"`) {
		t.Fatalf("response: status=%d body=%q", rec.Code, rec.Body.String())
	}
}

func TestPublicDownloadReturnsJSONForStorageFailure(t *testing.T) {
	noteID := testUUID(1)
	attachmentID := testUUID(2)
	repo := &fakeAttachmentRepo{attachment: sqlcgen.Attachment{
		ID:         attachmentID,
		NoteID:     noteID,
		StorageKey: "attachments/note/note.txt",
		MimeType:   "text/plain",
	}}
	h := NewPublicHandler(repo, &fakeStorage{openErr: errors.New("storage unavailable")}, func(context.Context, string) (pgtype.UUID, error) {
		return noteID, nil
	})
	e := echo.New()
	attachmentPath := uid.UUIDToString(attachmentID)
	req := httptest.NewRequest(http.MethodGet, "/api/v1/s/token/attachments/"+attachmentPath, nil)
	rec := httptest.NewRecorder()
	c := e.NewContext(req, rec)
	c.SetPath("/api/v1/s/:token/attachments/:attachment_id")
	c.SetParamNames("token", "attachment_id")
	c.SetParamValues("token", attachmentPath)

	if err := h.Download(c); err != nil {
		t.Fatalf("download: %v", err)
	}
	if rec.Code != http.StatusInternalServerError || !strings.Contains(rec.Body.String(), `"error":"Internal server error"`) {
		t.Fatalf("response: status=%d body=%q", rec.Code, rec.Body.String())
	}
}
