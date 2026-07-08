package settings

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/dto"
)

type mockQuerier struct {
	mock.Mock
	sqlcgen.Querier
}

func (m *mockQuerier) GetUserSettings(ctx context.Context, userID pgtype.UUID) (sqlcgen.UserSetting, error) {
	args := m.Called(ctx, userID)
	return args.Get(0).(sqlcgen.UserSetting), args.Error(1)
}

func (m *mockQuerier) UpdateUserSettings(ctx context.Context, params sqlcgen.UpdateUserSettingsParams) (sqlcgen.UserSetting, error) {
	args := m.Called(ctx, params)
	return args.Get(0).(sqlcgen.UserSetting), args.Error(1)
}

func TestService_Update(t *testing.T) {
	mq := new(mockQuerier)
	svc := NewService(mq)

	userID := pgtype.UUID{Bytes: [16]byte{1}, Valid: true}

	t.Run("success updating preferences", func(t *testing.T) {
		prefs := map[string]any{"notes_view_mode": "grid"}
		prefsBytes, _ := json.Marshal(prefs)

		expectedParam := sqlcgen.UpdateUserSettingsParams{
			UserID:      userID,
			Timezone:    "",
			Preferences: pgtype.Text{String: string(prefsBytes), Valid: true},
		}

		expectedSetting := sqlcgen.UserSetting{
			UserID:      userID,
			Timezone:    "UTC",
			Preferences: prefsBytes,
		}

		mq.On("UpdateUserSettings", mock.Anything, expectedParam).Return(expectedSetting, nil).Once()

		req := dto.UpdateSettingsRequest{
			Preferences: prefs,
		}

		resp, err := svc.Update(context.Background(), userID, req)
		assert.NoError(t, err)
		assert.Equal(t, "UTC", resp.Timezone)
		assert.Equal(t, prefs, resp.Preferences)

		mq.AssertExpectations(t)
	})
}
