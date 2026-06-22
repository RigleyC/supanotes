package agent

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/pgvector/pgvector-go"

	"github.com/RigleyC/supanotes/internal/agent/tools"
	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/memories"
	"github.com/RigleyC/supanotes/internal/tasks"
	"github.com/RigleyC/supanotes/pkg/llm"
	"github.com/RigleyC/supanotes/pkg/uid"
)

type stubLoopRepo struct {
	deletedUserID    pgtype.UUID
	deletedSessionID pgtype.UUID
	deleteErr        error
}

func (s *stubLoopRepo) GetMessages(ctx context.Context, userID, sessionID pgtype.UUID, limit, offset int32) ([]sqlcgen.Message, error) {
	return nil, nil
}
func (s *stubLoopRepo) CreateMessage(ctx context.Context, userID, sessionID pgtype.UUID, role, content string, toolCalls []byte, toolCallID *string) (sqlcgen.Message, error) {
	return sqlcgen.Message{}, nil
}
func (s *stubLoopRepo) DeleteSessionMessages(ctx context.Context, userID, sessionID pgtype.UUID) error {
	s.deletedUserID = userID
	s.deletedSessionID = sessionID
	return s.deleteErr
}
func (s *stubLoopRepo) CountNotes(ctx context.Context, userID pgtype.UUID) (int64, error) {
	return 0, nil
}
func (s *stubLoopRepo) CountTasks(ctx context.Context, userID pgtype.UUID) (int64, error) {
	return 0, nil
}
func (s *stubLoopRepo) CountOpenTasks(ctx context.Context, userID pgtype.UUID) (int64, error) {
	return 0, nil
}
func (s *stubLoopRepo) CountCompletedTasks(ctx context.Context, userID pgtype.UUID) (int64, error) {
	return 0, nil
}
func (s *stubLoopRepo) CreatePendingToolConfirmation(ctx context.Context, userID, sessionID pgtype.UUID, toolName, argsJSON string) (sqlcgen.PendingToolConfirmation, error) {
	return sqlcgen.PendingToolConfirmation{}, nil
}
func (s *stubLoopRepo) GetPendingToolConfirmation(ctx context.Context, id, userID pgtype.UUID) (sqlcgen.PendingToolConfirmation, error) {
	return sqlcgen.PendingToolConfirmation{}, nil
}
func (s *stubLoopRepo) ResolvePendingToolConfirmation(ctx context.Context, id, userID pgtype.UUID, status string) (sqlcgen.PendingToolConfirmation, error) {
	return sqlcgen.PendingToolConfirmation{}, nil
}

func TestLoopResetSessionDeletesSessionMessages(t *testing.T) {
	repo := &stubLoopRepo{}
	loop := NewLoop(repo, nil, nil, nil)
	userID := pgtype.UUID{Bytes: [16]byte{1}, Valid: true}
	sessionID := "00000000-0000-0000-0000-000000000001"

	if err := loop.ResetSession(context.Background(), userID, sessionID); err != nil {
		t.Fatalf("ResetSession: %v", err)
	}

	if repo.deletedUserID != userID {
		t.Fatalf("deleted user id: want %v, got %v", userID, repo.deletedUserID)
	}
	wantSessionID := pgtype.UUID{Bytes: [16]byte{15: 1}, Valid: true}
	if repo.deletedSessionID != wantSessionID {
		t.Fatalf("deleted session id: want %v, got %v", wantSessionID, repo.deletedSessionID)
	}
}

type stubLoopLLMClient struct {
	response  *llm.Response
	responses []*llm.Response
	errors    []error
	requests  []llm.Request
}

func (s *stubLoopLLMClient) Complete(ctx context.Context, req llm.Request) (*llm.Response, error) {
	s.requests = append(s.requests, req)
	if len(s.errors) > 0 {
		err := s.errors[0]
		s.errors = s.errors[1:]
		if err != nil {
			return nil, err
		}
	}
	if len(s.responses) > 0 {
		res := s.responses[0]
		s.responses = s.responses[1:]
		return res, nil
	}
	return s.response, nil
}

func (s *stubLoopLLMClient) CompleteStream(ctx context.Context, req llm.Request, onToken func(string) error) (*llm.Response, error) {
	res, err := s.Complete(ctx, req)
	if err != nil {
		return nil, err
	}
	if res.Content != "" {
		if err := onToken(res.Content); err != nil {
			return nil, err
		}
	}
	return res, nil
}

type stubLoopLLMFactory struct {
	client llm.Client
}

func (s *stubLoopLLMFactory) For(task llm.TaskType) llm.Client {
	return s.client
}

type stubLoopTasksRepo struct{}

