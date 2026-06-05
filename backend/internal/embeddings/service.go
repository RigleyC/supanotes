package embeddings

import (
	"context"
	"log"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/pgvector/pgvector-go"
)

type Service struct {
	repo Repository
}

func NewService(repo Repository) *Service {
	return &Service{repo: repo}
}

// GenerateAndSave usa um stub no momento para gerar embeddings fake
func (s *Service) GenerateAndSave(ctx context.Context, noteID pgtype.UUID, content string) error {
	// Stub de embedding (Feature 5 integrará o OpenAI real)
	vec := make([]float32, 1536)
	for i := range vec {
		vec[i] = 0.01 // mock value
	}

	err := s.repo.UpsertNoteEmbedding(ctx, noteID, pgvector.NewVector(vec))
	if err != nil {
		s.repo.UpdateNoteEmbeddingStatus(context.Background(), noteID, "failed")
		return err
	}

	return s.repo.UpdateNoteEmbeddingStatus(ctx, noteID, "completed")
}

func (s *Service) ProcessPending(ctx context.Context) error {
	rows, err := s.repo.GetPendingEmbeddings(ctx, 50)
	if err != nil {
		return err
	}

	for _, row := range rows {
		err := s.GenerateAndSave(ctx, row.ID, row.Content)
		if err != nil {
			log.Printf("failed to process embedding for note %v: %v", row.ID, err)
			continue
		}
	}

	return nil
}
