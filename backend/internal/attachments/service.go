package attachments

import (
	"context"
	"fmt"
	"io"
	"mime"
	"path/filepath"
	"time"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/pkg/uid"
)

const maxUploadBytes = 50 * 1024 * 1024 // 50 MB

type Service interface {
	Upload(ctx context.Context, noteID pgtype.UUID, filename string, r io.Reader, size int64) (sqlcgen.Attachment, error)
	ListByNote(ctx context.Context, noteID pgtype.UUID) ([]sqlcgen.Attachment, error)
}

type service struct {
	repo    Repository
	storage StorageService
}

func NewService(repo Repository, storage StorageService) Service {
	return &service{repo: repo, storage: storage}
}

func (s *service) Upload(ctx context.Context, noteID pgtype.UUID, filename string, r io.Reader, size int64) (sqlcgen.Attachment, error) {
	if size > maxUploadBytes {
		return sqlcgen.Attachment{}, fmt.Errorf("file too large: %d bytes (max 50 MB)", size)
	}
	ext := filepath.Ext(filename)
	mimeType := mime.TypeByExtension(ext)
	if mimeType == "" {
		mimeType = "application/octet-stream"
	}
	key := fmt.Sprintf("attachments/%s/%d%s", uid.UUIDToString(noteID), time.Now().UnixNano(), ext)

	publicURL, err := s.storage.Upload(ctx, key, r, mimeType, size)
	if err != nil {
		return sqlcgen.Attachment{}, fmt.Errorf("upload to storage: %w", err)
	}
	return s.repo.Insert(ctx, noteID, filename, publicURL, mimeType, size)
}

func (s *service) ListByNote(ctx context.Context, noteID pgtype.UUID) ([]sqlcgen.Attachment, error) {
	return s.repo.ListByNote(ctx, noteID)
}