func (s *stubLoopTasksRepo) CreateTask(ctx context.Context, arg sqlcgen.CreateTaskParams) (sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubLoopTasksRepo) GetTaskByID(ctx context.Context, id pgtype.UUID, userID pgtype.UUID) (sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubLoopTasksRepo) GetTasks(ctx context.Context, arg sqlcgen.GetTasksParams) ([]sqlcgen.Task, error) {
	return nil, nil
}
func (s *stubLoopTasksRepo) UpdateTask(ctx context.Context, arg sqlcgen.UpdateTaskParams) (sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubLoopTasksRepo) DeleteTask(ctx context.Context, id, userID pgtype.UUID) error {
	panic("unimplemented")
}
func (s *stubLoopTasksRepo) GetTodayTasks(ctx context.Context, userID pgtype.UUID, upTo pgtype.Date) ([]sqlcgen.Task, error) {
	return nil, nil
}
func (s *stubLoopTasksRepo) GetTasksByNoteID(ctx context.Context, userID pgtype.UUID, noteID pgtype.UUID) ([]sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubLoopTasksRepo) CreateTaskCompletion(ctx context.Context, taskID pgtype.UUID, dueDate pgtype.Date) (sqlcgen.TaskCompletion, error) {
	panic("unimplemented")
}
func (s *stubLoopTasksRepo) CountTasks(ctx context.Context, userID pgtype.UUID) (int64, error) {
	panic("unimplemented")
}
func (s *stubLoopTasksRepo) CountOpenTasks(ctx context.Context, userID pgtype.UUID) (int64, error) {
	panic("unimplemented")
}
func (s *stubLoopTasksRepo) CountOverdueTasks(ctx context.Context, userID pgtype.UUID) (int64, error) {
	return 0, nil
}
func (s *stubLoopTasksRepo) CountCompletedTasks(ctx context.Context, userID pgtype.UUID) (int64, error) {
	panic("unimplemented")
}
func (s *stubLoopTasksRepo) SearchTasks(ctx context.Context, arg sqlcgen.SearchTasksParams) ([]sqlcgen.Task, error) {
	return nil, nil
}
func (s *stubLoopTasksRepo) GetRecentlyCompletedTasks(ctx context.Context, arg sqlcgen.GetRecentlyCompletedTasksParams) ([]sqlcgen.Task, error) {
	return nil, nil
}

type stubLoopQuerier struct{}

func (s *stubLoopQuerier) GetSoul(ctx context.Context, userID pgtype.UUID) (sqlcgen.Soul, error) {
	return sqlcgen.Soul{Personality: "test"}, nil
}
func (s *stubLoopQuerier) GetRecentNotes(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.GetRecentNotesRow, error) {
	return nil, nil
}
func (s *stubLoopQuerier) SearchNotesByEmbedding(ctx context.Context, arg sqlcgen.SearchNotesByEmbeddingParams) ([]sqlcgen.SearchNotesByEmbeddingRow, error) {
	return nil, nil
}

