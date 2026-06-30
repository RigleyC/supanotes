package memories

import (
	"context"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/pgvector/pgvector-go"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

type Repository interface {
	CountMemories(ctx context.Context, userID pgtype.UUID) (int64, error)
	GetMemories(ctx context.Context, userID pgtype.UUID, limit, offset int32) ([]sqlcgen.Memory, error)
	CreateMemory(ctx context.Context, userID pgtype.UUID, content string, embedding pgvector.Vector) (sqlcgen.Memory, error)
	UpdateMemory(ctx context.Context, id, userID pgtype.UUID, content string, embedding pgvector.Vector) (sqlcgen.Memory, error)
	DeleteMemory(ctx context.Context, id, userID pgtype.UUID) error
	SearchMemories(ctx context.Context, userID pgtype.UUID, embedding pgvector.Vector, limit int32) ([]sqlcgen.SearchMemoriesByEmbeddingRow, error)
}

type repository struct {
	q sqlcgen.Querier
}

func NewRepository(q sqlcgen.Querier) Repository {
	return &repository{q: q}
}

func (r *repository) CountMemories(ctx context.Context, userID pgtype.UUID) (int64, error) {
	return r.q.CountMemories(ctx, userID)
}

func (r *repository) GetMemories(ctx context.Context, userID pgtype.UUID, limit, offset int32) ([]sqlcgen.Memory, error) {
	return r.q.GetMemories(ctx, sqlcgen.GetMemoriesParams{
		UserID: userID,
		Limit:  limit,
		Offset: offset,
	})
}

func (r *repository) CreateMemory(ctx context.Context, userID pgtype.UUID, content string, embedding pgvector.Vector) (sqlcgen.Memory, error) {
	return r.q.CreateMemory(ctx, sqlcgen.CreateMemoryParams{
		UserID:    userID,
		Content:   content,
		Embedding: embedding,
	})
}

func (r *repository) DeleteMemory(ctx context.Context, id, userID pgtype.UUID) error {
	return r.q.DeleteMemory(ctx, sqlcgen.DeleteMemoryParams{
		ID:     id,
		UserID: userID,
	})
}

func (r *repository) UpdateMemory(ctx context.Context, id, userID pgtype.UUID, content string, embedding pgvector.Vector) (sqlcgen.Memory, error) {
	return r.q.UpdateMemory(ctx, sqlcgen.UpdateMemoryParams{
		ID:        id,
		UserID:    userID,
		Content:   content,
		Embedding: embedding,
	})
}

func (r *repository) SearchMemories(ctx context.Context, userID pgtype.UUID, embedding pgvector.Vector, limit int32) ([]sqlcgen.SearchMemoriesByEmbeddingRow, error) {
	return r.q.SearchMemoriesByEmbedding(ctx, sqlcgen.SearchMemoriesByEmbeddingParams{
		UserID:  userID,
		Column2: embedding,
		Limit:   limit,
	})
}
