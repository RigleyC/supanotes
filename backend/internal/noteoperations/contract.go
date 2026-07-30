package noteoperations

import (
	"context"

	"github.com/jackc/pgx/v5/pgtype"
)

// DocumentCommandService is the application seam for document mutations.
// Callers must use it instead of writing notes.document or task projections.
type DocumentCommandService interface {
	SyncOperations(ctx context.Context, noteID pgtype.UUID, userID pgtype.UUID, req SyncRequest) (SyncResponse, error)
}

// DocumentReader is the read seam paired with DocumentCommandService.
type DocumentReader interface {
	GetDocument(ctx context.Context, noteID pgtype.UUID, userID pgtype.UUID) (DocumentResponse, error)
	GetOperationsSince(ctx context.Context, noteID pgtype.UUID, userID pgtype.UUID, afterRevision int64) (OperationsListResponse, error)
}

// DocumentService groups the read and mutation seams used by integrations.
type DocumentService interface {
	DocumentCommandService
	DocumentReader
}

var _ DocumentService = (*Service)(nil)