// Remaining Querier methods
func (s *stubLoopQuerier) AddTagToNote(ctx context.Context, arg sqlcgen.AddTagToNoteParams) error {
	panic("unimplemented")
}
func (s *stubLoopQuerier) AppendToInbox(ctx context.Context, arg sqlcgen.AppendToInboxParams) (sqlcgen.Note, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) AppendToNoteContent(ctx context.Context, arg sqlcgen.AppendToNoteContentParams) (sqlcgen.Note, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) CleanupOldMessages(ctx context.Context) error { panic("unimplemented") }
func (s *stubLoopQuerier) CountNotes(ctx context.Context, userID pgtype.UUID) (int64, error) {
	return 0, nil
}
func (s *stubLoopQuerier) CountTasks(ctx context.Context, userID pgtype.UUID) (int64, error) {
	return 0, nil
}
func (s *stubLoopQuerier) SearchTasks(ctx context.Context, arg sqlcgen.SearchTasksParams) ([]sqlcgen.Task, error) {
	return nil, nil
}
func (s *stubLoopQuerier) GetRecentlyCompletedTasks(ctx context.Context, arg sqlcgen.GetRecentlyCompletedTasksParams) ([]sqlcgen.Task, error) {
	return nil, nil
}
func (s *stubLoopQuerier) CountOverdueTasks(ctx context.Context, userID pgtype.UUID) (int64, error) {
	return 0, nil
}
func (s *stubLoopQuerier) CountOpenTasks(ctx context.Context, userID pgtype.UUID) (int64, error) {
	return 0, nil
}
func (s *stubLoopQuerier) CountCompletedTasks(ctx context.Context, userID pgtype.UUID) (int64, error) {
	return 0, nil
}
func (s *stubLoopQuerier) CreateContext(ctx context.Context, arg sqlcgen.CreateContextParams) (sqlcgen.Context, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) CreateDeviceToken(ctx context.Context, arg sqlcgen.CreateDeviceTokenParams) (sqlcgen.DeviceToken, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) CreateMemory(ctx context.Context, arg sqlcgen.CreateMemoryParams) (sqlcgen.Memory, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) CreateMessage(ctx context.Context, arg sqlcgen.CreateMessageParams) (sqlcgen.Message, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) CreateNote(ctx context.Context, arg sqlcgen.CreateNoteParams) (sqlcgen.Note, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) CreateNoteLink(ctx context.Context, arg sqlcgen.CreateNoteLinkParams) error {
	panic("unimplemented")
}
func (s *stubLoopQuerier) CreateRefreshToken(ctx context.Context, arg sqlcgen.CreateRefreshTokenParams) (sqlcgen.RefreshToken, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) CreateRoutine(ctx context.Context, arg sqlcgen.CreateRoutineParams) (sqlcgen.Routine, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) CreateRoutineLog(ctx context.Context, arg sqlcgen.CreateRoutineLogParams) (sqlcgen.RoutineLog, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) CreateTag(ctx context.Context, arg sqlcgen.CreateTagParams) (sqlcgen.Tag, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) CreateTask(ctx context.Context, arg sqlcgen.CreateTaskParams) (sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) CreateTaskCompletion(ctx context.Context, arg sqlcgen.CreateTaskCompletionParams) (sqlcgen.TaskCompletion, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) CreateUser(ctx context.Context, arg sqlcgen.CreateUserParams) (sqlcgen.User, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) CreateUserSettings(ctx context.Context, arg sqlcgen.CreateUserSettingsParams) (sqlcgen.UserSetting, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) DeleteContext(ctx context.Context, arg sqlcgen.DeleteContextParams) error {
	panic("unimplemented")
}
func (s *stubLoopQuerier) DeleteDeviceToken(ctx context.Context, arg sqlcgen.DeleteDeviceTokenParams) error {
	panic("unimplemented")
}
func (s *stubLoopQuerier) DeleteDeviceTokenByToken(ctx context.Context, arg sqlcgen.DeleteDeviceTokenByTokenParams) error {
	panic("unimplemented")
}
func (s *stubLoopQuerier) DeleteMemory(ctx context.Context, arg sqlcgen.DeleteMemoryParams) error {
	panic("unimplemented")
}
func (s *stubLoopQuerier) DeleteNote(ctx context.Context, arg sqlcgen.DeleteNoteParams) error {
	panic("unimplemented")
}
func (s *stubLoopQuerier) DeleteSessionMessages(ctx context.Context, arg sqlcgen.DeleteSessionMessagesParams) error {
	panic("unimplemented")
}
func (s *stubLoopQuerier) DeleteTag(ctx context.Context, arg sqlcgen.DeleteTagParams) error {
	panic("unimplemented")
}
func (s *stubLoopQuerier) DeleteTask(ctx context.Context, arg sqlcgen.DeleteTaskParams) error {
	panic("unimplemented")
}
func (s *stubLoopQuerier) GetContexts(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.Context, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) GetEnabledRoutines(ctx context.Context) ([]sqlcgen.GetEnabledRoutinesRow, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) GetInboxNote(ctx context.Context, userID pgtype.UUID) (sqlcgen.GetInboxNoteRow, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) GetLatestBriefByType(ctx context.Context, arg sqlcgen.GetLatestBriefByTypeParams) (sqlcgen.RoutineLog, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) GetLinkedNotes(ctx context.Context, arg sqlcgen.GetLinkedNotesParams) ([]sqlcgen.Note, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) GetMemories(ctx context.Context, arg sqlcgen.GetMemoriesParams) ([]sqlcgen.Memory, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) GetMessages(ctx context.Context, arg sqlcgen.GetMessagesParams) ([]sqlcgen.Message, error) {
	return nil, nil
}
func (s *stubLoopQuerier) GetNoteByID(ctx context.Context, arg sqlcgen.GetNoteByIDParams) (sqlcgen.GetNoteByIDRow, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) GetNotes(ctx context.Context, arg sqlcgen.GetNotesParams) ([]sqlcgen.GetNotesRow, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) GetRefreshToken(ctx context.Context, tokenHash string) (sqlcgen.RefreshToken, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) GetRetryableEmbeddings(ctx context.Context, limit int32) ([]sqlcgen.GetRetryableEmbeddingsRow, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) GetRoutineLogsByUser(ctx context.Context, arg sqlcgen.GetRoutineLogsByUserParams) ([]sqlcgen.RoutineLog, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) GetRoutinesByUser(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.Routine, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) GetSyncContexts(ctx context.Context, arg sqlcgen.GetSyncContextsParams) ([]sqlcgen.Context, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) GetSyncNotes(ctx context.Context, arg sqlcgen.GetSyncNotesParams) ([]sqlcgen.GetSyncNotesRow, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) GetSyncTags(ctx context.Context, arg sqlcgen.GetSyncTagsParams) ([]sqlcgen.Tag, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) GetSyncTasks(ctx context.Context, arg sqlcgen.GetSyncTasksParams) ([]sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) GetTags(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.Tag, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) GetTagsForNote(ctx context.Context, noteID pgtype.UUID) ([]sqlcgen.Tag, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) GetTaskByID(ctx context.Context, arg sqlcgen.GetTaskByIDParams) (sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) GetTasks(ctx context.Context, arg sqlcgen.GetTasksParams) ([]sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) GetTasksByNoteID(ctx context.Context, arg sqlcgen.GetTasksByNoteIDParams) ([]sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) GetTodayTasks(ctx context.Context, arg sqlcgen.GetTodayTasksParams) ([]sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) GetUserByEmail(ctx context.Context, email string) (sqlcgen.User, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) GetUserByID(ctx context.Context, id pgtype.UUID) (sqlcgen.User, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) GetUserSettings(ctx context.Context, userID pgtype.UUID) (sqlcgen.UserSetting, error) {
	return sqlcgen.UserSetting{}, nil
}
func (s *stubLoopQuerier) HardDeleteExpiredContexts(ctx context.Context) error {
	panic("unimplemented")
}
func (s *stubLoopQuerier) HardDeleteExpiredNotes(ctx context.Context) error { panic("unimplemented") }
func (s *stubLoopQuerier) HardDeleteExpiredTasks(ctx context.Context) error { panic("unimplemented") }
func (s *stubLoopQuerier) ListDeviceTokensByUser(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.DeviceToken, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) RemoveTagFromNote(ctx context.Context, arg sqlcgen.RemoveTagFromNoteParams) error {
	panic("unimplemented")
}
func (s *stubLoopQuerier) RevokeAllUserRefreshTokens(ctx context.Context, userID pgtype.UUID) error {
	panic("unimplemented")
}
func (s *stubLoopQuerier) RevokeRefreshToken(ctx context.Context, id pgtype.UUID) error {
	panic("unimplemented")
}
func (s *stubLoopQuerier) SearchMemoriesByEmbedding(ctx context.Context, arg sqlcgen.SearchMemoriesByEmbeddingParams) ([]sqlcgen.SearchMemoriesByEmbeddingRow, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) SearchNotesFTS(ctx context.Context, arg sqlcgen.SearchNotesFTSParams) ([]sqlcgen.SearchNotesFTSRow, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) SearchNotesHybrid(ctx context.Context, arg sqlcgen.SearchNotesHybridParams) ([]sqlcgen.SearchNotesHybridRow, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) SearchNotesSemantic(ctx context.Context, arg sqlcgen.SearchNotesSemanticParams) ([]sqlcgen.SearchNotesSemanticRow, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) SetInboxContent(ctx context.Context, arg sqlcgen.SetInboxContentParams) (sqlcgen.Note, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) UpdateNote(ctx context.Context, arg sqlcgen.UpdateNoteParams) (sqlcgen.Note, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) UpdateNoteEmbeddingStatus(ctx context.Context, arg sqlcgen.UpdateNoteEmbeddingStatusParams) error {
	panic("unimplemented")
}
func (s *stubLoopQuerier) UpdateRoutine(ctx context.Context, arg sqlcgen.UpdateRoutineParams) (sqlcgen.Routine, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) UpdateTask(ctx context.Context, arg sqlcgen.UpdateTaskParams) (sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) UpdateUserSettings(ctx context.Context, arg sqlcgen.UpdateUserSettingsParams) (sqlcgen.UserSetting, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) UpsertContext(ctx context.Context, arg sqlcgen.UpsertContextParams) (sqlcgen.Context, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) UpsertNote(ctx context.Context, arg sqlcgen.UpsertNoteParams) (sqlcgen.Note, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) UpsertNoteEmbedding(ctx context.Context, arg sqlcgen.UpsertNoteEmbeddingParams) error {
	panic("unimplemented")
}
func (s *stubLoopQuerier) UpsertSoul(ctx context.Context, arg sqlcgen.UpsertSoulParams) (sqlcgen.Soul, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) UpsertTag(ctx context.Context, arg sqlcgen.UpsertTagParams) (sqlcgen.Tag, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) UpsertTask(ctx context.Context, arg sqlcgen.UpsertTaskParams) (sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) UpdateRoutineLastRunAt(ctx context.Context, id pgtype.UUID) error {
	panic("unimplemented")
}
func (s *stubLoopQuerier) UpsertTaskCompletion(ctx context.Context, arg sqlcgen.UpsertTaskCompletionParams) error {
	panic("unimplemented")
}
func (s *stubLoopQuerier) GetSyncTaskCompletions(ctx context.Context, arg sqlcgen.GetSyncTaskCompletionsParams) ([]sqlcgen.TaskCompletion, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) GetSyncNoteTags(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.NoteTag, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) UpsertNoteTag(ctx context.Context, arg sqlcgen.UpsertNoteTagParams) error {
	panic("unimplemented")
}
func (s *stubLoopQuerier) GetSyncNoteLinks(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.NoteLink, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) UpsertNoteLink(ctx context.Context, arg sqlcgen.UpsertNoteLinkParams) error {
	panic("unimplemented")
}
func (s *stubLoopQuerier) CreateNoteShare(ctx context.Context, arg sqlcgen.CreateNoteShareParams) (sqlcgen.NoteShare, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) DeleteNoteShare(ctx context.Context, arg sqlcgen.DeleteNoteShareParams) error {
	panic("unimplemented")
}
func (s *stubLoopQuerier) GetNoteOwner(ctx context.Context, id pgtype.UUID) (pgtype.UUID, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) GetNoteShareForUser(ctx context.Context, arg sqlcgen.GetNoteShareForUserParams) (sqlcgen.NoteShare, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) GetNoteShares(ctx context.Context, noteID pgtype.UUID) ([]sqlcgen.GetNoteSharesRow, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) CreatePendingToolConfirmation(context.Context, sqlcgen.CreatePendingToolConfirmationParams) (sqlcgen.PendingToolConfirmation, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) GetPendingToolConfirmation(context.Context, sqlcgen.GetPendingToolConfirmationParams) (sqlcgen.PendingToolConfirmation, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) ResolvePendingToolConfirmation(context.Context, sqlcgen.ResolvePendingToolConfirmationParams) (sqlcgen.PendingToolConfirmation, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) DeleteAttachment(ctx context.Context, id pgtype.UUID) error { return nil }
func (s *stubLoopQuerier) InsertAttachment(ctx context.Context, arg sqlcgen.InsertAttachmentParams) (sqlcgen.Attachment, error) {
	panic("unimplemented")
}
func (s *stubLoopQuerier) ListAttachmentsByNote(ctx context.Context, noteID pgtype.UUID) ([]sqlcgen.Attachment, error) {
	return nil, nil
}
func (s *stubLoopQuerier) GetNoteOwnerID(ctx context.Context, noteID pgtype.UUID) (pgtype.UUID, error) {
	return pgtype.UUID{}, nil
}
func (s *stubLoopQuerier) GetSyncUserNotePreferences(ctx context.Context, arg sqlcgen.GetSyncUserNotePreferencesParams) ([]sqlcgen.UserNotePreference, error) {
	return nil, nil
}
func (s *stubLoopQuerier) UpsertUserNotePreference(ctx context.Context, arg sqlcgen.UpsertUserNotePreferenceParams) (sqlcgen.UserNotePreference, error) {
	return sqlcgen.UserNotePreference{}, nil
}

