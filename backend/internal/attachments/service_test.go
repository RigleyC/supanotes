package attachments

import (
	"bytes"
	"context"
	"errors"
	"io"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/stretchr/testify/require"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/pkg/uid"
)

func TestUploadAllowsOwnerAndEditor(t *testing.T) {
	t.Parallel()

	for _, permission := range []string{"owner", "edit"} {
		permission := permission
		t.Run(permission, func(t *testing.T) {
			t.Parallel()

			repo := &fakeAttachmentRepo{permission: permission}
			storage := &fakeStorage{readUpload: true}
			svc := NewService(repo, storage)

			attachment, err := svc.Upload(context.Background(), testUUID(1), testUUID(2), "file.txt", bytes.NewReader([]byte("hello")), 5)

			require.NoError(t, err)
			require.Equal(t, "file.txt", attachment.Filename)
			require.Equal(t, 1, storage.uploadCalls)
			require.Equal(t, 1, repo.insertCalls)
		})
	}
}

func TestUploadRejectsViewNoAccessAndDeletedBeforeStorage(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name       string
		permission string
		wantErr    error
	}{
		{name: "view", permission: "view", wantErr: ErrNoPermission},
		{name: "none", permission: "none", wantErr: ErrNoPermission},
		{name: "not-found", permission: "not_found", wantErr: ErrNoteNotFound},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			repo := &fakeAttachmentRepo{permission: tc.permission}
			storage := &fakeStorage{}
			svc := NewService(repo, storage)

			_, err := svc.Upload(context.Background(), testUUID(1), testUUID(2), "file.txt", bytes.NewReader([]byte("hello")), 5)

			require.ErrorIs(t, err, tc.wantErr)
			require.Equal(t, 0, storage.uploadCalls)
			require.Equal(t, 0, repo.insertCalls)
			require.Equal(t, int64(1), svc.Metrics().RejectedUploads)
		})
	}
}

func TestUploadRejectsUnsafeSizeBeforeStorage(t *testing.T) {
	t.Parallel()

	for _, size := range []int64{-1, maxUploadBytes + 1} {
		repo := &fakeAttachmentRepo{permission: "owner"}
		storage := &fakeStorage{}
		svc := NewService(repo, storage)

		_, err := svc.Upload(context.Background(), testUUID(1), testUUID(2), "file.txt", bytes.NewReader(nil), size)

		require.Error(t, err)
		require.Equal(t, 0, storage.uploadCalls)
		require.Equal(t, int64(1), svc.Metrics().RejectedUploads)
	}
}

func TestUploadReaderStopsAboveLimit(t *testing.T) {
	t.Parallel()

	repo := &fakeAttachmentRepo{permission: "owner"}
	storage := &fakeStorage{readUpload: true}
	svc := NewService(repo, storage)

	_, err := svc.Upload(context.Background(), testUUID(1), testUUID(2), "file.txt", &overLimitReader{}, maxUploadBytes)

	require.ErrorIs(t, err, ErrFileTooLarge)
	require.Equal(t, 1, storage.uploadCalls)
	require.Equal(t, 0, repo.insertCalls)
	require.Equal(t, int64(1), svc.Metrics().RejectedUploads)
}

func TestUploadLimitReaderAllowsExactLimitEOF(t *testing.T) {
	t.Parallel()

	reader := &uploadLimitReader{r: bytes.NewReader([]byte("hello")), remaining: 5}
	data, err := io.ReadAll(reader)

	require.NoError(t, err)
	require.Equal(t, "hello", string(data))
}

func TestUploadDeletesObjectWhenMetadataInsertFails(t *testing.T) {
	t.Parallel()

	insertErr := errors.New("insert failed")
	repo := &fakeAttachmentRepo{permission: "owner", insertErr: insertErr}
	storage := &fakeStorage{readUpload: true}
	svc := NewService(repo, storage)

	_, err := svc.Upload(context.Background(), testUUID(1), testUUID(2), "file.txt", bytes.NewReader([]byte("hello")), 5)

	require.ErrorContains(t, err, "insert attachment metadata")
	require.Equal(t, 1, storage.uploadCalls)
	require.Equal(t, []string{"attachments/00000000-0000-0000-0000-000000000001"}, storage.deletedKeyPrefixes())
}

