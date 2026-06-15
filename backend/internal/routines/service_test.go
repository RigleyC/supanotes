package routines

import (
	"context"
	"errors"
	"testing"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/pkg/llm"
)

// --- mocks ---

type mockRepo struct {
	mock.Mock
}

func (m *mockRepo) CreateRoutine(ctx context.Context, userID pgtype.UUID, rType, cronExpr string, enabled bool) (sqlcgen.Routine, error) {
	args := m.Called(ctx, userID, rType, cronExpr, enabled)
	return args.Get(0).(sqlcgen.Routine), args.Error(1)
}
func (m *mockRepo) UpdateRoutine(ctx context.Context, id, userID pgtype.UUID, cronExpr *string, enabled *bool) (sqlcgen.Routine, error) {
	args := m.Called(ctx, id, userID, cronExpr, enabled)
	return args.Get(0).(sqlcgen.Routine), args.Error(1)
}
func (m *mockRepo) GetRoutinesByUser(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.Routine, error) {
	args := m.Called(ctx, userID)
	return args.Get(0).([]sqlcgen.Routine), args.Error(1)
}
func (m *mockRepo) GetEnabledRoutines(ctx context.Context) ([]sqlcgen.GetEnabledRoutinesRow, error) {
	args := m.Called(ctx)
	return args.Get(0).([]sqlcgen.GetEnabledRoutinesRow), args.Error(1)
}
func (m *mockRepo) CreateRoutineLog(ctx context.Context, routineID, userID pgtype.UUID, status string, content, errorMsg *string) (sqlcgen.RoutineLog, error) {
	args := m.Called(ctx, routineID, userID, status, content, errorMsg)
	return args.Get(0).(sqlcgen.RoutineLog), args.Error(1)
}
func (m *mockRepo) GetRoutineLogsByUser(ctx context.Context, userID pgtype.UUID, limit, offset int32) ([]sqlcgen.RoutineLog, error) {
	args := m.Called(ctx, userID, limit, offset)
	return args.Get(0).([]sqlcgen.RoutineLog), args.Error(1)
}
func (m *mockRepo) GetLatestBriefByType(ctx context.Context, userID pgtype.UUID, briefType string) (sqlcgen.RoutineLog, error) {
	args := m.Called(ctx, userID, briefType)
	return args.Get(0).(sqlcgen.RoutineLog), args.Error(1)
}
func (m *mockRepo) CleanupOldMessages(ctx context.Context) error {
	return m.Called(ctx).Error(0)
}
func (m *mockRepo) HardDeleteExpired(ctx context.Context) error {
	return m.Called(ctx).Error(0)
}
func (m *mockRepo) UpdateRoutineLastRunAt(ctx context.Context, id pgtype.UUID) error {
	return m.Called(ctx, id).Error(0)
}

type mockContextBuilder struct {
	result string
	err    error
}

func (m *mockContextBuilder) BuildForRoutine(_ context.Context, _ pgtype.UUID, _ string) (string, error) {
	return m.result, m.err
}

type mockLLMClient struct {
	resp *llm.Response
	err  error
}

func (m *mockLLMClient) Complete(_ context.Context, _ llm.Request) (*llm.Response, error) {
	return m.resp, m.err
}

type mockLLMFactory struct {
	client llm.Client
}

func (m *mockLLMFactory) For(_ llm.TaskType) llm.Client {
	return m.client
}

// --- tests ---

func TestGetRoutines_Success(t *testing.T) {
	repo := new(mockRepo)
	svc := NewService(repo, nil, nil)

	expected := []sqlcgen.Routine{{ID: pgtype.UUID{Bytes: [16]byte{1}, Valid: true}, Type: "daily"}}
	repo.On("GetRoutinesByUser", mock.Anything, mock.Anything).Return(expected, nil)

	got, err := svc.GetRoutines(context.Background(), pgtype.UUID{})
	require.NoError(t, err)
	assert.Len(t, got, 1)
	assert.Equal(t, "daily", got[0].Type)
}

func TestGetRoutines_Error(t *testing.T) {
	repo := new(mockRepo)
	svc := NewService(repo, nil, nil)

	repo.On("GetRoutinesByUser", mock.Anything, mock.Anything).Return([]sqlcgen.Routine(nil), errors.New("db err"))

	_, err := svc.GetRoutines(context.Background(), pgtype.UUID{})
	assert.ErrorContains(t, err, "db err")
}

func TestUpdateRoutine_Success(t *testing.T) {
	repo := new(mockRepo)
	svc := NewService(repo, nil, nil)

	enabled := true
	expected := sqlcgen.Routine{ID: pgtype.UUID{Bytes: [16]byte{1}, Valid: true}, Enabled: true}
	repo.On("UpdateRoutine", mock.Anything, mock.Anything, mock.Anything, (*string)(nil), &enabled).Return(expected, nil)

	got, err := svc.UpdateRoutine(context.Background(), pgtype.UUID{Bytes: [16]byte{1}, Valid: true}, pgtype.UUID{}, nil, &enabled)
	require.NoError(t, err)
	assert.True(t, got.Enabled)
}

func TestUpdateRoutine_Error(t *testing.T) {
	repo := new(mockRepo)
	svc := NewService(repo, nil, nil)

	repo.On("UpdateRoutine", mock.Anything, mock.Anything, mock.Anything, (*string)(nil), (*bool)(nil)).Return(sqlcgen.Routine{}, errors.New("not found"))

	_, err := svc.UpdateRoutine(context.Background(), pgtype.UUID{Bytes: [16]byte{1}, Valid: true}, pgtype.UUID{}, nil, nil)
	assert.ErrorContains(t, err, "not found")
}

