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
	sqlcgen.Querier
	mu sync.Mutex

	users       map[string]sqlcgen.User // key: email
	settings    map[pgtype.UUID]sqlcgen.UserSetting
	refreshByID map[pgtype.UUID]sqlcgen.RefreshToken

	createUserErr     error
	createSettingsErr error
	createRefreshErr  error
	revokeRefreshErr  error
	revokeAllErr      error
	revokeAllUserID   pgtype.UUID
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
		FamilyID:  pgUUID(uuid.New()),
	}
	m.refreshByID[rt.ID] = rt
	return rt, nil
}

func (m *mockQuerier) CreateRotatedRefreshToken(ctx context.Context, arg sqlcgen.CreateRotatedRefreshTokenParams) (sqlcgen.RefreshToken, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.createRefreshErr != nil {
		return sqlcgen.RefreshToken{}, m.createRefreshErr
	}
	rt := sqlcgen.RefreshToken{
		ID:        pgUUID(uuid.New()),
		UserID:    arg.UserID,
		TokenHash: arg.TokenHash,
		ExpiresAt: arg.ExpiresAt,
		FamilyID:  arg.FamilyID,
		ParentID:  arg.ParentID,
	}
	m.refreshByID[rt.ID] = rt
	return rt, nil
}

func (m *mockQuerier) ConsumeRefreshToken(ctx context.Context, tokenHash string) (sqlcgen.RefreshToken, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	now := time.Now()
	for id, rt := range m.refreshByID {
		if rt.TokenHash != tokenHash || rt.RevokedAt.Valid || rt.ConsumedAt.Valid || !rt.ExpiresAt.Valid || !rt.ExpiresAt.Time.After(now) {
			continue
		}
		rt.ConsumedAt = pgtype.Timestamptz{Time: now, Valid: true}
		m.refreshByID[id] = rt
		return rt, nil
	}
	return sqlcgen.RefreshToken{}, pgx.ErrNoRows
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

func (m *mockQuerier) GetRefreshTokenRecord(ctx context.Context, tokenHash string) (sqlcgen.RefreshToken, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	for _, rt := range m.refreshByID {
		if rt.TokenHash == tokenHash {
			return rt, nil
		}
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

func (m *mockQuerier) RevokeRefreshTokenFamily(ctx context.Context, familyID pgtype.UUID) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.revokeRefreshErr != nil {
		return m.revokeRefreshErr
	}
	now := time.Now()
	for id, rt := range m.refreshByID {
		if rt.FamilyID != familyID {
			continue
		}
		rt.RevokedAt = pgtype.Timestamptz{Time: now, Valid: true}
		rt.ReuseDetectedAt = pgtype.Timestamptz{Time: now, Valid: true}
		m.refreshByID[id] = rt
	}
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
	if m.revokeAllErr != nil {
		return m.revokeAllErr
	}
	now := time.Now()
	m.mu.Lock()
	defer m.mu.Unlock()
	m.revokeAllUserID = userID
	for id, rt := range m.refreshByID {
		if rt.UserID != userID {
			continue
		}
		rt.RevokedAt = pgtype.Timestamptz{Time: now, Valid: true}
		m.refreshByID[id] = rt
	}
	return nil
}
func (m *mockQuerier) CreateNote(ctx context.Context, arg sqlcgen.CreateNoteParams) (sqlcgen.Note, error) {
	return sqlcgen.Note{}, nil
}
func (m *mockQuerier) DeleteNote(ctx context.Context, arg sqlcgen.DeleteNoteParams) error { return nil }
func (m *mockQuerier) GetNoteByID(ctx context.Context, arg sqlcgen.GetNoteByIDParams) (sqlcgen.GetNoteByIDRow, error) {
	return sqlcgen.GetNoteByIDRow{}, nil
}
func (m *mockQuerier) GetNotes(ctx context.Context, arg sqlcgen.GetNotesParams) ([]sqlcgen.GetNotesRow, error) {
	return nil, nil
}
func (m *mockQuerier) UpdateNote(ctx context.Context, arg sqlcgen.UpdateNoteParams) (sqlcgen.Note, error) {
	return sqlcgen.Note{}, nil
}
func (m *mockQuerier) UpdateNoteContent(ctx context.Context, arg sqlcgen.UpdateNoteContentParams) error {
	return nil
}
func (m *mockQuerier) CountNotes(ctx context.Context, userID pgtype.UUID) (int64, error) {
	return 0, nil
}
func (m *mockQuerier) GetRecentNotes(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.GetRecentNotesRow, error) {
	return nil, nil
}
func (m *mockQuerier) GetLinkedNotes(ctx context.Context, arg sqlcgen.GetLinkedNotesParams) ([]sqlcgen.Note, error) {
	return nil, nil
}
func (m *mockQuerier) CreateNoteLink(ctx context.Context, arg sqlcgen.CreateNoteLinkParams) error {
	return nil
}
func (m *mockQuerier) GetAllNotesForMigration(ctx context.Context) ([]sqlcgen.GetAllNotesForMigrationRow, error) {
	return nil, nil
}
func (m *mockQuerier) HardDeleteOldNotes(ctx context.Context) error       { return nil }
func (m *mockQuerier) TryAcquireGCLock(ctx context.Context) (bool, error) { return true, nil }
func (m *mockQuerier) CreateNoteShare(ctx context.Context, arg sqlcgen.CreateNoteShareParams) (sqlcgen.NoteShare, error) {
	return sqlcgen.NoteShare{}, nil
}
func (m *mockQuerier) DeleteNoteShare(ctx context.Context, arg sqlcgen.DeleteNoteShareParams) error {
	return nil
}
func (m *mockQuerier) GetNoteOwner(ctx context.Context, noteID pgtype.UUID) (pgtype.UUID, error) {
	return pgtype.UUID{}, nil
}
func (m *mockQuerier) GetNoteShareForUser(ctx context.Context, arg sqlcgen.GetNoteShareForUserParams) (sqlcgen.NoteShare, error) {
	return sqlcgen.NoteShare{}, nil
}
func (m *mockQuerier) GetNoteShares(ctx context.Context, noteID pgtype.UUID) ([]sqlcgen.GetNoteSharesRow, error) {
	return nil, nil
}
func (m *mockQuerier) InsertAttachment(ctx context.Context, arg sqlcgen.InsertAttachmentParams) (sqlcgen.Attachment, error) {
	return sqlcgen.Attachment{}, nil
}
func (m *mockQuerier) ListAttachmentsByNote(ctx context.Context, noteID pgtype.UUID) ([]sqlcgen.Attachment, error) {
	return nil, nil
}
func (m *mockQuerier) DeleteAttachment(ctx context.Context, id pgtype.UUID) error { return nil }
func (m *mockQuerier) CheckNotePermission(ctx context.Context, arg sqlcgen.CheckNotePermissionParams) (interface{}, error) {
	return nil, nil
}
func (m *mockQuerier) GetNoteDocument(ctx context.Context, id pgtype.UUID) (sqlcgen.GetNoteDocumentRow, error) {
	return sqlcgen.GetNoteDocumentRow{}, nil
}
func (m *mockQuerier) UpdateNoteDocument(ctx context.Context, arg sqlcgen.UpdateNoteDocumentParams) error {
	return nil
}
func (m *mockQuerier) InsertOperation(ctx context.Context, arg sqlcgen.InsertOperationParams) (sqlcgen.NoteOperation, error) {
	return sqlcgen.NoteOperation{}, nil
}
func (m *mockQuerier) GetLastOperation(ctx context.Context, noteID pgtype.UUID) (sqlcgen.NoteOperation, error) {
	return sqlcgen.NoteOperation{}, nil
}
func (m *mockQuerier) GetNoteOperationByOpID(ctx context.Context, arg sqlcgen.GetNoteOperationByOpIDParams) (sqlcgen.NoteOperation, error) {
	return sqlcgen.NoteOperation{}, nil
}
func (m *mockQuerier) GetOperationsSince(ctx context.Context, arg sqlcgen.GetOperationsSinceParams) ([]sqlcgen.NoteOperation, error) {
	return nil, nil
}
func (m *mockQuerier) LockNote(ctx context.Context, id pgtype.UUID) (sqlcgen.LockNoteRow, error) {
	return sqlcgen.LockNoteRow{}, nil
}
func (m *mockQuerier) GetOperationByOpID(ctx context.Context, arg sqlcgen.GetNoteOperationByOpIDParams) (sqlcgen.NoteOperation, error) {
	return sqlcgen.NoteOperation{}, nil
}

func testConfig() *config.Config {

	return &config.Config{
		Port:        "8080",
		Environment: "dev",
		JWTSecret:   "test-secret-at-least-32-characters-long-enough",
		JWTIssuer:   "supanotes-api",
		JWTAudience: "supanotes-client",
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

	// Reusing a consumed token revokes the whole family.
	_, _, err = svc.Refresh(context.Background(), oldRefresh)
	if !errors.Is(err, ErrRefreshTokenReuse) {
		t.Fatalf("Refresh replay: want ErrRefreshTokenReuse, got %v", err)
	}

	// The rotated child is revoked with the family.
	_, _, err = svc.Refresh(context.Background(), refresh1)
	if !errors.Is(err, ErrInvalidRefreshToken) {
		t.Fatalf("Refresh after family revoke: want ErrInvalidRefreshToken, got %v", err)
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

func TestService_RevokeAllSessions(t *testing.T) {
	q := newMockQuerier()
	svc := NewService(q, testConfig(), nil)
	userID := pgUUID(uuid.New())
	otherUserID := pgUUID(uuid.New())

	_, err := q.CreateRefreshToken(context.Background(), sqlcgen.CreateRefreshTokenParams{
		UserID:    userID,
		TokenHash: "user-token",
		ExpiresAt: pgtype.Timestamptz{Time: time.Now().Add(time.Hour), Valid: true},
	})
	if err != nil {
		t.Fatalf("create user token: %v", err)
	}
	_, err = q.CreateRefreshToken(context.Background(), sqlcgen.CreateRefreshTokenParams{
		UserID:    otherUserID,
		TokenHash: "other-token",
		ExpiresAt: pgtype.Timestamptz{Time: time.Now().Add(time.Hour), Valid: true},
	})
	if err != nil {
		t.Fatalf("create other token: %v", err)
	}

	if err := svc.RevokeAllSessions(context.Background(), userID); err != nil {
		t.Fatalf("RevokeAllSessions: %v", err)
	}

	q.mu.Lock()
	defer q.mu.Unlock()
	for _, token := range q.refreshByID {
		if token.UserID == userID && !token.RevokedAt.Valid {
			t.Error("user refresh token was not revoked")
		}
		if token.UserID == otherUserID && token.RevokedAt.Valid {
			t.Error("other user's refresh token was revoked")
		}
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
	claims, err := auth.ParseAccessToken(access, cfg.JWTSecret, auth.TokenOptions{Issuer: cfg.JWTIssuer, Audience: cfg.JWTAudience})
	if err != nil {
		t.Fatalf("ParseAccessToken: %v", err)
	}
	if claims.UserID == "" {
		t.Error("claims.UserID empty")
	}
}

func (m *mockQuerier) UpdateUserSettings(ctx context.Context, arg sqlcgen.UpdateUserSettingsParams) (sqlcgen.UserSetting, error) {
	return sqlcgen.UserSetting{}, nil
}
