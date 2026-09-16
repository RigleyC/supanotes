package attachments

import (
	"context"
	"errors"
	"fmt"
	"io"
	"mime"
	"path"
	"path/filepath"
	"strings"
	"sync/atomic"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/pkg/uid"
)

const maxUploadBytes = 200 * 1024 * 1024 // 200 MB

var (
	ErrFileTooLarge       = errors.New("file exceeds 200 MB limit")
	ErrInvalidFileSize    = errors.New("invalid file size")
	ErrUploadRead         = errors.New("attachment upload source read failed")
	ErrNoPermission       = errors.New("no permission")
	ErrNoteNotFound       = errors.New("note not found")
	ErrAttachmentMetadata = errors.New("attachment metadata is invalid")
)

const (
	storageDeleteAttempts = 3
	storageDeleteBackoff  = 10 * time.Millisecond
)

type Service interface {
	Upload(ctx context.Context, noteID pgtype.UUID, userID pgtype.UUID, filename string, r io.Reader, size int64) (sqlcgen.Attachment, error)
	ListByNote(ctx context.Context, noteID pgtype.UUID) ([]sqlcgen.Attachment, error)
	Delete(ctx context.Context, userID, attachmentID pgtype.UUID) error
	CleanupPending(ctx context.Context) error
	Metrics() Metrics
}

type Metrics struct {
	RejectedUploads int64
}

type service struct {
	repo            Repository
	storage         StorageService
	rejectedUploads atomic.Int64
}

func NewService(repo Repository, storage StorageService) Service {
	return &service{repo: repo, storage: storage}
}

func (s *service) Upload(ctx context.Context, noteID pgtype.UUID, userID pgtype.UUID, filename string, r io.Reader, size int64) (sqlcgen.Attachment, error) {
	if size < 0 {
		s.rejectedUploads.Add(1)
		return sqlcgen.Attachment{}, ErrInvalidFileSize
	}
	if size > maxUploadBytes {
		s.rejectedUploads.Add(1)
		return sqlcgen.Attachment{}, ErrFileTooLarge
	}

	permission, err := s.repo.CheckNotePermission(ctx, noteID, userID)
	if err != nil {
		return sqlcgen.Attachment{}, fmt.Errorf("check note permission: %w", err)
	}
	if permission == "not_found" {
		s.rejectedUploads.Add(1)
		return sqlcgen.Attachment{}, ErrNoteNotFound
	}
	if permission != "owner" && permission != "edit" {
		s.rejectedUploads.Add(1)
		return sqlcgen.Attachment{}, ErrNoPermission
	}

	ext := filepath.Ext(filename)
	mimeType := mime.TypeByExtension(ext)
	if mimeType == "" {
		mimeType = "application/octet-stream"
	}
	key := fmt.Sprintf("attachments/%s/%d%s", uid.UUIDToString(noteID), time.Now().UnixNano(), ext)
	declaredLimit := size
	if declaredLimit < maxUploadBytes {
		declaredLimit++
	}
	limited := &uploadLimitReader{r: r, remaining: declaredLimit}
	counted := &uploadCountReader{r: limited}

	object, err := s.storage.Upload(ctx, key, counted, mimeType, size)
	if err != nil {
		if errors.Is(err, ErrFileTooLarge) {
			s.rejectedUploads.Add(1)
		}
		if counted.readErr != nil && !errors.Is(counted.readErr, io.EOF) && !errors.Is(counted.readErr, ErrFileTooLarge) {
			err = errors.Join(ErrUploadRead, counted.readErr, err)
		}
		return sqlcgen.Attachment{}, s.uploadFailure(ctx, key, err)
	}
	if counted.readErr != nil && !errors.Is(counted.readErr, io.EOF) {
		if errors.Is(counted.readErr, ErrFileTooLarge) {
			s.rejectedUploads.Add(1)
			return sqlcgen.Attachment{}, s.uploadFailure(ctx, key, ErrFileTooLarge)
		}
		return sqlcgen.Attachment{}, s.uploadFailure(ctx, key, errors.Join(ErrUploadRead, counted.readErr))
	}
	if object.Key != key || validateStorageKey(object.Key) != nil {
		return sqlcgen.Attachment{}, s.uploadFailure(ctx, key, ErrStorageInvalidObject)
	}
	contentTooLarge := false
	if counted.bytesRead == size {
		var probe [1]byte
		_, probeErr := counted.Read(probe[:])
		contentTooLarge = errors.Is(probeErr, ErrFileTooLarge)
		if probeErr != nil && !errors.Is(probeErr, io.EOF) && !errors.Is(probeErr, ErrFileTooLarge) {
			return sqlcgen.Attachment{}, s.uploadFailure(ctx, key, errors.Join(ErrUploadRead, probeErr))
		}
	}
	if contentTooLarge || counted.bytesRead != size {
		s.rejectedUploads.Add(1)
		return sqlcgen.Attachment{}, s.uploadFailure(ctx, key, ErrInvalidFileSize)
	}
	attachment, err := s.repo.Insert(ctx, noteID, filename, object.Key, mimeType, counted.bytesRead)
	if err != nil {
		return sqlcgen.Attachment{}, s.uploadFailure(ctx, key, fmt.Errorf("insert attachment metadata: %w", err))
	}
	if !attachment.ID.Valid || attachment.NoteID != noteID || attachment.Filename != filename || attachment.StorageKey != object.Key || attachment.MimeType != mimeType || attachment.SizeBytes != counted.bytesRead || !attachment.CreatedAt.Valid {
		return sqlcgen.Attachment{}, s.uploadFailure(ctx, key, ErrAttachmentMetadata)
	}
	return attachment, nil
}