func TestUpdateRoutineByType_Success(t *testing.T) {
	repo := new(mockRepo)
	svc := NewService(repo, nil, nil)

	routines := []sqlcgen.Routine{
		{ID: pgtype.UUID{Bytes: [16]byte{1}, Valid: true}, Type: "daily", CronExpr: "0 8 * * 1,2,3,4,5"},
	}
	repo.On("GetRoutinesByUser", mock.Anything, mock.Anything).Return(routines, nil)
	repo.On("UpdateRoutine", mock.Anything, mock.Anything, mock.Anything, (*string)(nil), (*bool)(nil)).Return(routines[0], nil)

	got, err := svc.UpdateRoutineByType(context.Background(), pgtype.UUID{}, "daily", nil, nil, nil, nil)
	require.NoError(t, err)
	assert.NotNil(t, got)
	assert.Equal(t, "daily", got.Type)
}

func TestUpdateRoutineByType_WithCronUpdate(t *testing.T) {
	repo := new(mockRepo)
	svc := NewService(repo, nil, nil)

	routines := []sqlcgen.Routine{
		{ID: pgtype.UUID{Bytes: [16]byte{1}, Valid: true}, Type: "daily", CronExpr: "0 8 * * 1,2,3,4,5"},
	}
	repo.On("GetRoutinesByUser", mock.Anything, mock.Anything).Return(routines, nil)

	timeOfDay := "09:30"
	daysOfWeek := "mon,wed,fri"
	expectedCron := "30 09 * * 1,3,5"
	repo.On("UpdateRoutine", mock.Anything, mock.Anything, mock.Anything, mock.MatchedBy(func(expr *string) bool {
		return expr != nil && *expr == expectedCron
	}), (*bool)(nil)).Return(routines[0], nil)

	got, err := svc.UpdateRoutineByType(context.Background(), pgtype.UUID{}, "daily", &timeOfDay, &daysOfWeek, nil, nil)
	require.NoError(t, err)
	assert.NotNil(t, got)
}

func TestUpdateRoutineByType_NotFound(t *testing.T) {
	repo := new(mockRepo)
	svc := NewService(repo, nil, nil)

	repo.On("GetRoutinesByUser", mock.Anything, mock.Anything).Return([]sqlcgen.Routine{}, nil)

	got, err := svc.UpdateRoutineByType(context.Background(), pgtype.UUID{}, "weekly", nil, nil, nil, nil)
	assert.Nil(t, got)
	assert.ErrorIs(t, err, ErrRoutineNotFound)
}

func TestGetRoutineLogs_Success(t *testing.T) {
	repo := new(mockRepo)
	svc := NewService(repo, nil, nil)

	logs := []sqlcgen.RoutineLog{{ID: pgtype.UUID{Bytes: [16]byte{1}, Valid: true}, Status: "success"}}
	repo.On("GetRoutineLogsByUser", mock.Anything, mock.Anything, int32(50), int32(0)).Return(logs, nil)

	got, err := svc.GetRoutineLogs(context.Background(), pgtype.UUID{}, 50, 0)
	require.NoError(t, err)
	assert.Len(t, got, 1)
}

func TestGetLatestBrief_Success(t *testing.T) {
	repo := new(mockRepo)
	svc := NewService(repo, nil, nil)

	log := sqlcgen.RoutineLog{
		Content: pgtype.Text{String: "brief content", Valid: true},
	}
	repo.On("GetLatestBriefByType", mock.Anything, mock.Anything, "daily").Return(log, nil)

	got, err := svc.GetLatestBrief(context.Background(), pgtype.UUID{}, "daily")
	require.NoError(t, err)
	assert.Equal(t, "brief content", got)
}

func TestGetLatestBrief_NotFound(t *testing.T) {
	repo := new(mockRepo)
	svc := NewService(repo, nil, nil)

	repo.On("GetLatestBriefByType", mock.Anything, mock.Anything, "daily").Return(sqlcgen.RoutineLog{}, ErrBriefNotFound)

	_, err := svc.GetLatestBrief(context.Background(), pgtype.UUID{}, "daily")
	assert.ErrorIs(t, err, ErrBriefNotFound)
}

func TestGetLatestBrief_EmptyContent(t *testing.T) {
	repo := new(mockRepo)
	svc := NewService(repo, nil, nil)

	log := sqlcgen.RoutineLog{Content: pgtype.Text{Valid: false}}
	repo.On("GetLatestBriefByType", mock.Anything, mock.Anything, "daily").Return(log, nil)

	_, err := svc.GetLatestBrief(context.Background(), pgtype.UUID{}, "daily")
	assert.ErrorIs(t, err, ErrBriefNotFound)
}

func TestTestRoutine_Success(t *testing.T) {
	repo := new(mockRepo)
	bldr := &mockContextBuilder{result: "rag context"}
	llmClient := &mockLLMClient{resp: &llm.Response{Content: "generated brief"}}
	llmFactory := &mockLLMFactory{client: llmClient}
	svc := NewService(repo, bldr, llmFactory)

	got, err := svc.TestRoutine(context.Background(), pgtype.UUID{}, "daily")
	require.NoError(t, err)
	assert.Equal(t, "generated brief", got)
}

func TestTestRoutine_ContextBuilderError(t *testing.T) {
	bldr := &mockContextBuilder{err: errors.New("no data")}
	svc := NewService(nil, bldr, nil)

	_, err := svc.TestRoutine(context.Background(), pgtype.UUID{}, "daily")
	assert.ErrorContains(t, err, "no data")
}

func TestBuildBriefPrompt(t *testing.T) {
	got := buildBriefPrompt("daily", "some context")
	assert.Contains(t, got, "Contexto Atual")
	assert.Contains(t, got, "some context")
}