type trackingStubLoopRepo struct {
	stubLoopRepo
	pendingConfirmations []string
}

func (s *trackingStubLoopRepo) CreatePendingToolConfirmation(ctx context.Context, userID, sessionID pgtype.UUID, toolName, argsJSON string) (sqlcgen.PendingToolConfirmation, error) {
	id := uuid.New()
	s.pendingConfirmations = append(s.pendingConfirmations, id.String())
	return sqlcgen.PendingToolConfirmation{
		ID:        pgtype.UUID{Bytes: id, Valid: true},
		UserID:    userID,
		SessionID: sessionID,
		ToolName:  toolName,
		ArgsJson:  []byte(argsJSON),
		Status:    "pending",
	}, nil
}

func TestLoopConfirmationRequired(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	q := &stubLoopQuerier{}
	embedCL := llm.NewEmbeddingClient("test-key", srv.URL, "text-embedding-3-small")
	memRepo := &stubLoopMemRepo{}
	tasksSvc := tasks.NewService(&stubLoopTasksRepo{})
	ctxBldr := NewContextBuilder(q, tasksSvc, memRepo, embedCL)

	llmFact := &stubLoopLLMFactory{
		client: &stubLoopLLMClient{
			response: &llm.Response{
				Content: "",
				ToolCalls: []llm.ToolCall{
					{ID: "call-1", Name: "update_note", ArgsJSON: `{"note_id":"abc","content":"new"}`},
				},
			},
		},
	}

	memSvc := memories.NewService(memRepo, embedCL)
	toolReg := tools.NewToolRegistry(
		q, nil, tasksSvc, memSvc, nil, nil, embedCL, llmFact,
	)

	repo := &trackingStubLoopRepo{}
	loop := NewLoop(repo, llmFact, ctxBldr, toolReg)

	events := make(chan SSEEvent, 10)
	go func() {
		defer close(events)
		if err := loop.ChatStream(
			context.Background(),
			pgtype.UUID{},
			"00000000-0000-0000-0000-000000000001",
			"update my note",
			events,
		); err != nil {
			t.Errorf("ChatStream: %v", err)
		}
	}()

	var foundConfirmation bool
	var confirmationPayload struct {
		ConfirmationID string `json:"confirmation_id"`
		ToolName       string `json:"tool_name"`
		Label          string `json:"label"`
	}
	var confirmationPayloadJSON string
	for evt := range events {
		if evt.Type != string(EventConfirmationRequired) {
			continue
		}
		foundConfirmation = true
		var streamEvent StreamEvent
		if err := json.Unmarshal([]byte(evt.Data), &streamEvent); err != nil {
			t.Fatalf("unmarshal stream event: %v", err)
		}
		payloadBytes, err := json.Marshal(streamEvent.Payload)
		if err != nil {
			t.Fatalf("marshal payload: %v", err)
		}
		confirmationPayloadJSON = string(payloadBytes)
		if err := json.Unmarshal(payloadBytes, &confirmationPayload); err != nil {
			t.Fatalf("unmarshal payload: %v", err)
		}
	}

	if !foundConfirmation {
		t.Fatal("expected confirmation_required event but got none")
	}
	if confirmationPayload.ConfirmationID == "" {
		t.Fatal("expected non-empty confirmation_id in payload")
	}
	if confirmationPayload.ToolName != "update_note" {
		t.Fatalf("tool_name: want update_note, got %s", confirmationPayload.ToolName)
	}
	if confirmationPayload.Label == "" {
		t.Fatal("expected non-empty label in payload")
	}
	if len(repo.pendingConfirmations) != 1 {
		t.Fatalf("expected 1 pending confirmation, got %d", len(repo.pendingConfirmations))
	}
	if repo.pendingConfirmations[0] != confirmationPayload.ConfirmationID {
		t.Fatalf("confirmation_id mismatch: repo has %s, payload has %s",
			repo.pendingConfirmations[0], confirmationPayload.ConfirmationID)
	}
	if strings.Contains(confirmationPayloadJSON, "args_json") {
		t.Fatal("payload must not contain args_json")
	}
}

