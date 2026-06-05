package memories

import (
	"context"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/pgvector/pgvector-go"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

type Service struct {
	repo Repository
}

func NewService(repo Repository) *Service {
	return &Service{repo: repo}
}

func (s *Service) GetMemories(ctx context.Context, userID pgtype.UUID, limit, offset int32) ([]sqlcgen.Memory, error) {
	return s.repo.GetMemories(ctx, userID, limit, offset)
}

func (s *Service) CreateMemory(ctx context.Context, userID pgtype.UUID, content string) (sqlcgen.Memory, error) {
	// Stub para o embedding (Feature 5 conectará no OpenAI)
	vec := make([]float32, 1536)
	for i := range vec {
		vec[i] = 0.01 // mock value
	}

	return s.repo.CreateMemory(ctx, userID, content, pgvector.NewVector(vec))
}

func (s *Service) DeleteMemory(ctx context.Context, id, userID pgtype.UUID) error {
	return s.repo.DeleteMemory(ctx, id, userID)
}
