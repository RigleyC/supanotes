package memories

import (
	"context"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/pgvector/pgvector-go"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

type Repository interface {
	GetMemories(ctx context.Context, userID pgtype.UUID, limit, offset int32) ([]sqlcgen.Memory, error)
	CreateMemory(ctx context.Context, userID pgtype.UUID, content string, embedding pgvector.Vector) (sqlcgen.Memory, error)
	DeleteMemory(ctx context.Context, id, userID pgtype.UUID) error
}

type repository struct {
	q sqlcgen.Querier
}

func NewRepository(q sqlcgen.Querier) Repository {
	return &repository{q: q}
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