func (s *service) ListByNote(ctx context.Context, noteID pgtype.UUID) ([]sqlcgen.Attachment, error) {
	attachments, err := s.repo.ListByNote(ctx, noteID)
	if err != nil {
		return nil, fmt.Errorf("list attachments: %w", err)
	}
	return attachments, nil
}

func (s *service) Delete(ctx context.Context, userID, attachmentID pgtype.UUID) error {
	attachment, err := s.repo.GetByID(ctx, attachmentID)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("load attachment for deletion: %w", err)
	}
	permission, err := s.repo.CheckNotePermission(ctx, attachment.NoteID, userID)
	if err != nil {
		return fmt.Errorf("check note permission: %w", err)
	}
	if permission == "not_found" {
		return ErrNoteNotFound
	}
	if permission != "owner" && permission != "edit" {
		return ErrNoPermission
	}
	if err := validateStorageKey(attachment.StorageKey); err != nil {
		return fmt.Errorf("validate attachment storage key: %w", err)
	}

	if err := s.repo.Delete(ctx, attachmentID); err != nil {
		return fmt.Errorf("delete attachment metadata: %w", err)
	}
	return s.cleanupStorageKey(ctx, attachment.StorageKey)
}

// DeleteInTransaction removes attachment metadata and enqueues its storage
// cleanup in the caller's transaction. MCP uses this seam to commit the
// destructive effect and the confirmation result atomically; the outbox then
// makes the external object deletion retryable and idempotent.
func (s *service) DeleteInTransaction(ctx context.Context, tx pgx.Tx, userID, attachmentID pgtype.UUID) error {
	if tx == nil {
		return errors.New("attachment deletion transaction is missing")
	}
	transactionalRepo, ok := s.repo.(interface {
		WithQuerier(sqlcgen.Querier) Repository
	})
	if !ok {
		return errors.New("attachment repository transaction is not configured")
	}
	repo := transactionalRepo.WithQuerier(sqlcgen.New(tx))
	attachment, err := repo.GetByID(ctx, attachmentID)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("load attachment for deletion: %w", err)
	}
	permission, err := repo.CheckNotePermission(ctx, attachment.NoteID, userID)
	if err != nil {
		return fmt.Errorf("check note permission: %w", err)
	}
	if permission == "not_found" {
		return ErrNoteNotFound
	}
	if permission != "owner" && permission != "edit" {
		return ErrNoPermission
	}
	if err := validateStorageKey(attachment.StorageKey); err != nil {
		return fmt.Errorf("validate attachment storage key: %w", err)
	}
	if err := repo.Delete(ctx, attachmentID); err != nil {
		return fmt.Errorf("delete attachment metadata: %w", err)
	}
	if err := repo.EnqueueStorageDeletion(ctx, attachment.StorageKey); err != nil {
		return fmt.Errorf("enqueue attachment storage deletion: %w", err)
	}
	return nil
}

func (s *service) uploadFailure(ctx context.Context, key string, cause error) error {
	cleanupErr := s.cleanupUploadedObject(ctx, key)
	if cleanupErr != nil {
		return fmt.Errorf("attachment upload failed and cleanup uploaded object failed: %w", errors.Join(cause, cleanupErr))
	}
	return cause
}

