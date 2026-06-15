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
func (s *stubTasksRepo) CreateTaskCompletion(ctx context.Context, taskID pgtype.UUID, dueDate pgtype.Date) (sqlcgen.TaskCompletion, error) {
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

// Minimal stubQuerier for context tests (subset of sqlcgen.Querier).
type stubQuerier struct {
	searchByEmbedding func(ctx context.Context, arg sqlcgen.SearchNotesByEmbeddingParams) ([]sqlcgen.SearchNotesByEmbeddingRow, error)
	getSoul           func(ctx context.Context, userID pgtype.UUID) (sqlcgen.Soul, error)
	getMessages       func(ctx context.Context, arg sqlcgen.GetMessagesParams) ([]sqlcgen.Message, error)
	getRecentNotes    func(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.Note, error)
}

func (s *stubQuerier) SearchNotesByEmbedding(ctx context.Context, arg sqlcgen.SearchNotesByEmbeddingParams) ([]sqlcgen.SearchNotesByEmbeddingRow, error) {
	if s.searchByEmbedding != nil {
		return s.searchByEmbedding(ctx, arg)
	}
	panic("unimplemented")
}
func (s *stubQuerier) GetSoul(ctx context.Context, userID pgtype.UUID) (sqlcgen.Soul, error) {
	if s.getSoul != nil {
		return s.getSoul(ctx, userID)
	}
	panic("unimplemented")
}
func (s *stubQuerier) GetMessages(ctx context.Context, arg sqlcgen.GetMessagesParams) ([]sqlcgen.Message, error) {
	if s.getMessages != nil {
		return s.getMessages(ctx, arg)
	}
	panic("unimplemented")
}
func (s *stubQuerier) GetRecentNotes(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.Note, error) {
	if s.getRecentNotes != nil {
		return s.getRecentNotes(ctx, userID)
	}
	panic("unimplemented")
}

// remaining Querier methods (unused by context tests)
func (s *stubQuerier) AddTagToNote(context.Context, sqlcgen.AddTagToNoteParams) error      { panic("unimplemented") }
func (s *stubQuerier) AppendToInbox(context.Context, sqlcgen.AppendToInboxParams) (sqlcgen.Note, error) {
	panic("unimplemented")
}
func (s *stubQuerier) AppendToNoteContent(context.Context, sqlcgen.AppendToNoteContentParams) (sqlcgen.Note, error) {
	panic("unimplemented")
}
func (s *stubQuerier) CleanupOldMessages(context.Context) error          { panic("unimplemented") }
func (s *stubQuerier) CountNotes(context.Context, pgtype.UUID) (int64, error)         { panic("unimplemented") }
func (s *stubQuerier) CountTasks(context.Context, pgtype.UUID) (int64, error)         { panic("unimplemented") }
func (s *stubQuerier) CountOpenTasks(context.Context, pgtype.UUID) (int64, error)     { panic("unimplemented") }
func (s *stubQuerier) CountCompletedTasks(context.Context, pgtype.UUID) (int64, error) { panic("unimplemented") }
func (s *stubQuerier) CreateContext(context.Context, sqlcgen.CreateContextParams) (sqlcgen.Context, error) {
	panic("unimplemented")
}
func (s *stubQuerier) CreateDeviceToken(context.Context, sqlcgen.CreateDeviceTokenParams) (sqlcgen.DeviceToken, error) {
	panic("unimplemented")
}
func (s *stubQuerier) CreateMemory(context.Context, sqlcgen.CreateMemoryParams) (sqlcgen.Memory, error) {
	panic("unimplemented")
}
func (s *stubQuerier) CreateMessage(context.Context, sqlcgen.CreateMessageParams) (sqlcgen.Message, error) {
	panic("unimplemented")
}
func (s *stubQuerier) CreateNote(context.Context, sqlcgen.CreateNoteParams) (sqlcgen.Note, error) {
	panic("unimplemented")
}
func (s *stubQuerier) CreateNoteLink(context.Context, sqlcgen.CreateNoteLinkParams) error {
	panic("unimplemented")
}
func (s *stubQuerier) CreateRefreshToken(context.Context, sqlcgen.CreateRefreshTokenParams) (sqlcgen.RefreshToken, error) {
	panic("unimplemented")
}
func (s *stubQuerier) CreateRoutine(context.Context, sqlcgen.CreateRoutineParams) (sqlcgen.Routine, error) {
	panic("unimplemented")
}
func (s *stubQuerier) CreateRoutineLog(context.Context, sqlcgen.CreateRoutineLogParams) (sqlcgen.RoutineLog, error) {
	panic("unimplemented")
}
func (s *stubQuerier) CreateTag(context.Context, sqlcgen.CreateTagParams) (sqlcgen.Tag, error) {
	panic("unimplemented")
}
func (s *stubQuerier) CreateTask(context.Context, sqlcgen.CreateTaskParams) (sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubQuerier) CreateTaskCompletion(context.Context, sqlcgen.CreateTaskCompletionParams) (sqlcgen.TaskCompletion, error) {
	panic("unimplemented")
}
func (s *stubQuerier) CreateUser(context.Context, sqlcgen.CreateUserParams) (sqlcgen.User, error) {
	panic("unimplemented")
}
func (s *stubQuerier) CreateUserSettings(context.Context, sqlcgen.CreateUserSettingsParams) (sqlcgen.UserSetting, error) {
	panic("unimplemented")
}
func (s *stubQuerier) DeleteContext(context.Context, sqlcgen.DeleteContextParams) error     { panic("unimplemented") }
func (s *stubQuerier) DeleteDeviceToken(context.Context, sqlcgen.DeleteDeviceTokenParams) error {
	panic("unimplemented")
}
func (s *stubQuerier) DeleteMemory(context.Context, sqlcgen.DeleteMemoryParams) error      { panic("unimplemented") }
func (s *stubQuerier) DeleteNote(context.Context, sqlcgen.DeleteNoteParams) error           { panic("unimplemented") }
func (s *stubQuerier) DeleteSessionMessages(context.Context, sqlcgen.DeleteSessionMessagesParams) error {
	panic("unimplemented")
}
func (s *stubQuerier) DeleteTag(context.Context, sqlcgen.DeleteTagParams) error    { panic("unimplemented") }
func (s *stubQuerier) DeleteTask(context.Context, sqlcgen.DeleteTaskParams) error   { panic("unimplemented") }
func (s *stubQuerier) GetContexts(context.Context, pgtype.UUID) ([]sqlcgen.Context, error) { panic("unimplemented") }
func (s *stubQuerier) GetEnabledRoutines(context.Context) ([]sqlcgen.GetEnabledRoutinesRow, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetInboxNote(context.Context, pgtype.UUID) (sqlcgen.Note, error) { panic("unimplemented") }
func (s *stubQuerier) GetLatestBriefByType(context.Context, sqlcgen.GetLatestBriefByTypeParams) (sqlcgen.RoutineLog, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetLinkedNotes(context.Context, sqlcgen.GetLinkedNotesParams) ([]sqlcgen.Note, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetMemories(context.Context, sqlcgen.GetMemoriesParams) ([]sqlcgen.Memory, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetNoteByID(context.Context, sqlcgen.GetNoteByIDParams) (sqlcgen.Note, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetNotes(context.Context, sqlcgen.GetNotesParams) ([]sqlcgen.Note, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetRefreshToken(context.Context, string) (sqlcgen.RefreshToken, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetRetryableEmbeddings(context.Context, int32) ([]sqlcgen.GetRetryableEmbeddingsRow, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetRoutineLogsByUser(context.Context, sqlcgen.GetRoutineLogsByUserParams) ([]sqlcgen.RoutineLog, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetRoutinesByUser(context.Context, pgtype.UUID) ([]sqlcgen.Routine, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetSyncContexts(context.Context, sqlcgen.GetSyncContextsParams) ([]sqlcgen.Context, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetSyncNotes(context.Context, sqlcgen.GetSyncNotesParams) ([]sqlcgen.Note, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetSyncTags(context.Context, sqlcgen.GetSyncTagsParams) ([]sqlcgen.Tag, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetSyncTasks(context.Context, sqlcgen.GetSyncTasksParams) ([]sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetTags(context.Context, pgtype.UUID) ([]sqlcgen.Tag, error)          { panic("unimplemented") }
func (s *stubQuerier) GetTagsForNote(context.Context, pgtype.UUID) ([]sqlcgen.Tag, error)   { panic("unimplemented") }
func (s *stubQuerier) GetTaskByID(context.Context, sqlcgen.GetTaskByIDParams) (sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetTasks(context.Context, sqlcgen.GetTasksParams) ([]sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetTasksByNoteID(context.Context, sqlcgen.GetTasksByNoteIDParams) ([]sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetTodayTasks(context.Context, sqlcgen.GetTodayTasksParams) ([]sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetUserByEmail(context.Context, string) (sqlcgen.User, error)          { panic("unimplemented") }
func (s *stubQuerier) GetUserByID(context.Context, pgtype.UUID) (sqlcgen.User, error)        { panic("unimplemented") }
func (s *stubQuerier) GetUserSettings(context.Context, pgtype.UUID) (sqlcgen.UserSetting, error) {
	panic("unimplemented")
}
func (s *stubQuerier) HardDeleteExpiredContexts(context.Context) error { panic("unimplemented") }
func (s *stubQuerier) HardDeleteExpiredNotes(context.Context) error    { panic("unimplemented") }
func (s *stubQuerier) HardDeleteExpiredTasks(context.Context) error    { panic("unimplemented") }
func (s *stubQuerier) ListDeviceTokensByUser(context.Context, pgtype.UUID) ([]sqlcgen.DeviceToken, error) {
	panic("unimplemented")
}
func (s *stubQuerier) RemoveTagFromNote(context.Context, sqlcgen.RemoveTagFromNoteParams) error {
	panic("unimplemented")
}
func (s *stubQuerier) RevokeAllUserRefreshTokens(context.Context, pgtype.UUID) error { panic("unimplemented") }
func (s *stubQuerier) RevokeRefreshToken(context.Context, pgtype.UUID) error          { panic("unimplemented") }
func (s *stubQuerier) SearchMemoriesByEmbedding(context.Context, sqlcgen.SearchMemoriesByEmbeddingParams) ([]sqlcgen.SearchMemoriesByEmbeddingRow, error) {
	panic("unimplemented")
}
func (s *stubQuerier) SearchNotesFTS(context.Context, sqlcgen.SearchNotesFTSParams) ([]sqlcgen.SearchNotesFTSRow, error) {
	panic("unimplemented")
}
func (s *stubQuerier) SearchNotesHybrid(context.Context, sqlcgen.SearchNotesHybridParams) ([]sqlcgen.SearchNotesHybridRow, error) {
	panic("unimplemented")
}
func (s *stubQuerier) SearchNotesSemantic(context.Context, sqlcgen.SearchNotesSemanticParams) ([]sqlcgen.SearchNotesSemanticRow, error) {
	panic("unimplemented")
}
func (s *stubQuerier) SetInboxContent(context.Context, sqlcgen.SetInboxContentParams) (sqlcgen.Note, error) {
	panic("unimplemented")
}
func (s *stubQuerier) UpdateNote(context.Context, sqlcgen.UpdateNoteParams) (sqlcgen.Note, error) {
	panic("unimplemented")
}
func (s *stubQuerier) UpdateNoteEmbeddingStatus(context.Context, sqlcgen.UpdateNoteEmbeddingStatusParams) error {
	panic("unimplemented")
}
func (s *stubQuerier) UpdateRoutine(context.Context, sqlcgen.UpdateRoutineParams) (sqlcgen.Routine, error) {
	panic("unimplemented")
}
func (s *stubQuerier) UpdateTask(context.Context, sqlcgen.UpdateTaskParams) (sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubQuerier) UpdateUserSettings(context.Context, sqlcgen.UpdateUserSettingsParams) (sqlcgen.UserSetting, error) {
	panic("unimplemented")
}
func (s *stubQuerier) UpsertContext(context.Context, sqlcgen.UpsertContextParams) (sqlcgen.Context, error) {
	panic("unimplemented")
}
func (s *stubQuerier) UpsertNote(context.Context, sqlcgen.UpsertNoteParams) (sqlcgen.Note, error) {
	panic("unimplemented")
}
func (s *stubQuerier) UpsertNoteEmbedding(context.Context, sqlcgen.UpsertNoteEmbeddingParams) error {
	panic("unimplemented")
}
func (s *stubQuerier) UpsertSoul(context.Context, sqlcgen.UpsertSoulParams) (sqlcgen.Soul, error) {
	panic("unimplemented")
}
func (s *stubQuerier) UpsertTag(context.Context, sqlcgen.UpsertTagParams) (sqlcgen.Tag, error) {
	panic("unimplemented")
}
func (s *stubQuerier) UpsertTask(context.Context, sqlcgen.UpsertTaskParams) (sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubQuerier) UpdateRoutineLastRunAt(context.Context, pgtype.UUID) error            { panic("unimplemented") }
func (s *stubQuerier) UpsertTaskCompletion(context.Context, sqlcgen.UpsertTaskCompletionParams) error {
	panic("unimplemented")
}
func (s *stubQuerier) GetSyncTaskCompletions(context.Context, sqlcgen.GetSyncTaskCompletionsParams) ([]sqlcgen.TaskCompletion, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetSyncNoteTags(context.Context, pgtype.UUID) ([]sqlcgen.NoteTag, error) {
	panic("unimplemented")
}
func (s *stubQuerier) UpsertNoteTag(context.Context, sqlcgen.UpsertNoteTagParams) error     { panic("unimplemented") }
func (s *stubQuerier) GetSyncNoteLinks(context.Context, pgtype.UUID) ([]sqlcgen.NoteLink, error) {
	panic("unimplemented")
}
func (s *stubQuerier) UpsertNoteLink(context.Context, sqlcgen.UpsertNoteLinkParams) error   { panic("unimplemented") }

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