func TestLoopRejectsEmptyLLMResponse(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	q := &stubLoopQuerier{}
	embedCL := llm.NewEmbeddingClient("test-key", srv.URL, "text-embedding-3-small")
	memRepo := &stubLoopMemRepo{}
	tasksSvc := tasks.NewService(&stubLoopTasksRepo{})
	ctxBldr := NewContextBuilder(q, tasksSvc, memRepo, embedCL)

	llmFact := &stubLoopLLMFactory{
		client: &stubLoopLLMClient{
			response: &llm.Response{},
		},
	}

	memSvc := memories.NewService(memRepo, embedCL)
	toolReg := tools.NewToolRegistry(
		q, nil, tasksSvc, memSvc, nil, nil, embedCL, llmFact,
	)

	loop := NewLoop(&stubLoopRepo{}, llmFact, ctxBldr, toolReg)

	events := make(chan SSEEvent, 10)
	err := loop.ChatStream(
		context.Background(),
		pgtype.UUID{},
		"00000000-0000-0000-0000-000000000001",
		"hello",
		events,
	)
	close(events)

	if err == nil {
		t.Fatal("expected empty llm response to return an error")
	}
}

func TestLoopFallsBackWithoutToolsWhenLLMReturnsEmptyResponse(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	q := &stubLoopQuerier{}
	embedCL := llm.NewEmbeddingClient("test-key", srv.URL, "text-embedding-3-small")
	memRepo := &stubLoopMemRepo{}
	tasksSvc := tasks.NewService(&stubLoopTasksRepo{})
	ctxBldr := NewContextBuilder(q, tasksSvc, memRepo, embedCL)

	llmClient := &stubLoopLLMClient{
		responses: []*llm.Response{
			{},
			{Content: "hello back"},
		},
	}
	llmFact := &stubLoopLLMFactory{client: llmClient}

	memSvc := memories.NewService(memRepo, embedCL)
	toolReg := tools.NewToolRegistry(
		q, nil, tasksSvc, memSvc, nil, nil, embedCL, llmFact,
	)

	loop := NewLoop(&stubLoopRepo{}, llmFact, ctxBldr, toolReg)

	events := make(chan SSEEvent, 10)
	err := loop.ChatStream(
		context.Background(),
		pgtype.UUID{},
		"00000000-0000-0000-0000-000000000001",
		"hello",
		events,
	)
	close(events)

	if err != nil {
		t.Fatalf("ChatStream: %v", err)
	}
	if len(llmClient.requests) != 2 {
		t.Fatalf("expected two llm requests, got %d", len(llmClient.requests))
	}
	if len(llmClient.requests[0].Tools) == 0 {
		t.Fatal("expected first request to include tools")
	}
	if len(llmClient.requests[1].Tools) != 0 {
		t.Fatal("expected fallback request to omit tools")
	}

	var foundFinal bool
	for evt := range events {
		if evt.Type == string(EventMessageFinished) {
			foundFinal = true
		}
	}
	if !foundFinal {
		t.Fatal("expected fallback response to finish the message")
	}
}

