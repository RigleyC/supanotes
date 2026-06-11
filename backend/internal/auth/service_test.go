package auth

import (
	"context"
	"errors"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/pkg/auth"
	"github.com/RigleyC/supanotes/pkg/config"
	"github.com/RigleyC/supanotes/pkg/uid"
)

// mockQuerier implements sqlcgen.Querier by recording calls and returning
// canned data or errors. Only the methods exercised by the Service are
// fully featured; the rest are stubbed to fail loudly if invoked.
type mockQuerier struct {
	mu sync.Mutex

	users       map[string]sqlcgen.User // key: email
	settings    map[pgtype.UUID]sqlcgen.UserSetting
	refreshByID map[pgtype.UUID]sqlcgen.RefreshToken

	createUserErr     error
	createSettingsErr error
	createRefreshErr  error
	revokeRefreshErr  error
}

func newMockQuerier() *mockQuerier {
	return &mockQuerier{
		users:       map[string]sqlcgen.User{},
		settings:    map[pgtype.UUID]sqlcgen.UserSetting{},
		refreshByID: map[pgtype.UUID]sqlcgen.RefreshToken{},
	}
}

func pgUUID(id uuid.UUID) pgtype.UUID {
	return pgtype.UUID{Bytes: id, Valid: true}
}

func errUniqueViolation() error {
	return &pgconn.PgError{Code: uniqueViolationCode}
}

func (m *mockQuerier) CreateUser(ctx context.Context, arg sqlcgen.CreateUserParams) (sqlcgen.User, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.createUserErr != nil {
		return sqlcgen.User{}, m.createUserErr
	}
	if _, exists := m.users[arg.Email]; exists {
		return sqlcgen.User{}, errUniqueViolation()
	}
	id := uuid.New()
	u := sqlcgen.User{
		ID:           pgUUID(id),
		Email:        arg.Email,
		PasswordHash: arg.PasswordHash,
		Name:         arg.Name,
	}
	m.users[arg.Email] = u
	return u, nil
}

func (m *mockQuerier) CreateUserSettings(ctx context.Context, arg sqlcgen.CreateUserSettingsParams) (sqlcgen.UserSetting, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.createSettingsErr != nil {
		return sqlcgen.UserSetting{}, m.createSettingsErr
	}
	s := sqlcgen.UserSetting{UserID: arg.UserID, Timezone: arg.Timezone}
	m.settings[arg.UserID] = s
	return s, nil
}

func (m *mockQuerier) CreateRefreshToken(ctx context.Context, arg sqlcgen.CreateRefreshTokenParams) (sqlcgen.RefreshToken, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.createRefreshErr != nil {
		return sqlcgen.RefreshToken{}, m.createRefreshErr
	}
	id := uuid.New()
	rt := sqlcgen.RefreshToken{
		ID:        pgUUID(id),
		UserID:    arg.UserID,
		TokenHash: arg.TokenHash,
		ExpiresAt: arg.ExpiresAt,
	}
	m.refreshByID[rt.ID] = rt
	return rt, nil
}

func (m *mockQuerier) GetRefreshToken(ctx context.Context, tokenHash string) (sqlcgen.RefreshToken, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	now := time.Now()
	for _, rt := range m.refreshByID {
		if rt.TokenHash != tokenHash {
			continue
		}
		if rt.RevokedAt.Valid {
			continue
		}
		if !rt.ExpiresAt.Valid || !rt.ExpiresAt.Time.After(now) {
			continue
		}
		return rt, nil
	}
	return sqlcgen.RefreshToken{}, pgx.ErrNoRows
}

func (m *mockQuerier) RevokeRefreshToken(ctx context.Context, id pgtype.UUID) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.revokeRefreshErr != nil {
		return m.revokeRefreshErr
	}
	rt, ok := m.refreshByID[id]
	if !ok {
		return nil
	}
	rt.RevokedAt = pgtype.Timestamptz{Time: time.Now(), Valid: true}
	m.refreshByID[id] = rt
	return nil
}

