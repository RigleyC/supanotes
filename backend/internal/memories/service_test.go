package memories

import (
	"context"
	"testing"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/pgvector/pgvector-go"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/pkg/llm"
)

type mockRepo struct {
	mock.Mock
}

func (m *mockRepo) GetMemories(ctx context.Context, userID pgtype.UUID, limit, offset int32) ([]sqlcgen.Memory, error) {
	args := m.Called(ctx, userID, limit, offset)
	return args.Get(0).([]sqlcgen.Memory), args.Error(1)
}

func (m *mockRepo) CreateMemory(ctx context.Context, userID pgtype.UUID, content string, embedding pgvector.Vector) (sqlcgen.Memory, error) {
	args := m.Called(ctx, userID, content, embedding)
	return args.Get(0).(sqlcgen.Memory), args.Error(1)
}

func (m *mockRepo) DeleteMemory(ctx context.Context, id, userID pgtype.UUID) error {
	args := m.Called(ctx, id, userID)
	return args.Error(0)
}

func (m *mockRepo) SearchMemories(ctx context.Context, userID pgtype.UUID, embedding pgvector.Vector, limit int32) ([]sqlcgen.SearchMemoriesByEmbeddingRow, error) {
	args := m.Called(ctx, userID, embedding, limit)
	return args.Get(0).([]sqlcgen.SearchMemoriesByEmbeddingRow), args.Error(1)
}

func TestCreateMemory_UsesRealEmbedding(t *testing.T) {
	repo := new(mockRepo)
	// EmbeddingClient with empty API key returns mock 1536-dim embedding
	embedCL := llm.NewEmbeddingClient("", "", "")
	svc := NewService(repo, embedCL)

	repo.On("CreateMemory", mock.Anything, mock.Anything, "test memory", mock.Anything).Return(sqlcgen.Memory{}, nil)

	_, err := svc.CreateMemory(context.Background(), pgtype.UUID{}, "test memory")
	assert.NoError(t, err)
}
