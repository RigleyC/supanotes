package embeddings

import (
	"context"
	"fmt"
	"log"
	"strings"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/pgvector/pgvector-go"

	"github.com/RigleyC/supanotes/pkg/llm"
)

type Service struct {
	repo    Repository
	embedCL *llm.EmbeddingClient
}

func NewService(repo Repository, embedCL *llm.EmbeddingClient) *Service {
	return &Service{repo: repo, embedCL: embedCL}
}

const (
	chunkSize    = 800
	chunkOverlap = 100
)

func (s *Service) GenerateAndSave(ctx context.Context, noteID pgtype.UUID, content string) error {
	chunks := chunkText(content, chunkSize, chunkOverlap)
	if len(chunks) == 0 {
		return s.repo.UpdateNoteEmbeddingStatus(ctx, noteID, "done")
	}

	var sum []float64
	for i, chunk := range chunks {
		emb, err := s.embedCL.GenerateEmbedding(ctx, chunk)
		if err != nil {
			return fmt.Errorf("generate embedding for chunk %d: %w", i, err)
		}
		if sum == nil {
			sum = make([]float64, len(emb))
		}
		for j := range emb {
			sum[j] += emb[j]
		}
	}

	avg := make([]float32, len(sum))
	count := float64(len(chunks))
	for i := range sum {
		avg[i] = float32(sum[i] / count)
	}

	if err := s.repo.UpsertNoteEmbedding(ctx, noteID, pgvector.NewVector(avg)); err != nil {
		return fmt.Errorf("upsert embedding: %w", err)
	}
	return s.repo.UpdateNoteEmbeddingStatus(ctx, noteID, "done")
}

func (s *Service) ProcessPending(ctx context.Context) error {
	rows, err := s.repo.GetRetryableEmbeddings(ctx, 50)
	if err != nil {
		return err
	}
	for _, row := range rows {
		if err := s.GenerateAndSave(ctx, row.ID, row.Content); err != nil {
			log.Printf("failed to process embedding for note %v: %v", row.ID, err)
			_ = s.repo.UpdateNoteEmbeddingStatus(ctx, row.ID, "failed")
			continue
		}
	}
	return nil
}

func chunkText(text string, size, overlap int) []string {
	words := strings.Fields(text)
	if len(words) == 0 {
		return nil
	}
	if len(words) <= size {
		return []string{text}
	}
	var chunks []string
	for i := 0; i < len(words); i += size - overlap {
		end := i + size
		if end > len(words) {
			end = len(words)
		}
		chunks = append(chunks, strings.Join(words[i:end], " "))
	}
	return chunks
}