func (m *mockQuerier) GetUserByEmail(ctx context.Context, email string) (sqlcgen.User, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if u, ok := m.users[email]; ok {
		return u, nil
	}
	return sqlcgen.User{}, pgx.ErrNoRows
}

func (m *mockQuerier) GetUserByID(ctx context.Context, id pgtype.UUID) (sqlcgen.User, error) {
	return sqlcgen.User{}, errors.New("GetUserByID: not implemented in mock")
}
func (m *mockQuerier) GetUserSettings(ctx context.Context, userID pgtype.UUID) (sqlcgen.UserSetting, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if s, ok := m.settings[userID]; ok {
		return s, nil
	}
	return sqlcgen.UserSetting{UserID: userID, Timezone: "UTC", CreatedAt: pgtype.Timestamptz{Valid: true}, UpdatedAt: pgtype.Timestamptz{Valid: true}}, nil
}
func (m *mockQuerier) RevokeAllUserRefreshTokens(ctx context.Context, userID pgtype.UUID) error {
	return errors.New("RevokeAllUserRefreshTokens: not implemented in mock")
}
func (m *mockQuerier) CreateDeviceToken(ctx context.Context, arg sqlcgen.CreateDeviceTokenParams) (sqlcgen.DeviceToken, error) {
	return sqlcgen.DeviceToken{}, errors.New("CreateDeviceToken: not implemented in mock")
}
func (m *mockQuerier) DeleteDeviceToken(ctx context.Context, arg sqlcgen.DeleteDeviceTokenParams) error {
	return errors.New("DeleteDeviceToken: not implemented in mock")
}
func (m *mockQuerier) AddTagToNote(ctx context.Context, arg sqlcgen.AddTagToNoteParams) error {
	return nil
}
func (m *mockQuerier) AppendToInbox(ctx context.Context, arg sqlcgen.AppendToInboxParams) (sqlcgen.Note, error) {
	return sqlcgen.Note{}, nil
}
func (m *mockQuerier) AppendToNoteContent(ctx context.Context, arg sqlcgen.AppendToNoteContentParams) (sqlcgen.Note, error) {
	return sqlcgen.Note{}, nil
}
func (m *mockQuerier) CreateContext(ctx context.Context, arg sqlcgen.CreateContextParams) (sqlcgen.Context, error) {
	return sqlcgen.Context{}, nil
}
func (m *mockQuerier) CreateNote(ctx context.Context, arg sqlcgen.CreateNoteParams) (sqlcgen.Note, error) {
	return sqlcgen.Note{}, nil
}
func (m *mockQuerier) CreateNoteLink(ctx context.Context, arg sqlcgen.CreateNoteLinkParams) error {
	return nil
}
func (m *mockQuerier) CreateTag(ctx context.Context, arg sqlcgen.CreateTagParams) (sqlcgen.Tag, error) {
	return sqlcgen.Tag{}, nil
}
func (m *mockQuerier) DeleteContext(ctx context.Context, arg sqlcgen.DeleteContextParams) error {
	return nil
}
func (m *mockQuerier) DeleteNote(ctx context.Context, arg sqlcgen.DeleteNoteParams) error { return nil }
func (m *mockQuerier) DeleteTag(ctx context.Context, arg sqlcgen.DeleteTagParams) error   { return nil }
func (m *mockQuerier) GetContexts(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.Context, error) {
	return nil, nil
}
func (m *mockQuerier) GetInboxNote(ctx context.Context, userID pgtype.UUID) (sqlcgen.Note, error) {
	return sqlcgen.Note{}, nil
}
func (m *mockQuerier) GetLatestBriefByType(ctx context.Context, arg sqlcgen.GetLatestBriefByTypeParams) (sqlcgen.RoutineLog, error) {
	return sqlcgen.RoutineLog{}, nil
}
func (m *mockQuerier) GetNoteByID(ctx context.Context, arg sqlcgen.GetNoteByIDParams) (sqlcgen.Note, error) {
	return sqlcgen.Note{}, nil
}
func (m *mockQuerier) GetNotes(ctx context.Context, arg sqlcgen.GetNotesParams) ([]sqlcgen.Note, error) {
	return nil, nil
}
func (m *mockQuerier) GetTags(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.Tag, error) {
	return nil, nil
}
func (m *mockQuerier) GetTagsForNote(ctx context.Context, noteID pgtype.UUID) ([]sqlcgen.Tag, error) {
	return nil, nil
}
func (m *mockQuerier) RemoveTagFromNote(ctx context.Context, arg sqlcgen.RemoveTagFromNoteParams) error {
	return nil
}
func (m *mockQuerier) UpdateNote(ctx context.Context, arg sqlcgen.UpdateNoteParams) (sqlcgen.Note, error) {
	return sqlcgen.Note{}, nil
}

