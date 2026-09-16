package attachments

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

var ErrInvalidPermissionResponse = errors.New("invalid note permission response")

type DeliveryRepository interface {
	CheckNotePermission(ctx context.Context, noteID pgtype.UUID, userID pgtype.UUID) (string, error)
	GetByID(ctx context.Context, id pgtype.UUID) (sqlcgen.Attachment, error)
}

type Repository interface {
	DeliveryRepository
	Insert(ctx context.Context, noteID pgtype.UUID, filename, storageKey, mimeType string, sizeBytes int64) (sqlcgen.Attachment, error)
	ListByNote(ctx context.Context, noteID pgtype.UUID) ([]sqlcgen.Attachment, error)
	Delete(ctx context.Context, id pgtype.UUID) error
	EnqueueStorageDeletion(ctx context.Context, storageKey string) error
	ClaimStorageDeletion(ctx context.Context, storageKey *string) (sqlcgen.ClaimAttachmentDeletionRow, error)
	CompleteStorageDeletion(ctx context.Context, id pgtype.UUID) error
	RetryStorageDeletion(ctx context.Context, id pgtype.UUID, lastError string) error
}

type repository struct {
	q sqlcgen.Querier
}

func NewRepository(q *sqlcgen.Queries) Repository {
	return &repository{q: q}
}

func (r *repository) WithQuerier(q sqlcgen.Querier) Repository {
	return &repository{q: q}
}

func (r *repository) CheckNotePermission(ctx context.Context, noteID pgtype.UUID, userID pgtype.UUID) (string, error) {
	permission, err := r.q.CheckNotePermission(ctx, sqlcgen.CheckNotePermissionParams{
		ID:     noteID,
		UserID: userID,
	})
	if err != nil {
		return "", err
	}
	return parsePermissionResponse(permission)
}

func parsePermissionResponse(permission any) (string, error) {
	switch value := permission.(type) {
	case string:
		if value == "" {
			return "", fmt.Errorf("%w: empty string", ErrInvalidPermissionResponse)
		}
		return value, nil
	case []byte:
		if len(value) == 0 {
			return "", fmt.Errorf("%w: empty bytes", ErrInvalidPermissionResponse)
		}
		return string(value), nil
	case pgtype.Text:
		if !value.Valid || value.String == "" {
			return "", fmt.Errorf("%w: invalid text", ErrInvalidPermissionResponse)
		}
		return value.String, nil
	case nil:
		return "", fmt.Errorf("%w: nil response", ErrInvalidPermissionResponse)
	default:
		return "", fmt.Errorf("%w: %T", ErrInvalidPermissionResponse, permission)
	}
}

func (r *repository) Insert(ctx context.Context, noteID pgtype.UUID, filename, storageKey, mimeType string, sizeBytes int64) (sqlcgen.Attachment, error) {
	return r.q.InsertAttachment(ctx, sqlcgen.InsertAttachmentParams{
		NoteID:     noteID,
		Filename:   filename,
		StorageKey: storageKey,
		MimeType:   mimeType,
		SizeBytes:  sizeBytes,
	})
}

func (r *repository) ListByNote(ctx context.Context, noteID pgtype.UUID) ([]sqlcgen.Attachment, error) {
	return r.q.ListAttachmentsByNote(ctx, noteID)
}

func (r *repository) GetByID(ctx context.Context, id pgtype.UUID) (sqlcgen.Attachment, error) {
	return r.q.GetAttachmentByID(ctx, id)
}

func (r *repository) Delete(ctx context.Context, id pgtype.UUID) error {
	return r.q.DeleteAttachment(ctx, id)
}

func (r *repository) EnqueueStorageDeletion(ctx context.Context, storageKey string) error {
	return r.q.EnqueueAttachmentDeletion(ctx, storageKey)
}

func (r *repository) ClaimStorageDeletion(ctx context.Context, storageKey *string) (sqlcgen.ClaimAttachmentDeletionRow, error) {
	arg := sqlcgen.ClaimAttachmentDeletionParams{}
	if storageKey != nil {
		arg.StorageKey = pgtype.Text{String: *storageKey, Valid: true}
	}
	return r.q.ClaimAttachmentDeletion(ctx, arg)
}

func (r *repository) CompleteStorageDeletion(ctx context.Context, id pgtype.UUID) error {
	return r.q.CompleteAttachmentDeletion(ctx, id)
}

func (r *repository) RetryStorageDeletion(ctx context.Context, id pgtype.UUID, lastError string) error {
	return r.q.RetryAttachmentDeletion(ctx, sqlcgen.RetryAttachmentDeletionParams{
		ID:        id,
		LastError: lastError,
	})
}
