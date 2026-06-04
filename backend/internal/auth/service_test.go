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
)

// mockQuerier implements sqlcgen.Querier by recording calls and returning
// canned data or errors. Only the methods exercised by the Service are
// fully featured; the rest are stubbed to fail loudly if invoked.
type mockQuerier struct {
	mu sync.Mutex

	users       map[string]sqlcgen.User // key: email
	settings    map[pgtype.UUID]sqlcgen.UserSetting
	refreshByID map[pgtype.UUID]sqlcgen.RefreshToken

	createUserErr        error
	createSettingsErr    error
	createRefreshErr     error
	revokeRefreshErr     error
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
	return sqlcgen.UserSetting{}, errors.New("GetUserSettings: not implemented in mock")
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

func testConfig() *config.Config {
	return &config.Config{
		Port:        "8080",
		Environment: "dev",
		JWTSecret:   "test-secret-at-least-32-characters-long-enough",
	}
}

func TestService_Register_Success(t *testing.T) {
	q := newMockQuerier()
	svc := NewService(q, testConfig())

	user, access, refresh, err := svc.Register(context.Background(), "User@Example.COM  ", "correct-horse-battery", "  Alice  ")
	if err != nil {
		t.Fatalf("Register: %v", err)
	}
	if user == nil {
		t.Fatal("Register: user is nil")
	}
	if user.Email != "user@example.com" {
		t.Errorf("Register: email not lowercased, got %q", user.Email)
	}
	if user.Name != "Alice" {
		t.Errorf("Register: name not trimmed, got %q", user.Name)
	}
	if !strings.HasPrefix(user.PasswordHash, "$argon2id$") {
		t.Errorf("Register: password hash not Argon2id PHC, got prefix %q", user.PasswordHash[:20])
	}
	if access == "" {
		t.Error("Register: empty access token")
	}
	if len(refresh) != 64 {
		t.Errorf("Register: refresh token want 64 hex chars, got %d", len(refresh))
	}
	if _, ok := q.settings[user.ID]; !ok {
		t.Error("Register: user settings not seeded")
	}
}

func TestService_Register_EmailConflict(t *testing.T) {
	q := newMockQuerier()
	svc := NewService(q, testConfig())

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
	svc := NewService(q, testConfig())

	_, _, _, err := svc.Register(context.Background(), "login@example.com", "supersecret", "Cara")
	if err != nil {
		t.Fatalf("Register: %v", err)
	}

	user, access, refresh, err := svc.Login(context.Background(), "LOGIN@EXAMPLE.COM", "supersecret")
	if err != nil {
		t.Fatalf("Login: %v", err)
	}
	if user.Email != "login@example.com" {
		t.Errorf("Login: email mismatch %q", user.Email)
	}
	if access == "" || refresh == "" {
		t.Error("Login: empty tokens")
	}
}

func TestService_Login_UnknownUser(t *testing.T) {
	q := newMockQuerier()
	svc := NewService(q, testConfig())

	_, _, _, err := svc.Login(context.Background(), "ghost@example.com", "anything-here")
	if !errors.Is(err, ErrInvalidCredentials) {
		t.Fatalf("Login unknown: want ErrInvalidCredentials, got %v", err)
	}
}

func TestService_Login_WrongPassword(t *testing.T) {
	q := newMockQuerier()
	svc := NewService(q, testConfig())

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
	svc := NewService(q, testConfig())

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
	svc := NewService(q, testConfig())

	_, _, err := svc.Refresh(context.Background(), "deadbeef")
	if !errors.Is(err, ErrInvalidRefreshToken) {
		t.Fatalf("Refresh unknown: want ErrInvalidRefreshToken, got %v", err)
	}
}

func TestService_Logout_RevokesToken(t *testing.T) {
	q := newMockQuerier()
	svc := NewService(q, testConfig())

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
	svc := NewService(q, testConfig())

	if err := svc.Logout(context.Background(), "nope"); err != nil {
		t.Fatalf("Logout unknown: want nil, got %v", err)
	}
}

func TestUUIDHelpers(t *testing.T) {
	original := uuid.New()
	pg := pgUUID(original)

	if got := UUIDToString(pg); got != original.String() {
		t.Errorf("UUIDToString: want %q, got %q", original.String(), got)
	}
	if got := UUIDToString(pgtype.UUID{}); got != "" {
		t.Errorf("UUIDToString(null): want empty, got %q", got)
	}

	parsed, err := UUIDFromString(original.String())
	if err != nil {
		t.Fatalf("UUIDFromString: %v", err)
	}
	if parsed.Bytes != original {
		t.Errorf("UUIDFromString: bytes mismatch")
	}
	if _, err := UUIDFromString("not-a-uuid"); err == nil {
		t.Error("UUIDFromString: want error on bad input")
	}
}

func TestService_Register_SettingsFailureBubblesUp(t *testing.T) {
	q := newMockQuerier()
	q.createSettingsErr = errors.New("settings boom")
	svc := NewService(q, testConfig())

	_, _, _, err := svc.Register(context.Background(), "sf@example.com", "password-1234", "Gus")
	if err == nil {
		t.Fatal("Register with settings error: want error, got nil")
	}
	if errors.Is(err, ErrEmailInUse) {
		t.Fatalf("Register with settings error: got ErrEmailInUse, want %v", err)
	}
}

func TestService_Refresh_StoreFailureBubblesUp(t *testing.T) {
	q := newMockQuerier()
	svc := NewService(q, testConfig())

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
	svc := NewService(q, cfg)

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