func (m *mockQuerier) CreateTask(ctx context.Context, arg sqlcgen.CreateTaskParams) (sqlcgen.Task, error) {
	return sqlcgen.Task{}, nil
}
func (m *mockQuerier) CreateTaskCompletion(ctx context.Context, arg sqlcgen.CreateTaskCompletionParams) (sqlcgen.TaskCompletion, error) {
	return sqlcgen.TaskCompletion{}, nil
}
func (m *mockQuerier) DeleteTask(ctx context.Context, arg sqlcgen.DeleteTaskParams) error { return nil }
func (m *mockQuerier) GetTaskByID(ctx context.Context, arg sqlcgen.GetTaskByIDParams) (sqlcgen.Task, error) {
	return sqlcgen.Task{}, nil
}
func (m *mockQuerier) GetTasks(ctx context.Context, arg sqlcgen.GetTasksParams) ([]sqlcgen.Task, error) {
	return nil, nil
}
func (m *mockQuerier) GetTasksByNoteID(ctx context.Context, arg sqlcgen.GetTasksByNoteIDParams) ([]sqlcgen.Task, error) {
	return nil, nil
}
func (m *mockQuerier) GetTodayTasks(ctx context.Context, arg sqlcgen.GetTodayTasksParams) ([]sqlcgen.Task, error) {
	return nil, nil
}
func (m *mockQuerier) UpdateTask(ctx context.Context, arg sqlcgen.UpdateTaskParams) (sqlcgen.Task, error) {
	return sqlcgen.Task{}, nil
}

func (m *mockQuerier) CreateMemory(ctx context.Context, arg sqlcgen.CreateMemoryParams) (sqlcgen.Memory, error) {
	return sqlcgen.Memory{}, nil
}
func (m *mockQuerier) DeleteMemory(ctx context.Context, arg sqlcgen.DeleteMemoryParams) error {
	return nil
}
func (m *mockQuerier) GetMemories(ctx context.Context, arg sqlcgen.GetMemoriesParams) ([]sqlcgen.Memory, error) {
	return nil, nil
}
func (m *mockQuerier) GetPendingEmbeddings(ctx context.Context, limit int32) ([]sqlcgen.GetPendingEmbeddingsRow, error) {
	return nil, nil
}
func (m *mockQuerier) GetRetryableEmbeddings(ctx context.Context, limit int32) ([]sqlcgen.GetRetryableEmbeddingsRow, error) {
	return nil, nil
}
func (m *mockQuerier) GetSoul(ctx context.Context, userID pgtype.UUID) (sqlcgen.Soul, error) {
	return sqlcgen.Soul{}, nil
}
func (m *mockQuerier) SetInboxContent(ctx context.Context, arg sqlcgen.SetInboxContentParams) (sqlcgen.Note, error) {
	return sqlcgen.Note{}, nil
}
func (m *mockQuerier) UpdateNoteEmbeddingStatus(ctx context.Context, arg sqlcgen.UpdateNoteEmbeddingStatusParams) error {
	return nil
}
func (m *mockQuerier) UpsertNoteEmbedding(ctx context.Context, arg sqlcgen.UpsertNoteEmbeddingParams) error {
	return nil
}
func (m *mockQuerier) UpsertSoul(ctx context.Context, arg sqlcgen.UpsertSoulParams) (sqlcgen.Soul, error) {
	return sqlcgen.Soul{}, nil
}

