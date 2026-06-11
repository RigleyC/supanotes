package memories

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/pgvector/pgvector-go"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/pkg/llm"
)

type Service struct {
	repo    Repository
	embedCL *llm.EmbeddingClient
}

func NewService(repo Repository, embedCL *llm.EmbeddingClient) *Service {
	return &Service{repo: repo, embedCL: embedCL}
}

func (s *Service) GetMemories(ctx context.Context, userID pgtype.UUID, limit, offset int32) ([]sqlcgen.Memory, error) {
	return s.repo.GetMemories(ctx, userID, limit, offset)
}

func (s *Service) CreateMemory(ctx context.Context, userID pgtype.UUID, content string) (sqlcgen.Memory, error) {
	emb, err := s.embedCL.GenerateEmbedding(ctx, content)
	if err != nil {
		return sqlcgen.Memory{}, fmt.Errorf("memories: generate embedding: %w", err)
	}
	vec := pgvector.NewVector(float64ToFloat32(emb))
	return s.repo.CreateMemory(ctx, userID, content, vec)
}

func (s *Service) DeleteMemory(ctx context.Context, id, userID pgtype.UUID) error {
	return s.repo.DeleteMemory(ctx, id, userID)
}

func float64ToFloat32(src []float64) []float32 {
	dst := make([]float32, len(src))
	for i := range src {
		dst[i] = float32(src[i])
	}
	return dst
}
