package attachments

import (
	"bytes"
	"context"
	"errors"
	"io"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
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

func TestUploadRejectsInvalidStorageResponseAndDoesNotPersistMetadata(t *testing.T) {
	t.Parallel()

	repo := &fakeAttachmentRepo{permission: "owner"}
	storage := &fakeStorage{readUpload: true, invalidUploadResponse: true}
	svc := NewService(repo, storage)

	_, err := svc.Upload(context.Background(), testUUID(1), testUUID(2), "file.txt", bytes.NewReader([]byte("hello")), 5)

	require.ErrorIs(t, err, ErrStorageInvalidObject)
	require.Zero(t, repo.insertCalls)
	require.Len(t, storage.deleteCalls, 1)
}

func TestUploadPropagatesReaderFailureAndCleansUpObject(t *testing.T) {
	t.Parallel()

	readErr := errors.New("source read failed")
	repo := &fakeAttachmentRepo{permission: "owner"}
	storage := &fakeStorage{readUpload: true}
	svc := NewService(repo, storage)

	_, err := svc.Upload(context.Background(), testUUID(1), testUUID(2), "file.txt", &errorReader{err: readErr}, 5)

	require.ErrorIs(t, err, readErr)
	require.ErrorIs(t, err, ErrUploadRead)
	require.Zero(t, repo.insertCalls)
	require.Len(t, storage.deleteCalls, 1)
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
	require.Empty(t, repo.pending, "successful immediate cleanup must acknowledge its durable intent")
}

func TestUploadKeepsOriginalFailureWhenCleanupAlsoFails(t *testing.T) {
	t.Parallel()

	insertErr := errors.New("insert failed")
	repo := &fakeAttachmentRepo{permission: "owner", insertErr: insertErr}
	storage := &fakeStorage{
		readUpload: true,
		deleteErrs: []error{errStorageDown, errStorageDown, errStorageDown},
	}
	svc := NewService(repo, storage)

	_, err := svc.Upload(context.Background(), testUUID(1), testUUID(2), "file.txt", bytes.NewReader([]byte("hello")), 5)

	require.ErrorIs(t, err, insertErr)
	require.ErrorIs(t, err, ErrStorageDelete)
	require.Len(t, storage.deleteCalls, storageDeleteAttempts)
	require.Len(t, repo.pending, 1, "failed cleanup must remain retryable in the outbox")
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

func TestDeleteDoesNotDeleteObjectStillReferencedByAnotherAttachment(t *testing.T) {
	t.Parallel()

	attachment := deliveryAttachment()
	repo := &fakeAttachmentRepo{
		attachment: attachment,
		list: []sqlcgen.Attachment{
			attachment,
			{ID: testUUID(4), NoteID: attachment.NoteID, StorageKey: attachment.StorageKey},
		},
		permission: "owner",
	}
	storage := &fakeStorage{}
	svc := NewService(repo, storage)

	require.NoError(t, svc.Delete(context.Background(), testUUID(2), attachment.ID))
	require.Empty(t, storage.deleteCalls)
	require.Equal(t, 1, repo.deleteCalls)
}

func TestDeleteDoesNotTouchStorageWhenMetadataDeleteFails(t *testing.T) {
	t.Parallel()

	attachment := deliveryAttachment()
	repo := &fakeAttachmentRepo{
		attachment: attachment,
		list:       []sqlcgen.Attachment{attachment},
		permission: "owner",
		deleteErr:  errors.New("database unavailable"),
	}
	storage := &fakeStorage{}
	svc := NewService(repo, storage)

	err := svc.Delete(context.Background(), testUUID(2), attachment.ID)

	require.ErrorContains(t, err, "delete attachment metadata")
	require.Empty(t, storage.deleteCalls)
}

func TestDeleteRetriesStorageFailure(t *testing.T) {
	t.Parallel()

	attachment := deliveryAttachment()
	repo := &fakeAttachmentRepo{
		attachment: attachment,
		list:       []sqlcgen.Attachment{attachment},
		permission: "edit",
	}
	storage := &fakeStorage{deleteErrs: []error{errStorageDown, nil}}
	svc := NewService(repo, storage)

	require.NoError(t, svc.Delete(context.Background(), testUUID(2), attachment.ID))
	require.Len(t, storage.deleteCalls, 2)
	require.Equal(t, 1, repo.deleteCalls)
}

func TestDeletePersistsIntentWhenStorageDeletionFails(t *testing.T) {
	t.Parallel()

	attachment := deliveryAttachment()
	repo := &fakeAttachmentRepo{
		attachment: attachment,
		list:       []sqlcgen.Attachment{attachment},
		permission: "owner",
	}
	storage := &fakeStorage{deleteErrs: []error{errStorageDown, errStorageDown, errStorageDown}}
	svc := NewService(repo, storage)

	err := svc.Delete(context.Background(), testUUID(2), attachment.ID)

	require.ErrorIs(t, err, ErrStorageDelete)
	require.Equal(t, 1, repo.deleteCalls)
	require.Len(t, repo.pending, 1)

	storage.deleteErrs = []error{nil}
	require.NoError(t, svc.CleanupPending(context.Background()))
	require.Empty(t, repo.pending)
}

func TestDeleteKeepsObjectWhenReferenceStillExists(t *testing.T) {
	t.Parallel()

	attachment := deliveryAttachment()
	repo := &fakeAttachmentRepo{
		attachment: attachment,
		list:       nil,
		permission: "owner",
	}
	repo.list = []sqlcgen.Attachment{attachment, {ID: testUUID(4), NoteID: attachment.NoteID, StorageKey: attachment.StorageKey}}
	storage := &fakeStorage{}
	svc := NewService(repo, storage)

	require.NoError(t, svc.Delete(context.Background(), testUUID(2), attachment.ID))
	require.Empty(t, storage.deleteCalls)
	require.Empty(t, repo.pending)
}

func TestDeleteIsIdempotentAfterMetadataWasAlreadyRemoved(t *testing.T) {
	t.Parallel()

	repo := &fakeAttachmentRepo{getErr: pgx.ErrNoRows}
	svc := NewService(repo, &fakeStorage{})

	require.NoError(t, svc.Delete(context.Background(), testUUID(2), testUUID(3)))
}

type fakeAttachmentRepo struct {
	permission  string
	insertErr   error
	insertCalls int
	deleteErr   error
	deleteCalls int
	attachment  sqlcgen.Attachment
	getErr      error
	list        []sqlcgen.Attachment
	listErr     error
	enqueueErr  error
	claimErr    error
	pending     []sqlcgen.ClaimAttachmentDeletionRow
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
		ID:         testUUID(3),
		NoteID:     noteID,
		Filename:   filename,
		StorageKey: url,
		MimeType:   mimeType,
		SizeBytes:  sizeBytes,
		CreatedAt: pgtype.Timestamptz{
			Time:  time.Unix(0, 0).UTC(),
			Valid: true,
		},
	}, nil
}

func (r *fakeAttachmentRepo) ListByNote(context.Context, pgtype.UUID) ([]sqlcgen.Attachment, error) {
	return r.list, r.listErr
}

func (r *fakeAttachmentRepo) GetByID(context.Context, pgtype.UUID) (sqlcgen.Attachment, error) {
	if r.getErr != nil {
		return sqlcgen.Attachment{}, r.getErr
	}
	return r.attachment, nil
}

func (r *fakeAttachmentRepo) Delete(_ context.Context, id pgtype.UUID) error {
	r.deleteCalls++
	if r.deleteErr != nil {
		return r.deleteErr
	}
	key := r.attachment.StorageKey
	referenced := false
	for _, candidate := range r.list {
		if candidate.ID != id && candidate.StorageKey == key {
			referenced = true
		}
	}
	r.pending = append(r.pending, sqlcgen.ClaimAttachmentDeletionRow{
		ID:         testUUID(byte(10 + len(r.pending))),
		StorageKey: key,
		Referenced: referenced,
	})
	return nil
}

func (r *fakeAttachmentRepo) EnqueueStorageDeletion(_ context.Context, key string) error {
	if r.enqueueErr != nil {
		return r.enqueueErr
	}
	r.pending = append(r.pending, sqlcgen.ClaimAttachmentDeletionRow{
		ID:         testUUID(byte(10 + len(r.pending))),
		StorageKey: key,
	})
	return nil
}

func (r *fakeAttachmentRepo) ClaimStorageDeletion(_ context.Context, key *string) (sqlcgen.ClaimAttachmentDeletionRow, error) {
	if r.claimErr != nil {
		return sqlcgen.ClaimAttachmentDeletionRow{}, r.claimErr
	}
	for _, deletion := range r.pending {
		if key == nil || deletion.StorageKey == *key {
			return deletion, nil
		}
	}
	return sqlcgen.ClaimAttachmentDeletionRow{}, pgx.ErrNoRows
}

func (r *fakeAttachmentRepo) CompleteStorageDeletion(_ context.Context, id pgtype.UUID) error {
	for i, deletion := range r.pending {
		if deletion.ID == id {
			r.pending = append(r.pending[:i], r.pending[i+1:]...)
			return nil
		}
	}
	return nil
}

func (r *fakeAttachmentRepo) RetryStorageDeletion(_ context.Context, _ pgtype.UUID, _ string) error {
	return nil
}

type fakeStorage struct {
	uploadCalls           int
	deleteCalls           []string
	readUpload            bool
	openErr               error
	deleteErrs            []error
	invalidUploadResponse bool
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
	if s.invalidUploadResponse {
		return StoredObject{}, nil
	}
	return StoredObject{Key: key}, nil
}

func (s *fakeStorage) Delete(_ context.Context, key string) error {
	s.deleteCalls = append(s.deleteCalls, key)
	if len(s.deleteErrs) == 0 {
		return nil
	}
	err := s.deleteErrs[0]
	s.deleteErrs = s.deleteErrs[1:]
	return err
}

func (s *fakeStorage) Open(_ context.Context, _ string) (io.ReadCloser, error) {
	if s.openErr != nil {
		return nil, s.openErr
	}
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

type errorReader struct {
	err error
}

func (r *errorReader) Read([]byte) (int, error) {
	return 0, r.err
}

func testUUID(lastByte byte) pgtype.UUID {
	u, _ := uid.UUIDFromString("00000000-0000-0000-0000-000000000000")
	u.Bytes[15] = lastByte
	return u
}
