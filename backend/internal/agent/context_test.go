package agent

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/pgvector/pgvector-go"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/tasks"
	"github.com/RigleyC/supanotes/pkg/llm"
)

type stubTasksRepo struct{}

func (s *stubTasksRepo) CreateTask(ctx context.Context, arg sqlcgen.CreateTaskParams) (sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubTasksRepo) GetTaskByID(ctx context.Context, id pgtype.UUID, userID pgtype.UUID) (sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubTasksRepo) GetTasks(ctx context.Context, arg sqlcgen.GetTasksParams) ([]sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubTasksRepo) UpdateTask(ctx context.Context, arg sqlcgen.UpdateTaskParams) (sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubTasksRepo) DeleteTask(ctx context.Context, id, userID pgtype.UUID) error {
	panic("unimplemented")
}
func (s *stubTasksRepo) GetTodayTasks(ctx context.Context, userID pgtype.UUID, upTo pgtype.Timestamptz) ([]sqlcgen.Task, error) {
	return nil, nil
}
func (s *stubTasksRepo) GetTasksByNoteID(ctx context.Context, userID pgtype.UUID, noteID pgtype.UUID) ([]sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubTasksRepo) CreateTaskCompletion(ctx context.Context, taskID pgtype.UUID, status string) (sqlcgen.TaskCompletion, error) {
	panic("unimplemented")
}
func (s *stubTasksRepo) CountTasks(ctx context.Context, userID pgtype.UUID) (int64, error) {
	panic("unimplemented")
}
func (s *stubTasksRepo) CountOpenTasks(ctx context.Context, userID pgtype.UUID) (int64, error) {
	panic("unimplemented")
}
func (s *stubTasksRepo) CountCompletedTasks(ctx context.Context, userID pgtype.UUID) (int64, error) {
	panic("unimplemented")
}

type stubMemRepo struct{}

func (m *stubMemRepo) GetMemories(ctx context.Context, userID pgtype.UUID, limit, offset int32) ([]sqlcgen.Memory, error) {
	return nil, nil
}
func (m *stubMemRepo) CreateMemory(ctx context.Context, userID pgtype.UUID, content string, embedding pgvector.Vector) (sqlcgen.Memory, error) {
	panic("unimplemented")
}
func (m *stubMemRepo) DeleteMemory(ctx context.Context, id, userID pgtype.UUID) error {
	panic("unimplemented")
}
func (m *stubMemRepo) SearchMemories(ctx context.Context, userID pgtype.UUID, embedding pgvector.Vector, limit int32) ([]sqlcgen.SearchMemoriesByEmbeddingRow, error) {
	return nil, nil
}

func TestContextBuilder_Build(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]any{
			"data": []map[string]any{
				{"embedding": make([]float64, 1536), "index": 0},
			},
		})
	}))
	defer srv.Close()

	q := &stubQuerier{
		searchByEmbedding: func(ctx context.Context, arg sqlcgen.SearchNotesByEmbeddingParams) ([]sqlcgen.SearchNotesByEmbeddingRow, error) {
			return nil, nil
		},
		getSoul: func(ctx context.Context, userID pgtype.UUID) (sqlcgen.Soul, error) {
			return sqlcgen.Soul{Personality: "test"}, nil
		},
		getMessages: func(ctx context.Context, arg sqlcgen.GetMessagesParams) ([]sqlcgen.Message, error) {
			return nil, nil
		},
		getRecentNotes: func(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.Note, error) {
			return nil, nil
		},
	}

	embedCL := llm.NewEmbeddingClient("test-key", srv.URL, "text-embedding-3-small")
	memRepo := &stubMemRepo{}
	tasksSvc := tasks.NewService(&stubTasksRepo{})

	cb := NewContextBuilder(q, tasksSvc, memRepo, embedCL)
	result, err := cb.Build(context.Background(), pgtype.UUID{}, pgtype.UUID{}, "test query")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result == "" {
		t.Fatal("expected non-empty context")
	}
}
