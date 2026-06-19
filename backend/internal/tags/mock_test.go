package tags

import (
	"context"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

type mockQuerier struct{}

func newMockQuerier() *mockQuerier {
	return &mockQuerier{}
}

func (m *mockQuerier) AddTagToNote(_ context.Context, _ sqlcgen.AddTagToNoteParams) error {
	return nil
}
func (m *mockQuerier) AppendToInbox(_ context.Context, _ sqlcgen.AppendToInboxParams) (sqlcgen.Note, error) {
	return sqlcgen.Note{}, nil
}
func (m *mockQuerier) AppendToNoteContent(_ context.Context, _ sqlcgen.AppendToNoteContentParams) (sqlcgen.Note, error) {
	return sqlcgen.Note{}, nil
}
func (m *mockQuerier) CleanupOldMessages(_ context.Context) error                     { return nil }
func (m *mockQuerier) CountNotes(_ context.Context, _ pgtype.UUID) (int64, error)     { return 0, nil }
func (m *mockQuerier) CountTasks(_ context.Context, _ pgtype.UUID) (int64, error)     { return 0, nil }
func (m *mockQuerier) CountOpenTasks(_ context.Context, _ pgtype.UUID) (int64, error) { return 0, nil }
func (m *mockQuerier) CountCompletedTasks(_ context.Context, _ pgtype.UUID) (int64, error) {
	return 0, nil
}
func (m *mockQuerier) CreateContext(_ context.Context, _ sqlcgen.CreateContextParams) (sqlcgen.Context, error) {
	return sqlcgen.Context{}, nil
}
func (m *mockQuerier) CreateDeviceToken(_ context.Context, _ sqlcgen.CreateDeviceTokenParams) (sqlcgen.DeviceToken, error) {
	return sqlcgen.DeviceToken{}, nil
}
func (m *mockQuerier) CreateMemory(_ context.Context, _ sqlcgen.CreateMemoryParams) (sqlcgen.Memory, error) {
	return sqlcgen.Memory{}, nil
}
func (m *mockQuerier) CreateMessage(_ context.Context, _ sqlcgen.CreateMessageParams) (sqlcgen.Message, error) {
	return sqlcgen.Message{}, nil
}
func (m *mockQuerier) CreateNoteLink(_ context.Context, _ sqlcgen.CreateNoteLinkParams) error {
	return nil
}
func (m *mockQuerier) CreateNote(_ context.Context, _ sqlcgen.CreateNoteParams) (sqlcgen.Note, error) {
	return sqlcgen.Note{}, nil
}
func (m *mockQuerier) CreateRefreshToken(_ context.Context, _ sqlcgen.CreateRefreshTokenParams) (sqlcgen.RefreshToken, error) {
	return sqlcgen.RefreshToken{}, nil
}
func (m *mockQuerier) CreateRoutine(_ context.Context, _ sqlcgen.CreateRoutineParams) (sqlcgen.Routine, error) {
	return sqlcgen.Routine{}, nil
}
func (m *mockQuerier) CreateRoutineLog(_ context.Context, _ sqlcgen.CreateRoutineLogParams) (sqlcgen.RoutineLog, error) {
	return sqlcgen.RoutineLog{}, nil
}
func (m *mockQuerier) CreateTag(_ context.Context, _ sqlcgen.CreateTagParams) (sqlcgen.Tag, error) {
	return sqlcgen.Tag{}, nil
}
func (m *mockQuerier) CreateTask(_ context.Context, _ sqlcgen.CreateTaskParams) (sqlcgen.Task, error) {
	return sqlcgen.Task{}, nil
}
func (m *mockQuerier) CreateTaskCompletion(_ context.Context, _ sqlcgen.CreateTaskCompletionParams) (sqlcgen.TaskCompletion, error) {
	return sqlcgen.TaskCompletion{}, nil
}
func (m *mockQuerier) CreateUser(_ context.Context, _ sqlcgen.CreateUserParams) (sqlcgen.User, error) {
	return sqlcgen.User{}, nil
}
func (m *mockQuerier) CreateUserSettings(_ context.Context, _ sqlcgen.CreateUserSettingsParams) (sqlcgen.UserSetting, error) {
	return sqlcgen.UserSetting{}, nil
}
func (m *mockQuerier) DeleteContext(_ context.Context, _ sqlcgen.DeleteContextParams) error {
	return nil
}
func (m *mockQuerier) DeleteDeviceToken(_ context.Context, _ sqlcgen.DeleteDeviceTokenParams) error {
	return nil
}
func (m *mockQuerier) DeleteMemory(_ context.Context, _ sqlcgen.DeleteMemoryParams) error { return nil }
func (m *mockQuerier) DeleteNote(_ context.Context, _ sqlcgen.DeleteNoteParams) error     { return nil }
func (m *mockQuerier) DeleteSessionMessages(_ context.Context, _ sqlcgen.DeleteSessionMessagesParams) error {
	return nil
}
func (m *mockQuerier) DeleteTag(_ context.Context, _ sqlcgen.DeleteTagParams) error   { return nil }
func (m *mockQuerier) DeleteTask(_ context.Context, _ sqlcgen.DeleteTaskParams) error { return nil }
func (m *mockQuerier) GetContexts(_ context.Context, _ pgtype.UUID) ([]sqlcgen.Context, error) {
	return nil, nil
}
func (m *mockQuerier) GetEnabledRoutines(_ context.Context) ([]sqlcgen.GetEnabledRoutinesRow, error) {
	return nil, nil
}
func (m *mockQuerier) GetInboxNote(_ context.Context, _ pgtype.UUID) (sqlcgen.Note, error) {
	return sqlcgen.Note{}, nil
}
func (m *mockQuerier) GetLatestBriefByType(_ context.Context, _ sqlcgen.GetLatestBriefByTypeParams) (sqlcgen.RoutineLog, error) {
	return sqlcgen.RoutineLog{}, nil
}
func (m *mockQuerier) GetLinkedNotes(_ context.Context, _ sqlcgen.GetLinkedNotesParams) ([]sqlcgen.Note, error) {
	return nil, nil
}
func (m *mockQuerier) GetMemories(_ context.Context, _ sqlcgen.GetMemoriesParams) ([]sqlcgen.Memory, error) {
	return nil, nil
}
func (m *mockQuerier) GetMessages(_ context.Context, _ sqlcgen.GetMessagesParams) ([]sqlcgen.Message, error) {
	return nil, nil
}
func (m *mockQuerier) GetNoteByID(_ context.Context, _ sqlcgen.GetNoteByIDParams) (sqlcgen.Note, error) {
	return sqlcgen.Note{}, nil
}
func (m *mockQuerier) GetNotes(_ context.Context, _ sqlcgen.GetNotesParams) ([]sqlcgen.Note, error) {
	return nil, nil
}
func (m *mockQuerier) GetRecentNotes(_ context.Context, _ pgtype.UUID) ([]sqlcgen.Note, error) {
	return nil, nil
}
func (m *mockQuerier) GetRefreshToken(_ context.Context, _ string) (sqlcgen.RefreshToken, error) {
	return sqlcgen.RefreshToken{}, nil
}
func (m *mockQuerier) GetRetryableEmbeddings(_ context.Context, _ int32) ([]sqlcgen.GetRetryableEmbeddingsRow, error) {
	return nil, nil
}
func (m *mockQuerier) GetRoutineLogsByUser(_ context.Context, _ sqlcgen.GetRoutineLogsByUserParams) ([]sqlcgen.RoutineLog, error) {
	return nil, nil
}
func (m *mockQuerier) GetRoutinesByUser(_ context.Context, _ pgtype.UUID) ([]sqlcgen.Routine, error) {
	return nil, nil
}
func (m *mockQuerier) GetSoul(_ context.Context, _ pgtype.UUID) (sqlcgen.Soul, error) {
	return sqlcgen.Soul{}, nil
}
func (m *mockQuerier) GetSyncContexts(_ context.Context, _ sqlcgen.GetSyncContextsParams) ([]sqlcgen.Context, error) {
	return nil, nil
}
func (m *mockQuerier) GetSyncNotes(_ context.Context, _ sqlcgen.GetSyncNotesParams) ([]sqlcgen.GetSyncNotesRow, error) {
	return nil, nil
}
func (m *mockQuerier) GetSyncTags(_ context.Context, _ sqlcgen.GetSyncTagsParams) ([]sqlcgen.Tag, error) {
	return nil, nil
}
func (m *mockQuerier) GetSyncTasks(_ context.Context, _ sqlcgen.GetSyncTasksParams) ([]sqlcgen.Task, error) {
	return nil, nil
}
func (m *mockQuerier) GetTags(_ context.Context, _ pgtype.UUID) ([]sqlcgen.Tag, error) {
	return nil, nil
}
func (m *mockQuerier) GetTagsForNote(_ context.Context, _ pgtype.UUID) ([]sqlcgen.Tag, error) {
	return nil, nil
}
func (m *mockQuerier) GetTaskByID(_ context.Context, _ sqlcgen.GetTaskByIDParams) (sqlcgen.Task, error) {
	return sqlcgen.Task{}, nil
}
func (m *mockQuerier) GetTasks(_ context.Context, _ sqlcgen.GetTasksParams) ([]sqlcgen.Task, error) {
	return nil, nil
}
func (m *mockQuerier) GetTasksByNoteID(_ context.Context, _ sqlcgen.GetTasksByNoteIDParams) ([]sqlcgen.Task, error) {
	return nil, nil
}
func (m *mockQuerier) GetTodayTasks(_ context.Context, _ sqlcgen.GetTodayTasksParams) ([]sqlcgen.Task, error) {
	return nil, nil
}
func (m *mockQuerier) GetUserByEmail(_ context.Context, _ string) (sqlcgen.User, error) {
	return sqlcgen.User{}, nil
}
func (m *mockQuerier) GetUserByID(_ context.Context, _ pgtype.UUID) (sqlcgen.User, error) {
	return sqlcgen.User{}, nil
}
func (m *mockQuerier) GetUserSettings(_ context.Context, _ pgtype.UUID) (sqlcgen.UserSetting, error) {
	return sqlcgen.UserSetting{}, nil
}
func (m *mockQuerier) HardDeleteExpiredContexts(_ context.Context) error { return nil }
func (m *mockQuerier) HardDeleteExpiredNotes(_ context.Context) error    { return nil }
func (m *mockQuerier) HardDeleteExpiredTasks(_ context.Context) error    { return nil }
func (m *mockQuerier) ListDeviceTokensByUser(_ context.Context, _ pgtype.UUID) ([]sqlcgen.DeviceToken, error) {
	return nil, nil
}
func (m *mockQuerier) RemoveTagFromNote(_ context.Context, _ sqlcgen.RemoveTagFromNoteParams) error {
	return nil
}
func (m *mockQuerier) RevokeAllUserRefreshTokens(_ context.Context, _ pgtype.UUID) error { return nil }
func (m *mockQuerier) RevokeRefreshToken(_ context.Context, _ pgtype.UUID) error         { return nil }
func (m *mockQuerier) SearchMemoriesByEmbedding(_ context.Context, _ sqlcgen.SearchMemoriesByEmbeddingParams) ([]sqlcgen.SearchMemoriesByEmbeddingRow, error) {
	return nil, nil
}
func (m *mockQuerier) SearchNotesByEmbedding(_ context.Context, _ sqlcgen.SearchNotesByEmbeddingParams) ([]sqlcgen.SearchNotesByEmbeddingRow, error) {
	return nil, nil
}
func (m *mockQuerier) SearchNotesFTS(_ context.Context, _ sqlcgen.SearchNotesFTSParams) ([]sqlcgen.SearchNotesFTSRow, error) {
	return nil, nil
}
func (m *mockQuerier) SearchNotesHybrid(_ context.Context, _ sqlcgen.SearchNotesHybridParams) ([]sqlcgen.SearchNotesHybridRow, error) {
	return nil, nil
}
func (m *mockQuerier) SearchNotesSemantic(_ context.Context, _ sqlcgen.SearchNotesSemanticParams) ([]sqlcgen.SearchNotesSemanticRow, error) {
	return nil, nil
}
func (m *mockQuerier) SetInboxContent(_ context.Context, _ sqlcgen.SetInboxContentParams) (sqlcgen.Note, error) {
	return sqlcgen.Note{}, nil
}
func (m *mockQuerier) UpdateNote(_ context.Context, _ sqlcgen.UpdateNoteParams) (sqlcgen.Note, error) {
	return sqlcgen.Note{}, nil
}
func (m *mockQuerier) UpdateNoteEmbeddingStatus(_ context.Context, _ sqlcgen.UpdateNoteEmbeddingStatusParams) error {
	return nil
}
func (m *mockQuerier) UpdateRoutine(_ context.Context, _ sqlcgen.UpdateRoutineParams) (sqlcgen.Routine, error) {
	return sqlcgen.Routine{}, nil
}
func (m *mockQuerier) UpdateTask(_ context.Context, _ sqlcgen.UpdateTaskParams) (sqlcgen.Task, error) {
	return sqlcgen.Task{}, nil
}
func (m *mockQuerier) UpdateUserSettings(_ context.Context, _ sqlcgen.UpdateUserSettingsParams) (sqlcgen.UserSetting, error) {
	return sqlcgen.UserSetting{}, nil
}
func (m *mockQuerier) UpsertContext(_ context.Context, _ sqlcgen.UpsertContextParams) (sqlcgen.Context, error) {
	return sqlcgen.Context{}, nil
}
func (m *mockQuerier) UpsertNote(_ context.Context, _ sqlcgen.UpsertNoteParams) (sqlcgen.Note, error) {
	return sqlcgen.Note{}, nil
}
func (m *mockQuerier) UpsertNoteEmbedding(_ context.Context, _ sqlcgen.UpsertNoteEmbeddingParams) error {
	return nil
}
func (m *mockQuerier) UpsertSoul(_ context.Context, _ sqlcgen.UpsertSoulParams) (sqlcgen.Soul, error) {
	return sqlcgen.Soul{}, nil
}
func (m *mockQuerier) UpsertTag(_ context.Context, _ sqlcgen.UpsertTagParams) (sqlcgen.Tag, error) {
	return sqlcgen.Tag{}, nil
}
func (m *mockQuerier) UpsertTask(_ context.Context, _ sqlcgen.UpsertTaskParams) (sqlcgen.Task, error) {
	return sqlcgen.Task{}, nil
}
func (m *mockQuerier) UpdateRoutineLastRunAt(_ context.Context, _ pgtype.UUID) error {
	return nil
}

func (m *mockQuerier) UpsertTaskCompletion(_ context.Context, _ sqlcgen.UpsertTaskCompletionParams) error {
	return nil
}

func (m *mockQuerier) GetSyncTaskCompletions(_ context.Context, _ sqlcgen.GetSyncTaskCompletionsParams) ([]sqlcgen.TaskCompletion, error) {
	return nil, nil
}
func (m *mockQuerier) GetSyncNoteTags(_ context.Context, _ pgtype.UUID) ([]sqlcgen.NoteTag, error) {
	return nil, nil
}
func (m *mockQuerier) UpsertNoteTag(_ context.Context, _ sqlcgen.UpsertNoteTagParams) error {
	return nil
}
func (m *mockQuerier) GetSyncNoteLinks(_ context.Context, _ pgtype.UUID) ([]sqlcgen.NoteLink, error) {
	return nil, nil
}
func (m *mockQuerier) UpsertNoteLink(_ context.Context, _ sqlcgen.UpsertNoteLinkParams) error {
	return nil
}
func (m *mockQuerier) CreateNoteShare(_ context.Context, _ sqlcgen.CreateNoteShareParams) (sqlcgen.NoteShare, error) {
	return sqlcgen.NoteShare{}, nil
}
func (m *mockQuerier) DeleteNoteShare(_ context.Context, _ sqlcgen.DeleteNoteShareParams) error {
	return nil
}
func (m *mockQuerier) GetNoteOwner(_ context.Context, _ pgtype.UUID) (pgtype.UUID, error) {
	return pgtype.UUID{}, nil
}
func (m *mockQuerier) GetNoteShareForUser(_ context.Context, _ sqlcgen.GetNoteShareForUserParams) (sqlcgen.NoteShare, error) {
	return sqlcgen.NoteShare{}, nil
}
func (m *mockQuerier) GetNoteShares(_ context.Context, _ pgtype.UUID) ([]sqlcgen.GetNoteSharesRow, error) {
	return nil, nil
}
func (m *mockQuerier) CreatePendingToolConfirmation(_ context.Context, _ sqlcgen.CreatePendingToolConfirmationParams) (sqlcgen.PendingToolConfirmation, error) {
	panic("unimplemented")
}
func (m *mockQuerier) GetPendingToolConfirmation(_ context.Context, _ sqlcgen.GetPendingToolConfirmationParams) (sqlcgen.PendingToolConfirmation, error) {
	panic("unimplemented")
}
func (m *mockQuerier) ResolvePendingToolConfirmation(_ context.Context, _ sqlcgen.ResolvePendingToolConfirmationParams) (sqlcgen.PendingToolConfirmation, error) {
	panic("unimplemented")
}

func (m *mockQuerier) GetRecentlyCompletedTasks(ctx context.Context, arg sqlcgen.GetRecentlyCompletedTasksParams) ([]sqlcgen.Task, error) {
	return nil, nil
}

func (m *mockQuerier) CountOverdueTasks(ctx context.Context, userID pgtype.UUID) (int64, error) {
	return 0, nil
}

func (m *mockQuerier) SearchTasks(ctx context.Context, arg sqlcgen.SearchTasksParams) ([]sqlcgen.Task, error) {
	return nil, nil
}
