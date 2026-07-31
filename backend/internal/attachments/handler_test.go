package attachments

import (
	"bytes"
	"context"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/labstack/echo/v4"
	"github.com/stretchr/testify/require"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/web"
)

func TestUploadHandlerPassesAuthenticatedUserToService(t *testing.T) {
	t.Parallel()

	svc := &fakeUploadService{
		attachment: sqlcgen.Attachment{
			ID:        testUUID(3),
			NoteID:    testUUID(1),
			Filename:  "file.txt",
			Url:       "https://cdn.example.com/file.txt",
			MimeType:  "text/plain; charset=utf-8",
			SizeBytes: 5,
			CreatedAt: pgtype.Timestamptz{
				Time:  time.Unix(0, 0).UTC(),
				Valid: true,
			},
		},
	}
	rec := runUploadRequest(t, svc, "00000000-0000-0000-0000-000000000002", "hello")

	require.Equal(t, http.StatusCreated, rec.Code, rec.Body.String())
	require.Equal(t, testUUID(1), svc.noteID)
	require.Equal(t, testUUID(2), svc.userID)
	require.Equal(t, "file.txt", svc.filename)
	require.Equal(t, int64(5), svc.size)
}

func TestUploadHandlerMapsPermissionAndNotFoundErrors(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name       string
		err        error
		wantStatus int
	}{
		{name: "forbidden", err: ErrNoPermission, wantStatus: http.StatusForbidden},
		{name: "not-found", err: ErrNoteNotFound, wantStatus: http.StatusNotFound},
		{name: "too-large", err: ErrFileTooLarge, wantStatus: http.StatusRequestEntityTooLarge},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			rec := runUploadRequest(t, &fakeUploadService{err: tc.err}, "00000000-0000-0000-0000-000000000002", "hello")

			require.Equal(t, tc.wantStatus, rec.Code, rec.Body.String())
		})
	}
}

func runUploadRequest(t *testing.T, svc Service, userID string, body string) *httptest.ResponseRecorder {
	t.Helper()

	e := echo.New()
	h := NewHandler(svc)

	var payload bytes.Buffer
	writer := multipart.NewWriter(&payload)
	require.NoError(t, writer.WriteField("note_id", "00000000-0000-0000-0000-000000000001"))
	fileWriter, err := writer.CreateFormFile("file", "file.txt")
	require.NoError(t, err)
	_, err = fileWriter.Write([]byte(body))
	require.NoError(t, err)
	require.NoError(t, writer.Close())

	req := httptest.NewRequest(http.MethodPost, "/attachments/upload", &payload)
	req.Header.Set(echo.HeaderContentType, writer.FormDataContentType())
	rec := httptest.NewRecorder()
	c := e.NewContext(req, rec)
	web.SetUserID(c, userID)

	require.NoError(t, h.Upload(c))
	return rec
}

type fakeUploadService struct {
	attachment sqlcgen.Attachment
	err        error
	noteID     pgtype.UUID
	userID     pgtype.UUID
	filename   string
	size       int64
}

func (s *fakeUploadService) Upload(_ context.Context, noteID pgtype.UUID, userID pgtype.UUID, filename string, _ io.Reader, size int64) (sqlcgen.Attachment, error) {
	s.noteID = noteID
	s.userID = userID
	s.filename = filename
	s.size = size
	if s.err != nil {
		return sqlcgen.Attachment{}, s.err
	}
	return s.attachment, nil
}

func (s *fakeUploadService) ListByNote(context.Context, pgtype.UUID) ([]sqlcgen.Attachment, error) {
	return nil, nil
}

func (s *fakeUploadService) Delete(context.Context, pgtype.UUID, pgtype.UUID) error {
	return nil
}

func (s *fakeUploadService) Metrics() Metrics {
	if s.err == nil {
		return Metrics{}
	}
	return Metrics{RejectedUploads: 1}
}
