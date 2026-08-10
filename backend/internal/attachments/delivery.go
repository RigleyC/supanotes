package attachments

import (
	"context"
	"errors"
	"fmt"
	"io"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

var (
	ErrAttachmentNotFound  = errors.New("attachment not found")
	ErrAttachmentForbidden = errors.New("attachment access forbidden")
	ErrPublicLinkNotFound  = errors.New("public link not found")
)

// AttachmentDelivery contains an already-authorized object stream. The caller
// owns Body and must close it after writing the response.
type AttachmentDelivery struct {
	Body      io.ReadCloser
	Filename  string
	MimeType  string
	SizeBytes int64
}

// DeliveryService centralizes authorization and private-object opening for
// authenticated and Share Link downloads.
type DeliveryService struct {
	repo    Repository
	storage StorageService
}

func NewDeliveryService(repo Repository, storage StorageService) *DeliveryService {
	return &DeliveryService{repo: repo, storage: storage}
}

func (s *DeliveryService) Authenticated(ctx context.Context, userID, attachmentID pgtype.UUID) (AttachmentDelivery, error) {
	attachment, err := s.load(ctx, attachmentID)
	if err != nil {
		return AttachmentDelivery{}, err
	}
	permission, err := s.repo.CheckNotePermission(ctx, attachment.NoteID, userID)
	if err != nil {
		return AttachmentDelivery{}, fmt.Errorf("check attachment permission: %w", err)
	}
	if permission == "not_found" {
		return AttachmentDelivery{}, ErrAttachmentNotFound
	}
	if permission != "owner" && permission != "edit" && permission != "view" {
		return AttachmentDelivery{}, ErrAttachmentForbidden
	}
	return s.open(ctx, attachment)
}

func (s *DeliveryService) Public(ctx context.Context, noteID, attachmentID pgtype.UUID) (AttachmentDelivery, error) {
	attachment, err := s.load(ctx, attachmentID)
	if err != nil {
		return AttachmentDelivery{}, err
	}
	if attachment.NoteID != noteID {
		return AttachmentDelivery{}, ErrAttachmentNotFound
	}
	return s.open(ctx, attachment)
}

func (s *DeliveryService) load(ctx context.Context, attachmentID pgtype.UUID) (sqlcgen.Attachment, error) {
	attachment, err := s.repo.GetByID(ctx, attachmentID)
	if errors.Is(err, pgx.ErrNoRows) {
		return sqlcgen.Attachment{}, ErrAttachmentNotFound
	}
	if err != nil {
		return sqlcgen.Attachment{}, fmt.Errorf("load attachment: %w", err)
	}
	return attachment, nil
}

func (s *DeliveryService) open(ctx context.Context, attachment sqlcgen.Attachment) (AttachmentDelivery, error) {
	if err := validateStorageKey(attachment.StorageKey); err != nil {
		return AttachmentDelivery{}, fmt.Errorf("validate attachment storage key: %w", err)
	}
	body, err := s.storage.Open(ctx, attachment.StorageKey)
	if err != nil {
		return AttachmentDelivery{}, fmt.Errorf("open attachment object: %w", err)
	}
	return AttachmentDelivery{
		Body:      body,
		Filename:  attachment.Filename,
		MimeType:  attachment.MimeType,
		SizeBytes: attachment.SizeBytes,
	}, nil
}