func (s *service) cleanupUploadedObject(ctx context.Context, key string) error {
	if err := s.repo.EnqueueStorageDeletion(ctx, key); err != nil {
		return fmt.Errorf("enqueue uploaded object cleanup: %w", err)
	}
	return s.cleanupStorageKey(ctx, key)
}

func (s *service) cleanupStorageKey(ctx context.Context, key string) error {
	deletion, err := s.repo.ClaimStorageDeletion(ctx, &key)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("claim attachment cleanup: %w", err)
	}
	return s.finishStorageDeletion(ctx, deletion)
}

func (s *service) finishStorageDeletion(ctx context.Context, deletion sqlcgen.ClaimAttachmentDeletionRow) error {
	if deletion.Referenced {
		if err := s.repo.CompleteStorageDeletion(ctx, deletion.ID); err != nil {
			return fmt.Errorf("discard referenced attachment cleanup: %w", err)
		}
		return nil
	}
	if err := s.deleteObjectWithRetry(ctx, deletion.StorageKey); err != nil {
		retryErr := s.repo.RetryStorageDeletion(ctx, deletion.ID, err.Error())
		if retryErr != nil {
			return errors.Join(err, fmt.Errorf("persist attachment cleanup retry: %w", retryErr))
		}
		return err
	}
	if err := s.repo.CompleteStorageDeletion(ctx, deletion.ID); err != nil {
		return fmt.Errorf("complete attachment cleanup: %w", err)
	}
	return nil
}

func (s *service) CleanupPending(ctx context.Context) error {
	var cleanupErr error
	for {
		deletion, err := s.repo.ClaimStorageDeletion(ctx, nil)
		if errors.Is(err, pgx.ErrNoRows) {
			return cleanupErr
		}
		if err != nil {
			return errors.Join(cleanupErr, fmt.Errorf("claim pending attachment cleanup: %w", err))
		}
		if err := s.finishStorageDeletion(ctx, deletion); err != nil {
			cleanupErr = errors.Join(cleanupErr, err)
		}
	}
}

func (s *service) deleteObjectWithRetry(ctx context.Context, key string) error {
	if err := validateStorageKey(key); err != nil {
		return fmt.Errorf("%w: %v", ErrStorageInvalidObject, err)
	}
	var lastErr error
	for attempt := 1; attempt <= storageDeleteAttempts; attempt++ {
		if err := ctx.Err(); err != nil {
			return &StorageOperationError{Operation: "delete", Err: errors.Join(ErrStorageDelete, err)}
		}
		if err := s.storage.Delete(ctx, key); err == nil {
			return nil
		} else {
			lastErr = err
		}
		if attempt < storageDeleteAttempts {
			timer := time.NewTimer(storageDeleteBackoff * time.Duration(attempt))
			select {
			case <-ctx.Done():
				if !timer.Stop() {
					<-timer.C
				}
				return &StorageOperationError{Operation: "delete", Err: errors.Join(ErrStorageDelete, ctx.Err())}
			case <-timer.C:
			}
		}
	}
	return &StorageOperationError{Operation: "delete", Err: errors.Join(ErrStorageDelete, lastErr)}
}

func validateStorageKey(key string) error {
	if key == "" || len(key) > 1024 || !strings.HasPrefix(key, "attachments/") || strings.Contains(key, "\\") || path.Clean(key) != key {
		return fmt.Errorf("attachment storage key is invalid")
	}
	return nil
}

func (s *service) Metrics() Metrics {
	return Metrics{RejectedUploads: s.rejectedUploads.Load()}
}

type uploadCountReader struct {
	r         io.Reader
	bytesRead int64
	readErr   error
}

func (r *uploadCountReader) Read(p []byte) (int, error) {
	n, err := r.r.Read(p)
	r.bytesRead += int64(n)
	if err != nil && !errors.Is(err, io.EOF) {
		r.readErr = err
	}
	return n, err
}

type uploadLimitReader struct {
	r         io.Reader
	remaining int64
}

func (r *uploadLimitReader) Read(p []byte) (int, error) {
	if r.remaining <= 0 {
		var probe [1]byte
		n, err := r.r.Read(probe[:])
		if n > 0 {
			return 0, ErrFileTooLarge
		}
		return 0, err
	}
	if int64(len(p)) > r.remaining {
		p = p[:int(r.remaining)]
	}
	n, err := r.r.Read(p)
	r.remaining -= int64(n)
	return n, err
}
