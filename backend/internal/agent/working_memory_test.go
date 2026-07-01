package agent

import (
	"context"
	"testing"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

type stubWMQuerier struct {
	vals map[string]string // keyed by "userID:sessionID:key"
}

func (s *stubWMQuerier) SetWorkingMemoryValue(ctx context.Context, arg sqlcgen.SetWorkingMemoryValueParams) (sqlcgen.AgentWorkingMemory, error) {
	if s.vals == nil {
		s.vals = make(map[string]string)
	}
	key := keyForWM(arg.UserID, arg.SessionID, arg.Key)
	s.vals[key] = arg.Value
	return sqlcgen.AgentWorkingMemory{}, nil
}

func (s *stubWMQuerier) GetWorkingMemoryValue(ctx context.Context, arg sqlcgen.GetWorkingMemoryValueParams) (string, error) {
	key := keyForWM(arg.UserID, arg.SessionID, arg.Key)
	return s.vals[key], nil
}

func (s *stubWMQuerier) GetWorkingMemoryForSession(ctx context.Context, arg sqlcgen.GetWorkingMemoryForSessionParams) ([]sqlcgen.GetWorkingMemoryForSessionRow, error) {
	var rows []sqlcgen.GetWorkingMemoryForSessionRow
	for k, v := range s.vals {
		if containsKeyFor(k, arg.UserID, arg.SessionID) {
			rows = append(rows, sqlcgen.GetWorkingMemoryForSessionRow{
				Key:   extractKey(k),
				Value: v,
			})
		}
	}
	return rows, nil
}

func (s *stubWMQuerier) DeleteWorkingMemoryForSession(ctx context.Context, arg sqlcgen.DeleteWorkingMemoryForSessionParams) error {
	for k := range s.vals {
		if containsKeyFor(k, arg.UserID, arg.SessionID) {
			delete(s.vals, k)
		}
	}
	return nil
}

func keyForWM(userID, sessionID pgtype.UUID, key string) string {
	return string(userID.Bytes[:]) + ":" + string(sessionID.Bytes[:]) + ":" + key
}

func containsKeyFor(k string, userID, sessionID pgtype.UUID) bool {
	prefix := string(userID.Bytes[:]) + ":" + string(sessionID.Bytes[:]) + ":"
	if len(k) < len(prefix) {
		return false
	}
	return k[:len(prefix)] == prefix
}

func extractKey(k string) string {
	parts := 0
	for i := 0; i < len(k); i++ {
		if k[i] == ':' {
			parts++
			if parts == 2 {
				return k[i+1:]
			}
		}
	}
	return ""
}

// Remaining Querier methods
func (s *stubWMQuerier) GetSoul(ctx context.Context, userID pgtype.UUID) (sqlcgen.Soul, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) GetRecentNotes(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.GetRecentNotesRow, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) SearchNotesByEmbedding(ctx context.Context, arg sqlcgen.SearchNotesByEmbeddingParams) ([]sqlcgen.SearchNotesByEmbeddingRow, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) AddTagToNote(ctx context.Context, arg sqlcgen.AddTagToNoteParams) error { panic("unimplemented") }
func (s *stubWMQuerier) AppendToInbox(ctx context.Context, arg sqlcgen.AppendToInboxParams) (sqlcgen.Note, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) AppendToNoteContent(ctx context.Context, arg sqlcgen.AppendToNoteContentParams) (sqlcgen.Note, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) CleanupOldMessages(ctx context.Context) error { panic("unimplemented") }
func (s *stubWMQuerier) CountNotes(ctx context.Context, userID pgtype.UUID) (int64, error) { return 0, nil }
func (s *stubWMQuerier) CountTasks(ctx context.Context, userID pgtype.UUID) (int64, error) { return 0, nil }
func (s *stubWMQuerier) SearchTasks(ctx context.Context, arg sqlcgen.SearchTasksParams) ([]sqlcgen.Task, error) {
	return nil, nil
}
func (s *stubWMQuerier) GetRecentlyCompletedTasks(ctx context.Context, arg sqlcgen.GetRecentlyCompletedTasksParams) ([]sqlcgen.Task, error) {
	return nil, nil
}
func (s *stubWMQuerier) CountOverdueTasks(ctx context.Context, userID pgtype.UUID) (int64, error) { return 0, nil }
func (s *stubWMQuerier) CountOpenTasks(ctx context.Context, userID pgtype.UUID) (int64, error)    { return 0, nil }
func (s *stubWMQuerier) CountCompletedTasks(ctx context.Context, userID pgtype.UUID) (int64, error) { return 0, nil }
func (s *stubWMQuerier) CreateContext(ctx context.Context, arg sqlcgen.CreateContextParams) (sqlcgen.Context, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) CreateDeviceToken(ctx context.Context, arg sqlcgen.CreateDeviceTokenParams) (sqlcgen.DeviceToken, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) CreateMemory(ctx context.Context, arg sqlcgen.CreateMemoryParams) (sqlcgen.Memory, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) CreateMessage(ctx context.Context, arg sqlcgen.CreateMessageParams) (sqlcgen.Message, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) CreateNote(ctx context.Context, arg sqlcgen.CreateNoteParams) (sqlcgen.Note, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) CreateNoteLink(ctx context.Context, arg sqlcgen.CreateNoteLinkParams) error {
	panic("unimplemented")
}
func (s *stubWMQuerier) CreateRefreshToken(ctx context.Context, arg sqlcgen.CreateRefreshTokenParams) (sqlcgen.RefreshToken, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) CreateRoutine(ctx context.Context, arg sqlcgen.CreateRoutineParams) (sqlcgen.Routine, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) CreateRoutineLog(ctx context.Context, arg sqlcgen.CreateRoutineLogParams) (sqlcgen.RoutineLog, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) CreateTag(ctx context.Context, arg sqlcgen.CreateTagParams) (sqlcgen.Tag, error) { panic("unimplemented") }
func (s *stubWMQuerier) CreateTask(ctx context.Context, arg sqlcgen.CreateTaskParams) (sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) CreateTaskCompletion(ctx context.Context, arg sqlcgen.CreateTaskCompletionParams) (sqlcgen.TaskCompletion, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) CreateUser(ctx context.Context, arg sqlcgen.CreateUserParams) (sqlcgen.User, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) CreateUserSettings(ctx context.Context, arg sqlcgen.CreateUserSettingsParams) (sqlcgen.UserSetting, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) DeleteContext(ctx context.Context, arg sqlcgen.DeleteContextParams) error { panic("unimplemented") }
func (s *stubWMQuerier) DeleteDeviceToken(ctx context.Context, arg sqlcgen.DeleteDeviceTokenParams) error {
	panic("unimplemented")
}
func (s *stubWMQuerier) DeleteDeviceTokenByToken(ctx context.Context, arg sqlcgen.DeleteDeviceTokenByTokenParams) error {
	panic("unimplemented")
}
func (s *stubWMQuerier) DeleteMemory(ctx context.Context, arg sqlcgen.DeleteMemoryParams) error { panic("unimplemented") }
func (s *stubWMQuerier) DeleteNote(ctx context.Context, arg sqlcgen.DeleteNoteParams) error     { panic("unimplemented") }
func (s *stubWMQuerier) DeleteSessionMessages(ctx context.Context, arg sqlcgen.DeleteSessionMessagesParams) error {
	panic("unimplemented")
}
func (s *stubWMQuerier) DeleteTag(ctx context.Context, arg sqlcgen.DeleteTagParams) error  { panic("unimplemented") }
func (s *stubWMQuerier) DeleteTask(ctx context.Context, arg sqlcgen.DeleteTaskParams) error { panic("unimplemented") }
func (s *stubWMQuerier) GetContexts(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.Context, error) {
	return nil, nil
}
func (s *stubWMQuerier) GetEnabledRoutines(ctx context.Context) ([]sqlcgen.GetEnabledRoutinesRow, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) GetInboxNote(ctx context.Context, userID pgtype.UUID) (sqlcgen.GetInboxNoteRow, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) GetLatestBriefByType(ctx context.Context, arg sqlcgen.GetLatestBriefByTypeParams) (sqlcgen.RoutineLog, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) GetLinkedNotes(ctx context.Context, arg sqlcgen.GetLinkedNotesParams) ([]sqlcgen.Note, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) CountMemories(ctx context.Context, userID pgtype.UUID) (int64, error) {
	return 0, nil
}
func (s *stubWMQuerier) GetMemories(ctx context.Context, arg sqlcgen.GetMemoriesParams) ([]sqlcgen.Memory, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) GetMessages(ctx context.Context, arg sqlcgen.GetMessagesParams) ([]sqlcgen.Message, error) {
	return nil, nil
}
func (s *stubWMQuerier) GetNoteByID(ctx context.Context, arg sqlcgen.GetNoteByIDParams) (sqlcgen.GetNoteByIDRow, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) GetNotes(ctx context.Context, arg sqlcgen.GetNotesParams) ([]sqlcgen.GetNotesRow, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) GetRefreshToken(ctx context.Context, tokenHash string) (sqlcgen.RefreshToken, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) GetRetryableEmbeddings(ctx context.Context, limit int32) ([]sqlcgen.GetRetryableEmbeddingsRow, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) GetRoutineLogsByUser(ctx context.Context, arg sqlcgen.GetRoutineLogsByUserParams) ([]sqlcgen.RoutineLog, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) GetRoutinesByUser(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.Routine, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) GetSyncContexts(ctx context.Context, arg sqlcgen.GetSyncContextsParams) ([]sqlcgen.Context, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) GetSyncNotes(ctx context.Context, arg sqlcgen.GetSyncNotesParams) ([]sqlcgen.GetSyncNotesRow, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) GetSyncTags(ctx context.Context, arg sqlcgen.GetSyncTagsParams) ([]sqlcgen.Tag, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) GetSyncTasks(ctx context.Context, arg sqlcgen.GetSyncTasksParams) ([]sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) GetTags(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.Tag, error) { panic("unimplemented") }
func (s *stubWMQuerier) GetTagsForNote(ctx context.Context, noteID pgtype.UUID) ([]sqlcgen.Tag, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) GetTaskByID(ctx context.Context, arg sqlcgen.GetTaskByIDParams) (sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) GetTasks(ctx context.Context, arg sqlcgen.GetTasksParams) ([]sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) GetTasksByNoteID(ctx context.Context, arg sqlcgen.GetTasksByNoteIDParams) ([]sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) GetTodayTasks(ctx context.Context, arg sqlcgen.GetTodayTasksParams) ([]sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) GetUserByEmail(ctx context.Context, email string) (sqlcgen.User, error) { panic("unimplemented") }
func (s *stubWMQuerier) GetUserByID(ctx context.Context, id pgtype.UUID) (sqlcgen.User, error) { panic("unimplemented") }
func (s *stubWMQuerier) GetUserSettings(ctx context.Context, userID pgtype.UUID) (sqlcgen.UserSetting, error) {
	return sqlcgen.UserSetting{}, nil
}
func (s *stubWMQuerier) HardDeleteExpiredContexts(ctx context.Context) error { panic("unimplemented") }
func (s *stubWMQuerier) HardDeleteExpiredNotes(ctx context.Context) error    { panic("unimplemented") }
func (s *stubWMQuerier) HardDeleteExpiredTasks(ctx context.Context) error    { panic("unimplemented") }
func (s *stubWMQuerier) ListDeviceTokensByUser(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.DeviceToken, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) RemoveTagFromNote(ctx context.Context, arg sqlcgen.RemoveTagFromNoteParams) error {
	panic("unimplemented")
}
func (s *stubWMQuerier) RevokeAllUserRefreshTokens(ctx context.Context, userID pgtype.UUID) error {
	panic("unimplemented")
}
func (s *stubWMQuerier) RevokeRefreshToken(ctx context.Context, id pgtype.UUID) error { panic("unimplemented") }
func (s *stubWMQuerier) SearchMemoriesByEmbedding(ctx context.Context, arg sqlcgen.SearchMemoriesByEmbeddingParams) ([]sqlcgen.SearchMemoriesByEmbeddingRow, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) SearchNotesFTS(ctx context.Context, arg sqlcgen.SearchNotesFTSParams) ([]sqlcgen.SearchNotesFTSRow, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) SearchNotesHybrid(ctx context.Context, arg sqlcgen.SearchNotesHybridParams) ([]sqlcgen.SearchNotesHybridRow, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) SearchNotesSemantic(ctx context.Context, arg sqlcgen.SearchNotesSemanticParams) ([]sqlcgen.SearchNotesSemanticRow, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) SetInboxContent(ctx context.Context, arg sqlcgen.SetInboxContentParams) (sqlcgen.Note, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) UpdateMemory(ctx context.Context, arg sqlcgen.UpdateMemoryParams) (sqlcgen.Memory, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) UpdateNote(ctx context.Context, arg sqlcgen.UpdateNoteParams) (sqlcgen.Note, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) UpdateNoteEmbeddingStatus(ctx context.Context, arg sqlcgen.UpdateNoteEmbeddingStatusParams) error {
	panic("unimplemented")
}
func (s *stubWMQuerier) UpdateRoutine(ctx context.Context, arg sqlcgen.UpdateRoutineParams) (sqlcgen.Routine, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) UpdateTask(ctx context.Context, arg sqlcgen.UpdateTaskParams) (sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) UpdateUserSettings(ctx context.Context, arg sqlcgen.UpdateUserSettingsParams) (sqlcgen.UserSetting, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) UpsertContext(ctx context.Context, arg sqlcgen.UpsertContextParams) (sqlcgen.Context, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) UpsertNote(ctx context.Context, arg sqlcgen.UpsertNoteParams) (sqlcgen.Note, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) UpsertNoteEmbedding(ctx context.Context, arg sqlcgen.UpsertNoteEmbeddingParams) error {
	panic("unimplemented")
}
func (s *stubWMQuerier) UpsertSoul(ctx context.Context, arg sqlcgen.UpsertSoulParams) (sqlcgen.Soul, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) UpdateSoulProfile(ctx context.Context, arg sqlcgen.UpdateSoulProfileParams) (sqlcgen.Soul, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) UpsertTag(ctx context.Context, arg sqlcgen.UpsertTagParams) (sqlcgen.Tag, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) UpsertTask(ctx context.Context, arg sqlcgen.UpsertTaskParams) (sqlcgen.Task, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) UpdateRoutineLastRunAt(ctx context.Context, id pgtype.UUID) error { panic("unimplemented") }
func (s *stubWMQuerier) UpsertTaskCompletion(ctx context.Context, arg sqlcgen.UpsertTaskCompletionParams) error {
	panic("unimplemented")
}
func (s *stubWMQuerier) GetSyncTaskCompletions(ctx context.Context, arg sqlcgen.GetSyncTaskCompletionsParams) ([]sqlcgen.TaskCompletion, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) GetSyncNoteTags(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.NoteTag, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) UpsertNoteTag(ctx context.Context, arg sqlcgen.UpsertNoteTagParams) error {
	panic("unimplemented")
}
func (s *stubWMQuerier) GetSyncNoteLinks(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.NoteLink, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) UpsertNoteLink(ctx context.Context, arg sqlcgen.UpsertNoteLinkParams) error {
	panic("unimplemented")
}
func (s *stubWMQuerier) CreateNoteShare(ctx context.Context, arg sqlcgen.CreateNoteShareParams) (sqlcgen.NoteShare, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) DeleteNoteShare(ctx context.Context, arg sqlcgen.DeleteNoteShareParams) error {
	panic("unimplemented")
}
func (s *stubWMQuerier) GetNoteOwner(ctx context.Context, id pgtype.UUID) (pgtype.UUID, error) { panic("unimplemented") }
func (s *stubWMQuerier) GetNoteShareForUser(ctx context.Context, arg sqlcgen.GetNoteShareForUserParams) (sqlcgen.NoteShare, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) GetNoteShares(ctx context.Context, noteID pgtype.UUID) ([]sqlcgen.GetNoteSharesRow, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) CreatePendingToolConfirmation(context.Context, sqlcgen.CreatePendingToolConfirmationParams) (sqlcgen.PendingToolConfirmation, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) GetPendingToolConfirmation(context.Context, sqlcgen.GetPendingToolConfirmationParams) (sqlcgen.PendingToolConfirmation, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) ResolvePendingToolConfirmation(context.Context, sqlcgen.ResolvePendingToolConfirmationParams) (sqlcgen.PendingToolConfirmation, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) DeleteAttachment(ctx context.Context, id pgtype.UUID) error { return nil }
func (s *stubWMQuerier) InsertAttachment(ctx context.Context, arg sqlcgen.InsertAttachmentParams) (sqlcgen.Attachment, error) {
	panic("unimplemented")
}
func (s *stubWMQuerier) ListAttachmentsByNote(ctx context.Context, noteID pgtype.UUID) ([]sqlcgen.Attachment, error) {
	return nil, nil
}
func (s *stubWMQuerier) GetNoteOwnerID(ctx context.Context, noteID pgtype.UUID) (pgtype.UUID, error) {
	return pgtype.UUID{}, nil
}
func (s *stubWMQuerier) GetSyncUserNotePreferences(ctx context.Context, arg sqlcgen.GetSyncUserNotePreferencesParams) ([]sqlcgen.UserNotePreference, error) {
	return nil, nil
}
func (s *stubWMQuerier) UpsertUserNotePreference(ctx context.Context, arg sqlcgen.UpsertUserNotePreferenceParams) (sqlcgen.UserNotePreference, error) {
	return sqlcgen.UserNotePreference{}, nil
}
func (s *stubWMQuerier) InsertNode(ctx context.Context, arg sqlcgen.InsertNodeParams) (sqlcgen.NoteNode, error) {
	return sqlcgen.NoteNode{}, nil
}
func (s *stubWMQuerier) UpdateNode(ctx context.Context, arg sqlcgen.UpdateNodeParams) (sqlcgen.NoteNode, error) {
	return sqlcgen.NoteNode{}, nil
}
func (s *stubWMQuerier) DeleteNode(ctx context.Context, id pgtype.UUID) error {
	return nil
}
func (s *stubWMQuerier) GetNodesByNoteId(ctx context.Context, noteID pgtype.UUID) ([]sqlcgen.NoteNode, error) {
	return nil, nil
}
func (s *stubWMQuerier) GetTasksByNodeID(ctx context.Context, nodeID pgtype.UUID) ([]sqlcgen.Task, error) {
	return nil, nil
}

var _ sqlcgen.Querier = (*stubWMQuerier)(nil)

func TestWorkingMemory_SetGet(t *testing.T) {
	q := &stubWMQuerier{vals: make(map[string]string)}
	svc := NewWorkingMemoryService(q)

	uid := pgtype.UUID{Bytes: [16]byte{1}, Valid: true}
	sid := pgtype.UUID{Bytes: [16]byte{2}, Valid: true}

	if err := svc.Set(context.Background(), uid, sid, "foo", "bar"); err != nil {
		t.Fatalf("Set: %v", err)
	}

	val, err := svc.Get(context.Background(), uid, sid, "foo")
	if err != nil {
		t.Fatalf("Get: %v", err)
	}
	if val != "bar" {
		t.Fatalf("Get: want %q, got %q", "bar", val)
	}
}

func TestWorkingMemory_Overwrite(t *testing.T) {
	q := &stubWMQuerier{vals: make(map[string]string)}
	svc := NewWorkingMemoryService(q)

	uid := pgtype.UUID{Bytes: [16]byte{1}, Valid: true}
	sid := pgtype.UUID{Bytes: [16]byte{2}, Valid: true}

	if err := svc.Set(context.Background(), uid, sid, "foo", "bar"); err != nil {
		t.Fatalf("Set: %v", err)
	}
	if err := svc.Set(context.Background(), uid, sid, "foo", "baz"); err != nil {
		t.Fatalf("Set overwrite: %v", err)
	}

	val, err := svc.Get(context.Background(), uid, sid, "foo")
	if err != nil {
		t.Fatalf("Get: %v", err)
	}
	if val != "baz" {
		t.Fatalf("Get after overwrite: want %q, got %q", "baz", val)
	}
}

func TestWorkingMemory_GetAll(t *testing.T) {
	q := &stubWMQuerier{vals: make(map[string]string)}
	svc := NewWorkingMemoryService(q)

	uid := pgtype.UUID{Bytes: [16]byte{1}, Valid: true}
	sid := pgtype.UUID{Bytes: [16]byte{2}, Valid: true}

	svc.Set(context.Background(), uid, sid, "a", "1")
	svc.Set(context.Background(), uid, sid, "b", "2")

	all, err := svc.GetAll(context.Background(), uid, sid)
	if err != nil {
		t.Fatalf("GetAll: %v", err)
	}
	if len(all) != 2 {
		t.Fatalf("GetAll: want 2 entries, got %d", len(all))
	}
	if all["a"] != "1" || all["b"] != "2" {
		t.Fatalf("GetAll: want {a:1, b:2}, got %v", all)
	}
}

func TestWorkingMemory_Clear(t *testing.T) {
	q := &stubWMQuerier{vals: make(map[string]string)}
	svc := NewWorkingMemoryService(q)

	uid := pgtype.UUID{Bytes: [16]byte{1}, Valid: true}
	sid := pgtype.UUID{Bytes: [16]byte{2}, Valid: true}

	svc.Set(context.Background(), uid, sid, "a", "1")
	svc.Set(context.Background(), uid, sid, "b", "2")

	if err := svc.Clear(context.Background(), uid, sid); err != nil {
		t.Fatalf("Clear: %v", err)
	}

	all, err := svc.GetAll(context.Background(), uid, sid)
	if err != nil {
		t.Fatalf("GetAll after clear: %v", err)
	}
	if len(all) != 0 {
		t.Fatalf("GetAll after clear: want 0 entries, got %d", len(all))
	}
}

func TestWorkingMemory_ScopedBySession(t *testing.T) {
	q := &stubWMQuerier{vals: make(map[string]string)}
	svc := NewWorkingMemoryService(q)

	uid := pgtype.UUID{Bytes: [16]byte{1}, Valid: true}
	sid1 := pgtype.UUID{Bytes: [16]byte{2}, Valid: true}
	sid2 := pgtype.UUID{Bytes: [16]byte{3}, Valid: true}

	svc.Set(context.Background(), uid, sid1, "foo", "session1")
	svc.Set(context.Background(), uid, sid2, "foo", "session2")

	val1, _ := svc.Get(context.Background(), uid, sid1, "foo")
	if val1 != "session1" {
		t.Fatalf("session1: want %q, got %q", "session1", val1)
	}
	val2, _ := svc.Get(context.Background(), uid, sid2, "foo")
	if val2 != "session2" {
		t.Fatalf("session2: want %q, got %q", "session2", val2)
	}
}