func (m *mockQuerier) CreateMessage(ctx context.Context, arg sqlcgen.CreateMessageParams) (sqlcgen.Message, error) {
	return sqlcgen.Message{}, nil
}
func (m *mockQuerier) DeleteSessionMessages(ctx context.Context, arg sqlcgen.DeleteSessionMessagesParams) error {
	return nil
}
func (m *mockQuerier) GetMessages(ctx context.Context, arg sqlcgen.GetMessagesParams) ([]sqlcgen.Message, error) {
	return nil, nil
}
func (m *mockQuerier) SearchNotesByEmbedding(ctx context.Context, arg sqlcgen.SearchNotesByEmbeddingParams) ([]sqlcgen.SearchNotesByEmbeddingRow, error) {
	return nil, nil
}
func (m *mockQuerier) SearchMemoriesByEmbedding(ctx context.Context, arg sqlcgen.SearchMemoriesByEmbeddingParams) ([]sqlcgen.SearchMemoriesByEmbeddingRow, error) {
	return nil, nil
}
func (m *mockQuerier) SearchNotesFTS(ctx context.Context, arg sqlcgen.SearchNotesFTSParams) ([]sqlcgen.SearchNotesFTSRow, error) {
	return nil, nil
}
func (m *mockQuerier) SearchNotesSemantic(ctx context.Context, arg sqlcgen.SearchNotesSemanticParams) ([]sqlcgen.SearchNotesSemanticRow, error) {
	return nil, nil
}

func (m *mockQuerier) CreateRoutine(ctx context.Context, arg sqlcgen.CreateRoutineParams) (sqlcgen.Routine, error) {
	return sqlcgen.Routine{}, nil
}
func (m *mockQuerier) UpdateRoutine(ctx context.Context, arg sqlcgen.UpdateRoutineParams) (sqlcgen.Routine, error) {
	return sqlcgen.Routine{}, nil
}
func (m *mockQuerier) GetRoutinesByUser(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.Routine, error) {
	return nil, nil
}
func (m *mockQuerier) GetEnabledRoutines(ctx context.Context) ([]sqlcgen.GetEnabledRoutinesRow, error) {
	return nil, nil
}
func (m *mockQuerier) CreateRoutineLog(ctx context.Context, arg sqlcgen.CreateRoutineLogParams) (sqlcgen.RoutineLog, error) {
	return sqlcgen.RoutineLog{}, nil
}
func (m *mockQuerier) GetRoutineLogsByUser(ctx context.Context, arg sqlcgen.GetRoutineLogsByUserParams) ([]sqlcgen.RoutineLog, error) {
	return nil, nil
}
func (m *mockQuerier) CleanupOldMessages(ctx context.Context) error { return nil }
func (m *mockQuerier) CountNotes(ctx context.Context, userID pgtype.UUID) (int64, error) {
	return 0, nil
}
func (m *mockQuerier) CountTasks(ctx context.Context, userID pgtype.UUID) (int64, error) {
	return 0, nil
}
func (m *mockQuerier) CountOpenTasks(ctx context.Context, userID pgtype.UUID) (int64, error) {
	return 0, nil
}
func (m *mockQuerier) CountCompletedTasks(ctx context.Context, userID pgtype.UUID) (int64, error) {
	return 0, nil
}

