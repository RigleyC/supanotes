package attachments

import (
	"context"
	"errors"
	"fmt"
	"io"
	"mime"
	"net/url"
	"path/filepath"
	"strings"
	"sync/atomic"
	"time"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/pkg/uid"
)

const maxUploadBytes = 200 * 1024 * 1024 // 200 MB

var (
	ErrFileTooLarge    = errors.New("file exceeds 200 MB limit")
	ErrInvalidFileSize = errors.New("invalid file size")
	ErrNoPermission    = errors.New("no permission")
	ErrNoteNotFound    = errors.New("note not found")
)

type Service interface {
	Upload(ctx context.Context, noteID pgtype.UUID, userID pgtype.UUID, filename string, r io.Reader, size int64) (sqlcgen.Attachment, error)
	ListByNote(ctx context.Context, noteID pgtype.UUID) ([]sqlcgen.Attachment, error)
	Delete(ctx context.Context, userID, attachmentID pgtype.UUID) error
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
		return sqlcgen.Attachment{}, fmt.Errorf("upload to storage: %w", err)
	}
	contentTooLarge := false
	if counted.bytesRead == size {
		var probe [1]byte
		_, probeErr := counted.Read(probe[:])
		contentTooLarge = errors.Is(probeErr, ErrFileTooLarge)
		if probeErr != nil && !errors.Is(probeErr, io.EOF) && !errors.Is(probeErr, ErrFileTooLarge) {
			if deleteErr := s.storage.Delete(ctx, object.Key); deleteErr != nil {
				return sqlcgen.Attachment{}, fmt.Errorf("verify upload size: %w; cleanup uploaded object: %v", probeErr, deleteErr)
			}
			return sqlcgen.Attachment{}, fmt.Errorf("verify upload size: %w", probeErr)
		}
	}
	if contentTooLarge || counted.bytesRead != size {
		s.rejectedUploads.Add(1)
		if deleteErr := s.storage.Delete(ctx, object.Key); deleteErr != nil {
			return sqlcgen.Attachment{}, fmt.Errorf("verify upload size: %w; cleanup uploaded object: %v", ErrInvalidFileSize, deleteErr)
		}
		return sqlcgen.Attachment{}, ErrInvalidFileSize
	}
	attachment, err := s.repo.Insert(ctx, noteID, filename, object.PublicURL, mimeType, counted.bytesRead)
	if err != nil {
		if deleteErr := s.storage.Delete(ctx, object.Key); deleteErr != nil {
			return sqlcgen.Attachment{}, fmt.Errorf("insert attachment metadata: %w; cleanup uploaded object: %v", err, deleteErr)
		}
		return sqlcgen.Attachment{}, fmt.Errorf("insert attachment metadata: %w", err)
	}
	return attachment, nil
}

func (s *service) ListByNote(ctx context.Context, noteID pgtype.UUID) ([]sqlcgen.Attachment, error) {
	return s.repo.ListByNote(ctx, noteID)
}

func (s *service) Delete(ctx context.Context, userID, attachmentID pgtype.UUID) error {
	attachment, err := s.repo.GetByID(ctx, attachmentID)
	if err != nil {
		return err
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
	key, err := storageKeyFromURL(attachment.Url)
	if err != nil {
		return err
	}
	if err := s.storage.Delete(ctx, key); err != nil {
		return fmt.Errorf("delete attachment object: %w", err)
	}
	if err := s.repo.Delete(ctx, attachmentID); err != nil {
		return fmt.Errorf("delete attachment metadata: %w", err)
	}
	return nil
}

func storageKeyFromURL(raw string) (string, error) {
	parsed, err := url.Parse(raw)
	if err != nil {
		return "", fmt.Errorf("parse attachment URL: %w", err)
	}
	marker := "/attachments/"
	index := strings.Index(parsed.Path, marker)
	if index < 0 {
		return "", fmt.Errorf("attachment URL does not contain storage key")
	}
	key, err := url.PathUnescape(strings.TrimPrefix(parsed.Path[index:], "/"))
	if err != nil {
		return "", fmt.Errorf("decode attachment storage key: %w", err)
	}
	return key, nil
}

func (s *service) Metrics() Metrics {
	return Metrics{RejectedUploads: s.rejectedUploads.Load()}
}

type uploadCountReader struct {
	r         io.Reader
	bytesRead int64
}

func (r *uploadCountReader) Read(p []byte) (int, error) {
	n, err := r.r.Read(p)
	r.bytesRead += int64(n)
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