func TestLoopFinishesWithToolResultWhenLLMResponseAfterToolIsEmpty(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	q := &stubLoopQuerier{}
	embedCL := llm.NewEmbeddingClient("test-key", srv.URL, "text-embedding-3-small")
	memRepo := &stubLoopMemRepo{}
	tasksSvc := tasks.NewService(&stubLoopTasksRepo{})
	ctxBldr := NewContextBuilder(q, tasksSvc, memRepo, embedCL)

	llmFact := &stubLoopLLMFactory{
		client: &stubLoopLLMClient{
			responses: []*llm.Response{
				{
					ToolCalls: []llm.ToolCall{
						{ID: "call-1", Name: "query_tasks", ArgsJSON: `{}`},
					},
				},
				{},
				{},
			},
		},
	}

	memSvc := memories.NewService(memRepo, embedCL)
	toolReg := tools.NewToolRegistry(
		q, nil, tasksSvc, memSvc, nil, nil, embedCL, llmFact,
	)

	loop := NewLoop(&stubLoopRepo{}, llmFact, ctxBldr, toolReg)

	events := make(chan SSEEvent, 10)
	err := loop.ChatStream(
		context.Background(),
		pgtype.UUID{},
		"00000000-0000-0000-0000-000000000001",
		"what is due today?",
		events,
	)
	close(events)

	if err != nil {
		t.Fatalf("ChatStream: %v", err)
	}

	var final string
	for evt := range events {
		if evt.Type != string(EventMessageFinished) {
			continue
		}
		var streamEvent StreamEvent
		if err := json.Unmarshal([]byte(evt.Data), &streamEvent); err != nil {
			t.Fatalf("unmarshal stream event: %v", err)
		}
		payloadBytes, err := json.Marshal(streamEvent.Payload)
		if err != nil {
			t.Fatalf("marshal payload: %v", err)
		}
		var payload MessageFinishedPayload
		if err := json.Unmarshal(payloadBytes, &payload); err != nil {
			t.Fatalf("unmarshal payload: %v", err)
		}
		final = payload.Content
	}

	if final != "No matching tasks found" {
		t.Fatalf("final content: want %q, got %q", "No matching tasks found", final)
	}
}