func testConfig() *config.Config {

	return &config.Config{
		Port:        "8080",
		Environment: "dev",
		JWTSecret:   "test-secret-at-least-32-characters-long-enough",
	}
}

func TestService_Register_Success(t *testing.T) {
	q := newMockQuerier()
	svc := NewService(q, testConfig(), nil)

	session, access, refresh, err := svc.Register(context.Background(), "User@Example.COM  ", "correct-horse-battery", "  Alice  ")
	if err != nil {
		t.Fatalf("Register: %v", err)
	}
	if session == nil {
		t.Fatal("Register: session is nil")
	}
	if session.User.Email != "user@example.com" {
		t.Errorf("Register: email not lowercased, got %q", session.User.Email)
	}
	if session.User.Name != "Alice" {
		t.Errorf("Register: name not trimmed, got %q", session.User.Name)
	}
	if !strings.HasPrefix(session.User.PasswordHash, "$argon2id$") {
		t.Errorf("Register: password hash not Argon2id PHC, got prefix %q", session.User.PasswordHash[:20])
	}
	if access == "" {
		t.Error("Register: empty access token")
	}
	if len(refresh) != 64 {
		t.Errorf("Register: refresh token want 64 hex chars, got %d", len(refresh))
	}
}

func TestService_Register_EmailConflict(t *testing.T) {
	q := newMockQuerier()
	svc := NewService(q, testConfig(), nil)

	_, _, _, err := svc.Register(context.Background(), "dup@example.com", "password-1234", "Bob")
	if err != nil {
		t.Fatalf("first Register: %v", err)
	}
	_, _, _, err = svc.Register(context.Background(), "dup@example.com", "password-1234", "Bob2")
	if !errors.Is(err, ErrEmailInUse) {
		t.Fatalf("second Register: want ErrEmailInUse, got %v", err)
	}
}

func TestService_Login_Success(t *testing.T) {
	q := newMockQuerier()
	svc := NewService(q, testConfig(), nil)

	_, _, _, err := svc.Register(context.Background(), "login@example.com", "supersecret", "Cara")
	if err != nil {
		t.Fatalf("Register: %v", err)
	}

	session, access, refresh, err := svc.Login(context.Background(), "LOGIN@EXAMPLE.COM", "supersecret")
	if err != nil {
		t.Fatalf("Login: %v", err)
	}
	if session.User.Email != "login@example.com" {
		t.Errorf("Login: email mismatch %q", session.User.Email)
	}
	if access == "" || refresh == "" {
		t.Error("Login: empty tokens")
	}
}

func TestService_Login_UnknownUser(t *testing.T) {
	q := newMockQuerier()
	svc := NewService(q, testConfig(), nil)

	_, _, _, err := svc.Login(context.Background(), "ghost@example.com", "anything-here")
	if !errors.Is(err, ErrInvalidCredentials) {
		t.Fatalf("Login unknown: want ErrInvalidCredentials, got %v", err)
	}
}

func TestService_Login_WrongPassword(t *testing.T) {
	q := newMockQuerier()
	svc := NewService(q, testConfig(), nil)

	_, _, _, err := svc.Register(context.Background(), "wp@example.com", "right-password", "Dan")
	if err != nil {
		t.Fatalf("Register: %v", err)
	}
	_, _, _, err = svc.Login(context.Background(), "wp@example.com", "wrong-password")
	if !errors.Is(err, ErrInvalidCredentials) {
		t.Fatalf("Login wrong pw: want ErrInvalidCredentials, got %v", err)
	}
}