func TestUploadRejectsDeclaredSizeMismatch(t *testing.T) {
	t.Parallel()

	repo := &fakeAttachmentRepo{permission: "owner"}
	storage := &fakeStorage{readUpload: true}
	svc := NewService(repo, storage)

	_, err := svc.Upload(context.Background(), testUUID(1), testUUID(2), "file.txt", bytes.NewReader([]byte("hello")), 6)

	require.ErrorIs(t, err, ErrInvalidFileSize)
	require.Equal(t, 1, storage.uploadCalls)
	require.Equal(t, 0, repo.insertCalls)
	require.Equal(t, int64(1), svc.Metrics().RejectedUploads)
	require.Len(t, storage.deleteCalls, 1)
}

func TestUploadRejectsContentLargerThanDeclaredSize(t *testing.T) {
	t.Parallel()

	repo := &fakeAttachmentRepo{permission: "owner"}
	storage := &fakeStorage{readUpload: true}
	svc := NewService(repo, storage)

	_, err := svc.Upload(context.Background(), testUUID(1), testUUID(2), "file.txt", bytes.NewReader([]byte("longer")), 5)

	require.ErrorIs(t, err, ErrInvalidFileSize)
	require.Equal(t, 0, repo.insertCalls)
	require.Len(t, storage.deleteCalls, 1)
}

type fakeAttachmentRepo struct {
	permission  string
	insertErr   error
	insertCalls int
	attachment  sqlcgen.Attachment
}

func (r *fakeAttachmentRepo) CheckNotePermission(_ context.Context, _ pgtype.UUID, _ pgtype.UUID) (string, error) {
	return r.permission, nil
}

func (r *fakeAttachmentRepo) Insert(_ context.Context, noteID pgtype.UUID, filename, url, mimeType string, sizeBytes int64) (sqlcgen.Attachment, error) {
	r.insertCalls++
	if r.insertErr != nil {
		return sqlcgen.Attachment{}, r.insertErr
	}
	return sqlcgen.Attachment{
		ID:        testUUID(3),
		NoteID:    noteID,
		Filename:  filename,
		Url:       url,
		MimeType:  mimeType,
		SizeBytes: sizeBytes,
		CreatedAt: pgtype.Timestamptz{
			Time:  time.Unix(0, 0).UTC(),
			Valid: true,
		},
	}, nil
}

func (r *fakeAttachmentRepo) ListByNote(context.Context, pgtype.UUID) ([]sqlcgen.Attachment, error) {
	return nil, nil
}

func (r *fakeAttachmentRepo) GetByID(context.Context, pgtype.UUID) (sqlcgen.Attachment, error) {
	return r.attachment, nil
}

func (r *fakeAttachmentRepo) Delete(context.Context, pgtype.UUID) error {
	return nil
}

type fakeStorage struct {
	uploadCalls int
	deleteCalls []string
	readUpload  bool
}

func (s *fakeStorage) Upload(_ context.Context, key string, r io.Reader, _ string, _ int64) (StoredObject, error) {
	s.uploadCalls++
	if s.readUpload {
		buf := make([]byte, 32*1024)
		for {
			_, err := r.Read(buf)
			if err == io.EOF {
				break
			}
			if err != nil {
				return StoredObject{}, err
			}
		}
	}
	return StoredObject{Key: key}, nil
}

func (s *fakeStorage) Delete(_ context.Context, key string) error {
	s.deleteCalls = append(s.deleteCalls, key)
	return nil
}

func (s *fakeStorage) Open(_ context.Context, _ string) (io.ReadCloser, error) {
	return io.NopCloser(strings.NewReader("attachment")), nil
}

func (s *fakeStorage) deletedKeyPrefixes() []string {
	prefixes := make([]string, 0, len(s.deleteCalls))
	for _, key := range s.deleteCalls {
		if len(key) >= len("attachments/00000000-0000-0000-0000-000000000001") {
			prefixes = append(prefixes, key[:len("attachments/00000000-0000-0000-0000-000000000001")])
		}
	}
	return prefixes
}

type overLimitReader struct {
	read int64
}

func (r *overLimitReader) Read(p []byte) (int, error) {
	if r.read > maxUploadBytes {
		return 0, io.EOF
	}
	n := len(p)
	r.read += int64(n)
	return n, nil
}

func testUUID(lastByte byte) pgtype.UUID {
	u, _ := uid.UUIDFromString("00000000-0000-0000-0000-000000000000")
	u.Bytes[15] = lastByte
	return u
}