func TestLoopFinishesWithToolResultWhenLLMCallAfterToolFails(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	q := &stubLoopQuerier{}
	embedCL := llm.NewEmbeddingClient("test-key", srv.URL, "text-embedding-3-small")
	memRepo := &stubLoopMemRepo{}
	tasksSvc := tasks.NewService(&stubLoopTasksRepo{})
	ctxBldr := NewContextBuilder(q, tasksSvc, memRepo, embedCL)

	llmFact := &stubLoopLLMFactory{
		client: &stubLoopLLMClient{
			responses: []*llm.Response{
				{
					ToolCalls: []llm.ToolCall{
						{ID: "call-1", Name: "query_tasks", ArgsJSON: `{}`},
					},
				},
			},
			errors: []error{
				nil,
				errors.New(`llm retry failed after 3 attempts: openai_compat: do req: Post "https://integrate.api.nvidia.com/v1/chat/completions": context deadline exceeded`),
			},
		},
	}

	memSvc := memories.NewService(memRepo, embedCL)
	toolReg := tools.NewToolRegistry(
		q, nil, tasksSvc, memSvc, nil, nil, embedCL, llmFact,
	)

	loop := NewLoop(&stubLoopRepo{}, llmFact, ctxBldr, toolReg)

	events := make(chan SSEEvent, 10)
	err := loop.ChatStream(
		context.Background(),
		pgtype.UUID{},
		"00000000-0000-0000-0000-000000000001",
		"what is due today?",
		events,
	)
	close(events)

	if err != nil {
		t.Fatalf("ChatStream: %v", err)
	}

	var final string
	for evt := range events {
		if evt.Type != string(EventMessageFinished) {
			continue
		}
		var streamEvent StreamEvent
		if err := json.Unmarshal([]byte(evt.Data), &streamEvent); err != nil {
			t.Fatalf("unmarshal stream event: %v", err)
		}
		payloadBytes, err := json.Marshal(streamEvent.Payload)
		if err != nil {
			t.Fatalf("marshal payload: %v", err)
		}
		var payload MessageFinishedPayload
		if err := json.Unmarshal(payloadBytes, &payload); err != nil {
			t.Fatalf("unmarshal payload: %v", err)
		}
		final = payload.Content
	}

	if final != "No matching tasks found" {
		t.Fatalf("final content: want %q, got %q", "No matching tasks found", final)
	}
}

type resolveTestRepo struct {
	pending sqlcgen.PendingToolConfirmation
	created sqlcgen.Message
}

