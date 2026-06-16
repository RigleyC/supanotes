package tools

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/notes"
	"github.com/RigleyC/supanotes/pkg/llm"
)

// stubQuerier panics on any method call.
type stubQuerier struct {
	searchByEmbedding func(ctx context.Context, arg sqlcgen.SearchNotesByEmbeddingParams) ([]sqlcgen.SearchNotesByEmbeddingRow, error)
	createNoteLink    func(ctx context.Context, arg sqlcgen.CreateNoteLinkParams) error
	getNoteByID       func(ctx context.Context, arg sqlcgen.GetNoteByIDParams) (sqlcgen.Note, error)
	getSoul           func(ctx context.Context, userID pgtype.UUID) (sqlcgen.Soul, error)
	getMessages       func(ctx context.Context, arg sqlcgen.GetMessagesParams) ([]sqlcgen.Message, error)
	getRecentNotes    func(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.Note, error)
	getInboxNote      func(ctx context.Context, userID pgtype.UUID) (sqlcgen.Note, error)
	createNote        func(ctx context.Context, arg sqlcgen.CreateNoteParams) (sqlcgen.Note, error)
	setInboxContent   func(ctx context.Context, arg sqlcgen.SetInboxContentParams) (sqlcgen.Note, error)
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

func (s *stubQuerier) CreateNoteLink(ctx context.Context, arg sqlcgen.CreateNoteLinkParams) error {
	if s.createNoteLink != nil {
		return s.createNoteLink(ctx, arg)
	}
	panic("unimplemented")
}

func (s *stubQuerier) GetNoteByID(ctx context.Context, arg sqlcgen.GetNoteByIDParams) (sqlcgen.Note, error) {
	if s.getNoteByID != nil {
		return s.getNoteByID(ctx, arg)
	}
	panic("unimplemented")
}

func (s *stubQuerier) SearchNotesByEmbedding(ctx context.Context, arg sqlcgen.SearchNotesByEmbeddingParams) ([]sqlcgen.SearchNotesByEmbeddingRow, error) {
	if s.searchByEmbedding != nil {
		return s.searchByEmbedding(ctx, arg)
	}
	panic("unimplemented")
}

// remaining Querier methods
func (s *stubQuerier) AddTagToNote(ctx context.Context, arg sqlcgen.AddTagToNoteParams) error {
	panic("unimplemented")
}
func (s *stubQuerier) AppendToInbox(ctx context.Context, arg sqlcgen.AppendToInboxParams) (sqlcgen.Note, error) {
	panic("unimplemented")
}
func (s *stubQuerier) AppendToNoteContent(ctx context.Context, arg sqlcgen.AppendToNoteContentParams) (sqlcgen.Note, error) {
	panic("unimplemented")
}
func (s *stubQuerier) CleanupOldMessages(ctx context.Context) error { panic("unimplemented") }
func (s *stubQuerier) CountNotes(ctx context.Context, userID pgtype.UUID) (int64, error) {
	panic("unimplemented")
}
func (s *stubQuerier) CountTasks(ctx context.Context, userID pgtype.UUID) (int64, error) {
	panic("unimplemented")
}
func (s *stubQuerier) CountOpenTasks(ctx context.Context, userID pgtype.UUID) (int64, error) {
	panic("unimplemented")
}
func (s *stubQuerier) CountCompletedTasks(ctx context.Context, userID pgtype.UUID) (int64, error) {
	panic("unimplemented")
}
func (s *stubQuerier) CreateContext(ctx context.Context, arg sqlcgen.CreateContextParams) (sqlcgen.Context, error) {
	panic("unimplemented")
}
func (s *stubQuerier) CreateDeviceToken(ctx context.Context, arg sqlcgen.CreateDeviceTokenParams) (sqlcgen.DeviceToken, error) {
	panic("unimplemented")
}
func (s *stubQuerier) CreateMemory(ctx context.Context, arg sqlcgen.CreateMemoryParams) (sqlcgen.Memory, error) {
	panic("unimplemented")
}
func (s *stubQuerier) CreateMessage(ctx context.Context, arg sqlcgen.CreateMessageParams) (sqlcgen.Message, error) {
	panic("unimplemented")
}
func (s *stubQuerier) CreateNote(ctx context.Context, arg sqlcgen.CreateNoteParams) (sqlcgen.Note, error) {
	if s.createNote != nil {
		return s.createNote(ctx, arg)
	}
	panic("unimplemented")
}
func (s *stubQuerier) CreateNoteShare(_ context.Context, _ sqlcgen.CreateNoteShareParams) (sqlcgen.NoteShare, error) {
	return sqlcgen.NoteShare{}, nil
}
func (s *stubQuerier) CreateRefreshToken(ctx context.Context, arg sqlcgen.CreateRefreshTokenParams) (sqlcgen.RefreshToken, error) {
	panic("unimplemented")
}
func (s *stubQuerier) CreateRoutine(ctx context.Context, arg sqlcgen.CreateRoutineParams) (sqlcgen.Routine, error) {
	panic("unimplemented")
}
func (s *stubQuerier) CreateRoutineLog(ctx context.Context, arg sqlcgen.CreateRoutineLogParams) (sqlcgen.RoutineLog, error) {
	panic("unimplemented")
}
func (s *stubQuerier) CreateTag(ctx context.Context, arg sqlcgen.CreateTagParams) (sqlcgen.Tag, error) {
	panic("unimplemented")
}
func (s *stubQuerier) CreateTask(ctx context.Context, arg sqlcgen.CreateTaskParams) (sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubQuerier) CreateTaskCompletion(ctx context.Context, arg sqlcgen.CreateTaskCompletionParams) (sqlcgen.TaskCompletion, error) {
	panic("unimplemented")
}
func (s *stubQuerier) CreateUser(ctx context.Context, arg sqlcgen.CreateUserParams) (sqlcgen.User, error) {
	panic("unimplemented")
}
func (s *stubQuerier) CreateUserSettings(ctx context.Context, arg sqlcgen.CreateUserSettingsParams) (sqlcgen.UserSetting, error) {
	panic("unimplemented")
}
func (s *stubQuerier) DeleteContext(ctx context.Context, arg sqlcgen.DeleteContextParams) error {
	panic("unimplemented")
}
func (s *stubQuerier) DeleteDeviceToken(ctx context.Context, arg sqlcgen.DeleteDeviceTokenParams) error {
	panic("unimplemented")
}
func (s *stubQuerier) DeleteMemory(ctx context.Context, arg sqlcgen.DeleteMemoryParams) error {
	panic("unimplemented")
}
func (s *stubQuerier) DeleteNoteShare(ctx context.Context, arg sqlcgen.DeleteNoteShareParams) error {
	return nil
}
func (s *stubQuerier) DeleteNote(ctx context.Context, arg sqlcgen.DeleteNoteParams) error {
	panic("unimplemented")
}
func (s *stubQuerier) DeleteSessionMessages(ctx context.Context, arg sqlcgen.DeleteSessionMessagesParams) error {
	panic("unimplemented")
}
func (s *stubQuerier) DeleteTag(ctx context.Context, arg sqlcgen.DeleteTagParams) error {
	panic("unimplemented")
}
func (s *stubQuerier) DeleteTask(ctx context.Context, arg sqlcgen.DeleteTaskParams) error {
	panic("unimplemented")
}
func (s *stubQuerier) GetContexts(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.Context, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetEnabledRoutines(ctx context.Context) ([]sqlcgen.GetEnabledRoutinesRow, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetInboxNote(ctx context.Context, userID pgtype.UUID) (sqlcgen.Note, error) {
	if s.getInboxNote != nil {
		return s.getInboxNote(ctx, userID)
	}
	panic("unimplemented")
}
func (s *stubQuerier) GetLatestBriefByType(ctx context.Context, arg sqlcgen.GetLatestBriefByTypeParams) (sqlcgen.RoutineLog, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetLinkedNotes(ctx context.Context, arg sqlcgen.GetLinkedNotesParams) ([]sqlcgen.Note, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetMemories(ctx context.Context, arg sqlcgen.GetMemoriesParams) ([]sqlcgen.Memory, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetNotes(ctx context.Context, arg sqlcgen.GetNotesParams) ([]sqlcgen.Note, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetNoteShareForUser(ctx context.Context, arg sqlcgen.GetNoteShareForUserParams) (sqlcgen.NoteShare, error) {
	return sqlcgen.NoteShare{}, nil
}
func (s *stubQuerier) GetNoteShares(ctx context.Context, noteID pgtype.UUID) ([]sqlcgen.GetNoteSharesRow, error) {
	return nil, nil
}
func (s *stubQuerier) GetRefreshToken(ctx context.Context, tokenHash string) (sqlcgen.RefreshToken, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetRetryableEmbeddings(ctx context.Context, limit int32) ([]sqlcgen.GetRetryableEmbeddingsRow, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetRoutineLogsByUser(ctx context.Context, arg sqlcgen.GetRoutineLogsByUserParams) ([]sqlcgen.RoutineLog, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetRoutinesByUser(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.Routine, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetSyncContexts(ctx context.Context, arg sqlcgen.GetSyncContextsParams) ([]sqlcgen.Context, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetSyncNotes(ctx context.Context, arg sqlcgen.GetSyncNotesParams) ([]sqlcgen.GetSyncNotesRow, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetSyncTags(ctx context.Context, arg sqlcgen.GetSyncTagsParams) ([]sqlcgen.Tag, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetSyncTasks(ctx context.Context, arg sqlcgen.GetSyncTasksParams) ([]sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetTags(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.Tag, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetTagsForNote(ctx context.Context, noteID pgtype.UUID) ([]sqlcgen.Tag, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetTaskByID(ctx context.Context, arg sqlcgen.GetTaskByIDParams) (sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetTasks(ctx context.Context, arg sqlcgen.GetTasksParams) ([]sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetTasksByNoteID(ctx context.Context, arg sqlcgen.GetTasksByNoteIDParams) ([]sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetTodayTasks(ctx context.Context, arg sqlcgen.GetTodayTasksParams) ([]sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetUserByEmail(ctx context.Context, email string) (sqlcgen.User, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetUserByID(ctx context.Context, id pgtype.UUID) (sqlcgen.User, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetUserSettings(ctx context.Context, userID pgtype.UUID) (sqlcgen.UserSetting, error) {
	panic("unimplemented")
}
func (s *stubQuerier) HardDeleteExpiredContexts(ctx context.Context) error { panic("unimplemented") }
func (s *stubQuerier) HardDeleteExpiredNotes(ctx context.Context) error    { panic("unimplemented") }
func (s *stubQuerier) HardDeleteExpiredTasks(ctx context.Context) error    { panic("unimplemented") }
func (s *stubQuerier) ListDeviceTokensByUser(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.DeviceToken, error) {
	panic("unimplemented")
}
func (s *stubQuerier) RemoveTagFromNote(ctx context.Context, arg sqlcgen.RemoveTagFromNoteParams) error {
	panic("unimplemented")
}
func (s *stubQuerier) RevokeAllUserRefreshTokens(ctx context.Context, userID pgtype.UUID) error {
	panic("unimplemented")
}
func (s *stubQuerier) RevokeRefreshToken(ctx context.Context, id pgtype.UUID) error {
	panic("unimplemented")
}
func (s *stubQuerier) SearchMemoriesByEmbedding(ctx context.Context, arg sqlcgen.SearchMemoriesByEmbeddingParams) ([]sqlcgen.SearchMemoriesByEmbeddingRow, error) {
	panic("unimplemented")
}
func (s *stubQuerier) SearchNotesFTS(ctx context.Context, arg sqlcgen.SearchNotesFTSParams) ([]sqlcgen.SearchNotesFTSRow, error) {
	panic("unimplemented")
}
func (s *stubQuerier) SearchNotesHybrid(ctx context.Context, arg sqlcgen.SearchNotesHybridParams) ([]sqlcgen.SearchNotesHybridRow, error) {
	panic("unimplemented")
}
func (s *stubQuerier) SearchNotesSemantic(ctx context.Context, arg sqlcgen.SearchNotesSemanticParams) ([]sqlcgen.SearchNotesSemanticRow, error) {
	panic("unimplemented")
}
func (s *stubQuerier) SetInboxContent(ctx context.Context, arg sqlcgen.SetInboxContentParams) (sqlcgen.Note, error) {
	if s.setInboxContent != nil {
		return s.setInboxContent(ctx, arg)
	}
	panic("unimplemented")
}
func (s *stubQuerier) UpdateNote(ctx context.Context, arg sqlcgen.UpdateNoteParams) (sqlcgen.Note, error) {
	panic("unimplemented")
}
func (s *stubQuerier) UpdateNoteEmbeddingStatus(ctx context.Context, arg sqlcgen.UpdateNoteEmbeddingStatusParams) error {
	panic("unimplemented")
}
func (s *stubQuerier) UpdateRoutine(ctx context.Context, arg sqlcgen.UpdateRoutineParams) (sqlcgen.Routine, error) {
	panic("unimplemented")
}
func (s *stubQuerier) UpdateTask(ctx context.Context, arg sqlcgen.UpdateTaskParams) (sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubQuerier) UpdateUserSettings(ctx context.Context, arg sqlcgen.UpdateUserSettingsParams) (sqlcgen.UserSetting, error) {
	panic("unimplemented")
}
func (s *stubQuerier) UpsertContext(ctx context.Context, arg sqlcgen.UpsertContextParams) (sqlcgen.Context, error) {
	panic("unimplemented")
}
func (s *stubQuerier) UpsertNote(ctx context.Context, arg sqlcgen.UpsertNoteParams) (sqlcgen.Note, error) {
	panic("unimplemented")
}
func (s *stubQuerier) UpsertNoteEmbedding(ctx context.Context, arg sqlcgen.UpsertNoteEmbeddingParams) error {
	panic("unimplemented")
}
func (s *stubQuerier) UpsertSoul(ctx context.Context, arg sqlcgen.UpsertSoulParams) (sqlcgen.Soul, error) {
	panic("unimplemented")
}
func (s *stubQuerier) UpsertTag(ctx context.Context, arg sqlcgen.UpsertTagParams) (sqlcgen.Tag, error) {
	panic("unimplemented")
}
func (s *stubQuerier) UpsertTask(ctx context.Context, arg sqlcgen.UpsertTaskParams) (sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubQuerier) UpdateRoutineLastRunAt(ctx context.Context, id pgtype.UUID) error {
	panic("unimplemented")
}

func (s *stubQuerier) UpsertTaskCompletion(ctx context.Context, arg sqlcgen.UpsertTaskCompletionParams) error {
	panic("unimplemented")
}

func (s *stubQuerier) GetSyncTaskCompletions(ctx context.Context, arg sqlcgen.GetSyncTaskCompletionsParams) ([]sqlcgen.TaskCompletion, error) {
	panic("unimplemented")
}
func (s *stubQuerier) GetSyncNoteTags(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.NoteTag, error) {
	panic("unimplemented")
}
func (s *stubQuerier) UpsertNoteTag(ctx context.Context, arg sqlcgen.UpsertNoteTagParams) error {
	panic("unimplemented")
}
func (s *stubQuerier) GetSyncNoteLinks(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.NoteLink, error) {
	panic("unimplemented")
}
func (s *stubQuerier) UpsertNoteLink(ctx context.Context, arg sqlcgen.UpsertNoteLinkParams) error {
	panic("unimplemented")
}

var _ sqlcgen.Querier = (*stubQuerier)(nil)

func TestSearchNotesTool_Execute(t *testing.T) {
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
			return []sqlcgen.SearchNotesByEmbeddingRow{
				{
					ID:         pgtype.UUID{Bytes: [16]byte{1}, Valid: true},
					Title:      pgtype.Text{String: "Test Note", Valid: true},
					Content:    "content here",
					Similarity: 85,
				},
			}, nil
		},
	}

	embedCL := llm.NewEmbeddingClient("test-key", srv.URL, "text-embedding-3-small")
	tool := &SearchNotesTool{q: q, embedCL: embedCL}

	result, err := tool.Execute(context.Background(), pgtype.UUID{}, `{"query":"test query"}`)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result == "" {
		t.Fatal("expected non-empty result")
	}
}

func TestSearchNotesTool_EmptyResults(t *testing.T) {
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
	}

	embedCL := llm.NewEmbeddingClient("test-key", srv.URL, "text-embedding-3-small")
	tool := &SearchNotesTool{q: q, embedCL: embedCL}

	result, err := tool.Execute(context.Background(), pgtype.UUID{}, `{"query":"nothing"}`)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result != "No matching notes found" {
		t.Fatalf("expected 'No matching notes found', got %q", result)
	}
}

func TestLinkNotesTool_Execute(t *testing.T) {
	q := &stubQuerier{
		createNoteLink: func(ctx context.Context, arg sqlcgen.CreateNoteLinkParams) error {
			return nil
		},
		getNoteByID: func(ctx context.Context, arg sqlcgen.GetNoteByIDParams) (sqlcgen.Note, error) {
			return sqlcgen.Note{
				ID:     arg.ID,
				UserID: arg.UserID,
			}, nil
		},
	}
	// notesSvc backed by the mock querier; NewService expects notes.Repository
	// which wraps sqlcgen.Querier. Use a notesService that delegates GetNoteByID
	// through the stub querier.
	notesSvc := newMockNotesService(q)
	tool := &LinkNotesTool{q: q, notesSvc: notesSvc}

	result, err := tool.Execute(context.Background(), pgtype.UUID{Bytes: [16]byte{1}, Valid: true}, `{"source_id":"00000000-0000-0000-0000-000000000001","target_id":"00000000-0000-0000-0000-000000000002"}`)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result == "" {
		t.Fatal("expected non-empty result")
	}
}

func TestLinkNotesTool_InvalidUUID(t *testing.T) {
	tool := &LinkNotesTool{}
	_, err := tool.Execute(context.Background(), pgtype.UUID{}, `{"source_id":"not-a-uuid","target_id":"00000000-0000-0000-0000-000000000002"}`)
	if err == nil {
		t.Fatal("expected error for invalid UUID")
	}
}

func TestLinkNotesTool_SourceNotFound(t *testing.T) {
	q := &stubQuerier{
		getNoteByID: func(ctx context.Context, arg sqlcgen.GetNoteByIDParams) (sqlcgen.Note, error) {
			return sqlcgen.Note{}, notes.ErrNoteNotFound
		},
		createNoteLink: func(ctx context.Context, arg sqlcgen.CreateNoteLinkParams) error {
			t.Fatal("should not be called")
			return nil
		},
	}
	notesSvc := newMockNotesService(q)
	tool := &LinkNotesTool{q: q, notesSvc: notesSvc}
	_, err := tool.Execute(context.Background(), pgtype.UUID{}, `{"source_id":"00000000-0000-0000-0000-000000000001","target_id":"00000000-0000-0000-0000-000000000002"}`)
	if err == nil {
		t.Fatal("expected error for missing source note")
	}
}

// newMockNotesService creates a notes.Service that uses a stubQuerier
func newMockNotesService(q sqlcgen.Querier) *notes.Service {
	return notes.NewService(&mockNotesRepo{q: q}, nil)
}

type mockNotesRepo struct {
	q sqlcgen.Querier
}

func (m *mockNotesRepo) WithQuerier(q sqlcgen.Querier) notes.Repository {
	return &mockNotesRepo{q: q}
}

func (m *mockNotesRepo) CreateNote(ctx context.Context, arg sqlcgen.CreateNoteParams) (sqlcgen.Note, error) {
	return m.q.CreateNote(ctx, arg)
}
func (m *mockNotesRepo) GetNoteByID(ctx context.Context, id pgtype.UUID, userID pgtype.UUID) (sqlcgen.Note, error) {
	return m.q.GetNoteByID(ctx, sqlcgen.GetNoteByIDParams{ID: id, UserID: userID})
}
func (m *mockNotesRepo) UpdateNote(ctx context.Context, arg sqlcgen.UpdateNoteParams) (sqlcgen.Note, error) {
	panic("unimplemented")
}
func (m *mockNotesRepo) DeleteNote(ctx context.Context, id pgtype.UUID, userID pgtype.UUID) error {
	panic("unimplemented")
}
func (m *mockNotesRepo) GetNotes(ctx context.Context, arg sqlcgen.GetNotesParams) ([]sqlcgen.Note, error) {
	panic("unimplemented")
}
func (m *mockNotesRepo) GetInboxNote(ctx context.Context, userID pgtype.UUID) (sqlcgen.Note, error) {
	return m.q.GetInboxNote(ctx, userID)
}
func (m *mockNotesRepo) AppendToInbox(ctx context.Context, arg sqlcgen.AppendToInboxParams) (sqlcgen.Note, error) {
	return m.q.AppendToInbox(ctx, arg)
}
func (m *mockNotesRepo) SetInboxContent(ctx context.Context, arg sqlcgen.SetInboxContentParams) (sqlcgen.Note, error) {
	return m.q.SetInboxContent(ctx, arg)
}
func (m *mockNotesRepo) AppendToNoteContent(ctx context.Context, arg sqlcgen.AppendToNoteContentParams) (sqlcgen.Note, error) {
	return m.q.AppendToNoteContent(ctx, arg)
}
func (m *mockNotesRepo) CountNotes(ctx context.Context, userID pgtype.UUID) (int64, error) {
	panic("unimplemented")
}

func (m *mockNotesRepo) GetUserByEmail(ctx context.Context, email string) (sqlcgen.User, error) {
	panic("unimplemented")
}

func (m *mockNotesRepo) CreateNoteShare(ctx context.Context, arg sqlcgen.CreateNoteShareParams) (sqlcgen.NoteShare, error) {
	panic("unimplemented")
}

func (m *mockNotesRepo) GetNoteShares(ctx context.Context, noteID pgtype.UUID) ([]sqlcgen.GetNoteSharesRow, error) {
	panic("unimplemented")
}

func (m *mockNotesRepo) DeleteNoteShare(ctx context.Context, arg sqlcgen.DeleteNoteShareParams) error {
	panic("unimplemented")
}

func TestGetNoteTool_Execute(t *testing.T) {
	q := &stubQuerier{
		getNoteByID: func(ctx context.Context, arg sqlcgen.GetNoteByIDParams) (sqlcgen.Note, error) {
			return sqlcgen.Note{
				ID:      arg.ID,
				UserID:  arg.UserID,
				Title:   pgtype.Text{String: "My Test Note", Valid: true},
				Content: "Hello world this is note content",
			}, nil
		},
	}
	notesSvc := newMockNotesService(q)
	tool := &GetNoteTool{notesSvc: notesSvc}

	result, err := tool.Execute(context.Background(), pgtype.UUID{Bytes: [16]byte{1}, Valid: true}, `{"note_id":"00000000-0000-0000-0000-000000000001"}`)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	expected := "Note [00000000-0000-0000-0000-000000000001] My Test Note:\nHello world this is note content"
	if result != expected {
		t.Fatalf("expected:\n%q\ngot:\n%q", expected, result)
	}
}

func TestGetNoteTool_InvalidUUID(t *testing.T) {
	tool := &GetNoteTool{}
	_, err := tool.Execute(context.Background(), pgtype.UUID{}, `{"note_id":"not-a-uuid"}`)
	if err == nil {
		t.Fatal("expected error for invalid UUID")
	}
}

func TestApplyInboxOrganizationTool_Execute(t *testing.T) {
	// [16]byte{15: 1} = last byte=1 → UUID string "00000000-0000-0000-0000-000000000001"
	inboxID := pgtype.UUID{Bytes: [16]byte{15: 1}, Valid: true}
	q := &stubQuerier{
		getInboxNote: func(ctx context.Context, userID pgtype.UUID) (sqlcgen.Note, error) {
			return sqlcgen.Note{
				ID:      inboxID,
				UserID:  userID,
				IsInbox: true,
				Content: "snippet 1\n\nsnippet 2",
			}, nil
		},
		createNote: func(ctx context.Context, arg sqlcgen.CreateNoteParams) (sqlcgen.Note, error) {
			if arg.Content != "snippet 1" {
				t.Fatalf("expected create note content to be 'snippet 1', got %q", arg.Content)
			}
			return sqlcgen.Note{}, nil
		},
		setInboxContent: func(ctx context.Context, arg sqlcgen.SetInboxContentParams) (sqlcgen.Note, error) {
			if arg.Content != "snippet 2" {
				t.Fatalf("expected set inbox content to be 'snippet 2', got %q", arg.Content)
			}
			return sqlcgen.Note{}, nil
		},
	}
	notesSvc := newMockNotesService(q)
	tool := &ApplyInboxOrganizationTool{notesSvc: notesSvc}

	argsJSON := `{"items":[{"item_id":"00000000-0000-0000-0000-000000000001-0","original_snippet":"snippet 1","destination_type":"new_note","destination_title":"New Note Title","accepted":true}]}`
	result, err := tool.Execute(context.Background(), pgtype.UUID{Bytes: [16]byte{2}, Valid: true}, argsJSON)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result != "Inbox organization plan applied successfully" {
		t.Fatalf("expected success message, got %q", result)
	}
}
