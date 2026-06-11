package embeddings

import (
	"context"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/pgvector/pgvector-go"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

type Repository interface {
	GetPendingEmbeddings(ctx context.Context, limit int32) ([]sqlcgen.GetPendingEmbeddingsRow, error)
	GetRetryableEmbeddings(ctx context.Context, limit int32) ([]sqlcgen.GetRetryableEmbeddingsRow, error)
	UpdateNoteEmbeddingStatus(ctx context.Context, id pgtype.UUID, embeddingStatus string) error
	UpsertNoteEmbedding(ctx context.Context, noteID pgtype.UUID, embedding pgvector.Vector) error
}

type repository struct {
	q sqlcgen.Querier
}

func NewRepository(q sqlcgen.Querier) Repository {
	return &repository{q: q}
}

func (r *repository) GetPendingEmbeddings(ctx context.Context, limit int32) ([]sqlcgen.GetPendingEmbeddingsRow, error) {
	return r.q.GetPendingEmbeddings(ctx, limit)
}

func (r *repository) GetRetryableEmbeddings(ctx context.Context, limit int32) ([]sqlcgen.GetRetryableEmbeddingsRow, error) {
	return r.q.GetRetryableEmbeddings(ctx, limit)
}

func (r *repository) UpdateNoteEmbeddingStatus(ctx context.Context, id pgtype.UUID, embeddingStatus string) error {
	return r.q.UpdateNoteEmbeddingStatus(ctx, sqlcgen.UpdateNoteEmbeddingStatusParams{
		ID:              id,
		EmbeddingStatus: embeddingStatus,
	})
}

func (r *repository) UpsertNoteEmbedding(ctx context.Context, noteID pgtype.UUID, embedding pgvector.Vector) error {
	return r.q.UpsertNoteEmbedding(ctx, sqlcgen.UpsertNoteEmbeddingParams{
		NoteID:    noteID,
		Embedding: embedding,
	})
}