func (r *resolveTestRepo) GetMessages(ctx context.Context, userID, sessionID pgtype.UUID, limit, offset int32) ([]sqlcgen.Message, error) {
	return nil, nil
}
func (r *resolveTestRepo) CreateMessage(ctx context.Context, userID, sessionID pgtype.UUID, role, content string, toolCalls []byte, toolCallID *string) (sqlcgen.Message, error) {
	r.created = sqlcgen.Message{Content: content}
	return r.created, nil
}
func (r *resolveTestRepo) DeleteSessionMessages(ctx context.Context, userID, sessionID pgtype.UUID) error {
	return nil
}
func (r *resolveTestRepo) CountNotes(ctx context.Context, userID pgtype.UUID) (int64, error) {
	return 0, nil
}
func (r *resolveTestRepo) CountTasks(ctx context.Context, userID pgtype.UUID) (int64, error) {
	return 0, nil
}
func (r *resolveTestRepo) CountOpenTasks(ctx context.Context, userID pgtype.UUID) (int64, error) {
	return 0, nil
}
func (r *resolveTestRepo) CountCompletedTasks(ctx context.Context, userID pgtype.UUID) (int64, error) {
	return 0, nil
}
func (r *resolveTestRepo) CreatePendingToolConfirmation(ctx context.Context, userID, sessionID pgtype.UUID, toolName, argsJSON string) (sqlcgen.PendingToolConfirmation, error) {
	id := uuid.New()
	r.pending = sqlcgen.PendingToolConfirmation{
		ID:        pgtype.UUID{Bytes: id, Valid: true},
		UserID:    userID,
		SessionID: sessionID,
		ToolName:  toolName,
		ArgsJson:  []byte(argsJSON),
		Status:    "pending",
	}
	return r.pending, nil
}
func (r *resolveTestRepo) GetPendingToolConfirmation(ctx context.Context, id, userID pgtype.UUID) (sqlcgen.PendingToolConfirmation, error) {
	if r.pending.Status == "" {
		return sqlcgen.PendingToolConfirmation{}, fmt.Errorf("not found")
	}
	return r.pending, nil
}
func (r *resolveTestRepo) ResolvePendingToolConfirmation(ctx context.Context, id, userID pgtype.UUID, status string) (sqlcgen.PendingToolConfirmation, error) {
	if r.pending.Status != "pending" {
		return sqlcgen.PendingToolConfirmation{}, fmt.Errorf("already resolved")
	}
	r.pending.Status = status
	return r.pending, nil
}

func TestResolveToolConfirmationCancelDoesNotExecuteTool(t *testing.T) {
	repo := &resolveTestRepo{
		pending: sqlcgen.PendingToolConfirmation{
			ID:        pgtype.UUID{Bytes: uuid.New(), Valid: true},
			UserID:    pgtype.UUID{},
			SessionID: pgtype.UUID{},
			ToolName:  "update_note",
			ArgsJson:  []byte(`{}`),
			Status:    "pending",
		},
	}
	h := &Handler{repo: repo, loop: NewLoop(&stubLoopRepo{}, nil, nil, nil)}

	resp, status, err := h.resolveToolConfirmation(context.Background(), pgtype.UUID{}, uid.UUIDToString(repo.pending.ID), false)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if status != 200 {
		t.Fatalf("status: want 200, got %d", status)
	}
	if resp.Status != "cancelled" {
		t.Fatalf("status field: want cancelled, got %s", resp.Status)
	}
}

func TestResolveToolConfirmationRejectsAlreadyResolved(t *testing.T) {
	id := pgtype.UUID{Bytes: uuid.New(), Valid: true}
	userID := pgtype.UUID{Bytes: uuid.New(), Valid: true}
	h := &Handler{
		repo: &resolveTestRepo{
			pending: sqlcgen.PendingToolConfirmation{
				ID:     id,
				UserID: userID,
				Status: "approved",
			},
		},
		loop: NewLoop(&stubLoopRepo{}, nil, nil, nil),
	}

	_, status, err := h.resolveToolConfirmation(context.Background(), userID, uid.UUIDToString(id), true)
	if err == nil {
		t.Fatal("expected error for already resolved confirmation")
	}
	if status != 409 {
		t.Fatalf("status: want 409, got %d", status)
	}
}

func TestResolveToolConfirmationNotFound(t *testing.T) {
	repo := &resolveTestRepo{}
	h := NewHandler(NewLoop(&stubLoopRepo{}, nil, nil, nil), repo)

	_, status, err := h.resolveToolConfirmation(
		context.Background(),
		pgtype.UUID{},
		uuid.New().String(),
		true,
	)
	if err == nil {
		t.Fatal("expected error for not found")
	}
	if status != 404 {
		t.Fatalf("status: want 404, got %d", status)
	}
}

type stubLoopMemRepo struct{}

func (m *stubLoopMemRepo) GetMemories(ctx context.Context, userID pgtype.UUID, limit, offset int32) ([]sqlcgen.Memory, error) {
	return nil, nil
}
func (m *stubLoopMemRepo) CreateMemory(ctx context.Context, userID pgtype.UUID, content string, embedding pgvector.Vector) (sqlcgen.Memory, error) {
	panic("unimplemented")
}
func (m *stubLoopMemRepo) DeleteMemory(ctx context.Context, id, userID pgtype.UUID) error {
	panic("unimplemented")
}
func (m *stubLoopMemRepo) SearchMemories(ctx context.Context, userID pgtype.UUID, embedding pgvector.Vector, limit int32) ([]sqlcgen.SearchMemoriesByEmbeddingRow, error) {
	return nil, nil
}