func TestService_Refresh_RotatesToken(t *testing.T) {
	q := newMockQuerier()
	svc := NewService(q, testConfig(), nil)

	_, _, oldRefresh, err := svc.Register(context.Background(), "rot@example.com", "password-1234", "Eve")
	if err != nil {
		t.Fatalf("Register: %v", err)
	}

	access1, refresh1, err := svc.Refresh(context.Background(), oldRefresh)
	if err != nil {
		t.Fatalf("Refresh #1: %v", err)
	}
	if refresh1 == oldRefresh {
		t.Error("Refresh: did not rotate token")
	}
	if access1 == "" {
		t.Error("Refresh: empty access token")
	}

	// Old token is revoked: replay must fail.
	_, _, err = svc.Refresh(context.Background(), oldRefresh)
	if !errors.Is(err, ErrInvalidRefreshToken) {
		t.Fatalf("Refresh replay: want ErrInvalidRefreshToken, got %v", err)
	}

	// New token still works.
	_, _, err = svc.Refresh(context.Background(), refresh1)
	if err != nil {
		t.Fatalf("Refresh #2: %v", err)
	}
}

func TestService_Refresh_UnknownToken(t *testing.T) {
	q := newMockQuerier()
	svc := NewService(q, testConfig(), nil)

	_, _, err := svc.Refresh(context.Background(), "deadbeef")
	if !errors.Is(err, ErrInvalidRefreshToken) {
		t.Fatalf("Refresh unknown: want ErrInvalidRefreshToken, got %v", err)
	}
}

func TestService_Logout_RevokesToken(t *testing.T) {
	q := newMockQuerier()
	svc := NewService(q, testConfig(), nil)

	_, _, refresh, err := svc.Register(context.Background(), "lo@example.com", "password-1234", "Finn")
	if err != nil {
		t.Fatalf("Register: %v", err)
	}

	if err := svc.Logout(context.Background(), refresh); err != nil {
		t.Fatalf("Logout: %v", err)
	}
	_, _, err = svc.Refresh(context.Background(), refresh)
	if !errors.Is(err, ErrInvalidRefreshToken) {
		t.Fatalf("Refresh after logout: want ErrInvalidRefreshToken, got %v", err)
	}
}

func TestService_Logout_UnknownTokenIsNoop(t *testing.T) {
	q := newMockQuerier()
	svc := NewService(q, testConfig(), nil)

	if err := svc.Logout(context.Background(), "nope"); err != nil {
		t.Fatalf("Logout unknown: want nil, got %v", err)
	}
}

func TestUUIDHelpers(t *testing.T) {
	original := uuid.New()
	pg := pgUUID(original)

	if got := uid.UUIDToString(pg); got != original.String() {
		t.Errorf("UUIDToString: want %q, got %q", original.String(), got)
	}
	if got := uid.UUIDToString(pgtype.UUID{}); got != "" {
		t.Errorf("UUIDToString(null): want empty, got %q", got)
	}

	parsed, err := uid.UUIDFromString(original.String())
	if err != nil {
		t.Fatalf("UUIDFromString: %v", err)
	}
	if parsed.Bytes != original {
		t.Errorf("UUIDFromString: bytes mismatch")
	}
	if _, err := uid.UUIDFromString("not-a-uuid"); err == nil {
		t.Error("UUIDFromString: want error on bad input")
	}
}

func TestService_Register_RefreshFailureBubblesUp(t *testing.T) {
	q := newMockQuerier()
	q.createRefreshErr = errors.New("store boom")
	svc := NewService(q, testConfig(), nil)

	_, _, _, err := svc.Register(context.Background(), "rf@example.com", "password-1234", "Gus")
	if err == nil {
		t.Fatal("Register with refresh error: want error, got nil")
	}
	if errors.Is(err, ErrEmailInUse) {
		t.Fatalf("Register with refresh error: got ErrEmailInUse, want %v", err)
	}
}

func TestService_Refresh_StoreFailureBubblesUp(t *testing.T) {
	q := newMockQuerier()
	svc := NewService(q, testConfig(), nil)

	_, _, refresh, err := svc.Register(context.Background(), "rf@example.com", "password-1234", "Hana")
	if err != nil {
		t.Fatalf("Register: %v", err)
	}

	q.createRefreshErr = errors.New("store boom")
	_, _, err = svc.Refresh(context.Background(), refresh)
	if err == nil {
		t.Fatal("Refresh with store error: want error, got nil")
	}
}

