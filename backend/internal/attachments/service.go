package attachments

import (
	"context"
	"errors"
	"fmt"
	"io"
	"mime"
	"path/filepath"
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
}

type service struct {
	repo    Repository
	storage StorageService
}

func NewService(repo Repository, storage StorageService) Service {
	return &service{repo: repo, storage: storage}
}

func (s *service) Upload(ctx context.Context, noteID pgtype.UUID, userID pgtype.UUID, filename string, r io.Reader, size int64) (sqlcgen.Attachment, error) {
	if size < 0 {
		return sqlcgen.Attachment{}, ErrInvalidFileSize
	}
	if size > maxUploadBytes {
		return sqlcgen.Attachment{}, ErrFileTooLarge
	}

	permission, err := s.repo.CheckNotePermission(ctx, noteID, userID)
	if err != nil {
		return sqlcgen.Attachment{}, fmt.Errorf("check note permission: %w", err)
	}
	if permission == "not_found" {
		return sqlcgen.Attachment{}, ErrNoteNotFound
	}
	if permission != "owner" && permission != "edit" {
		return sqlcgen.Attachment{}, ErrNoPermission
	}

	ext := filepath.Ext(filename)
	mimeType := mime.TypeByExtension(ext)
	if mimeType == "" {
		mimeType = "application/octet-stream"
	}
	key := fmt.Sprintf("attachments/%s/%d%s", uid.UUIDToString(noteID), time.Now().UnixNano(), ext)
	limited := &uploadLimitReader{r: r, remaining: maxUploadBytes}

	object, err := s.storage.Upload(ctx, key, limited, mimeType, size)
	if err != nil {
		return sqlcgen.Attachment{}, fmt.Errorf("upload to storage: %w", err)
	}
	attachment, err := s.repo.Insert(ctx, noteID, filename, object.PublicURL, mimeType, size)
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
