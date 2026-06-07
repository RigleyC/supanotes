package embeddings

import (
	"context"
	"fmt"
	"log"

	"github.com/jackc/pgx/v5/pgtype"
)

type Service struct {
	repo Repository
}

func NewService(repo Repository) *Service {
	return &Service{repo: repo}
}

// GenerateAndSave is a stub — no real embedding API configured yet.
func (s *Service) GenerateAndSave(ctx context.Context, noteID pgtype.UUID, content string) error {
	return fmt.Errorf("embeddings: service not configured — no real embedding API available")
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