// Sanity: ensure that the test config's secret actually validates the
// tokens we issue — protects against accidentally switching signing algos.
func TestService_IssuedTokenIsValid(t *testing.T) {
	q := newMockQuerier()
	cfg := testConfig()
	svc := NewService(q, cfg, nil)

	_, access, _, err := svc.Register(context.Background(), "vt@example.com", "password-1234", "Iris")
	if err != nil {
		t.Fatalf("Register: %v", err)
	}
	claims, err := auth.ParseAccessToken(access, cfg.JWTSecret)
	if err != nil {
		t.Fatalf("ParseAccessToken: %v", err)
	}
	if claims.UserID == "" {
		t.Error("claims.UserID empty")
	}
}

func (m *mockQuerier) GetRecentNotes(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.Note, error) {
	return nil, nil
}

func (m *mockQuerier) GetLinkedNotes(ctx context.Context, arg sqlcgen.GetLinkedNotesParams) ([]sqlcgen.Note, error) {
	return nil, nil
}

func (m *mockQuerier) SearchNotesHybrid(ctx context.Context, arg sqlcgen.SearchNotesHybridParams) ([]sqlcgen.SearchNotesHybridRow, error) {
	return nil, nil
}

func (m *mockQuerier) UpdateUserSettings(ctx context.Context, arg sqlcgen.UpdateUserSettingsParams) (sqlcgen.UserSetting, error) {
	return sqlcgen.UserSetting{}, nil
}

func (m *mockQuerier) GetSyncNotes(ctx context.Context, arg sqlcgen.GetSyncNotesParams) ([]sqlcgen.Note, error) {
	return nil, nil
}

func (m *mockQuerier) UpsertNote(ctx context.Context, arg sqlcgen.UpsertNoteParams) (sqlcgen.Note, error) {
	return sqlcgen.Note{}, nil
}

func (m *mockQuerier) GetSyncTasks(ctx context.Context, arg sqlcgen.GetSyncTasksParams) ([]sqlcgen.Task, error) {
	return nil, nil
}

func (m *mockQuerier) UpsertTask(ctx context.Context, arg sqlcgen.UpsertTaskParams) (sqlcgen.Task, error) {
	return sqlcgen.Task{}, nil
}

func (m *mockQuerier) GetSyncContexts(ctx context.Context, arg sqlcgen.GetSyncContextsParams) ([]sqlcgen.Context, error) {
	return nil, nil
}

func (m *mockQuerier) UpsertContext(ctx context.Context, arg sqlcgen.UpsertContextParams) (sqlcgen.Context, error) {
	return sqlcgen.Context{}, nil
}

func (m *mockQuerier) GetSyncTags(ctx context.Context, arg sqlcgen.GetSyncTagsParams) ([]sqlcgen.Tag, error) {
	return nil, nil
}

func (m *mockQuerier) UpsertTag(ctx context.Context, arg sqlcgen.UpsertTagParams) (sqlcgen.Tag, error) {
	return sqlcgen.Tag{}, nil
}

func (m *mockQuerier) ListDeviceTokensByUser(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.DeviceToken, error) {
	return nil, nil
}

func (m *mockQuerier) HardDeleteExpiredNotes(ctx context.Context) error {
	return nil
}

func (m *mockQuerier) HardDeleteExpiredTasks(ctx context.Context) error {
	return nil
}

func (m *mockQuerier) HardDeleteExpiredContexts(ctx context.Context) error {
	return nil
}

func (m *mockQuerier) UpdateRoutineLastRunAt(ctx context.Context, id pgtype.UUID) error {
	return nil
}

func (m *mockQuerier) UpsertTaskCompletion(ctx context.Context, arg sqlcgen.UpsertTaskCompletionParams) error {
	return nil
}
