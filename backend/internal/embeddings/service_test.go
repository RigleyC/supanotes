package embeddings

import (
	"context"
	"errors"
	"testing"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/pgvector/pgvector-go"
)

type mockRepo struct {
	getRetryable    func(ctx context.Context, limit int32) ([]sqlcgen.GetRetryableEmbeddingsRow, error)
	updateStatus    func(ctx context.Context, id pgtype.UUID, status string) error
	upsertEmbedding func(ctx context.Context, noteID pgtype.UUID, embedding pgvector.Vector) error
}

func (m *mockRepo) GetRetryableEmbeddings(ctx context.Context, limit int32) ([]sqlcgen.GetRetryableEmbeddingsRow, error) {
	return m.getRetryable(ctx, limit)
}

func (m *mockRepo) UpdateNoteEmbeddingStatus(ctx context.Context, id pgtype.UUID, embeddingStatus string) error {
	return m.updateStatus(ctx, id, embeddingStatus)
}

func (m *mockRepo) UpsertNoteEmbedding(ctx context.Context, noteID pgtype.UUID, embedding pgvector.Vector) error {
	return m.upsertEmbedding(ctx, noteID, embedding)
}

type mockEmbedClient struct {
	gen func(ctx context.Context, text string) ([]float64, error)
}

func (m *mockEmbedClient) GenerateEmbedding(ctx context.Context, text string) ([]float64, error) {
	return m.gen(ctx, text)
}

func TestChunkText(t *testing.T) {
	t.Run("empty text returns nil", func(t *testing.T) {
		if got := chunkText("", 800, 100); got != nil {
			t.Errorf("expected nil, got %v", got)
		}
	})

	t.Run("short text returns single chunk", func(t *testing.T) {
		text := "hello world"
		chunks := chunkText(text, 800, 100)
		if len(chunks) != 1 || chunks[0] != text {
			t.Errorf("expected [%s], got %v", text, chunks)
		}
	})

	t.Run("long text splits into chunks", func(t *testing.T) {
		words := make([]string, 100)
		for i := range words {
			words[i] = "word"
		}
		text := ""
		for _, w := range words {
			text += w + " "
		}
		text = text[:len(text)-1]
		chunks := chunkText(text, 20, 5)
		if len(chunks) < 2 {
			t.Errorf("expected multiple chunks, got %d", len(chunks))
		}
	})
}

func TestProcessPending(t *testing.T) {
	t.Run("empty list succeeds", func(t *testing.T) {
		svc := &Service{
			repo: &mockRepo{
				getRetryable: func(ctx context.Context, limit int32) ([]sqlcgen.GetRetryableEmbeddingsRow, error) {
					return nil, nil
				},
			},
		}
		if err := svc.ProcessPending(context.Background()); err != nil {
			t.Errorf("expected nil, got %v", err)
		}
	})

	t.Run("repo error is propagated", func(t *testing.T) {
		svc := &Service{
			repo: &mockRepo{
				getRetryable: func(ctx context.Context, limit int32) ([]sqlcgen.GetRetryableEmbeddingsRow, error) {
					return nil, errors.New("db error")
				},
			},
		}
		if err := svc.ProcessPending(context.Background()); err == nil {
			t.Error("expected error, got nil")
		}
	})
}
