package attachments

import (
	"context"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

type Repository interface {
	Insert(ctx context.Context, noteID pgtype.UUID, filename, url, mimeType string, sizeBytes int64) (sqlcgen.Attachment, error)
	ListByNote(ctx context.Context, noteID pgtype.UUID) ([]sqlcgen.Attachment, error)
	Delete(ctx context.Context, id pgtype.UUID) error
}

type repository struct {
	q *sqlcgen.Queries
}

func NewRepository(q *sqlcgen.Queries) Repository {
	return &repository{q: q}
}

func (r *repository) Insert(ctx context.Context, noteID pgtype.UUID, filename, url, mimeType string, sizeBytes int64) (sqlcgen.Attachment, error) {
	return r.q.InsertAttachment(ctx, sqlcgen.InsertAttachmentParams{
		NoteID:    noteID,
		Filename:  filename,
		Url:       url,
		MimeType:  mimeType,
		SizeBytes: sizeBytes,
	})
}

func (r *repository) ListByNote(ctx context.Context, noteID pgtype.UUID) ([]sqlcgen.Attachment, error) {
	return r.q.ListAttachmentsByNote(ctx, noteID)
}

func (r *repository) Delete(ctx context.Context, id pgtype.UUID) error {
	return r.q.DeleteAttachment(ctx, id)
}
