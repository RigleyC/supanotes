package auth

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/dto"
	authpkg "github.com/RigleyC/supanotes/pkg/auth"
	"github.com/RigleyC/supanotes/pkg/config"
	"github.com/RigleyC/supanotes/pkg/uid"
)

var (
	ErrEmailInUse          = errors.New("auth: email already in use")
	ErrInvalidCredentials  = errors.New("auth: invalid credentials")
	ErrInvalidRefreshToken = errors.New("auth: invalid refresh token")
)

const uniqueViolationCode = "23505"

type SessionData struct {
	User     sqlcgen.User
	Settings dto.SettingsResponse
}

type Service struct {
	q    sqlcgen.Querier
	pool *pgxpool.Pool
	cfg  *config.Config
}

func NewService(q sqlcgen.Querier, cfg *config.Config, pool *pgxpool.Pool) *Service {
	return &Service{q: q, pool: pool, cfg: cfg}
}

func (s *Service) inTx(ctx context.Context, fn func(sqlcgen.Querier) error) error {
	if s.pool == nil {
		return fn(s.q)
	}
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("auth: begin tx: %w", err)
	}
	defer tx.Rollback(ctx)
	if err := fn(sqlcgen.New(tx)); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func (s *Service) Register(ctx context.Context, email, password, name string) (*SessionData, string, string, error) {
	email = strings.ToLower(strings.TrimSpace(email))

	hash, err := authpkg.HashPassword(password)
	if err != nil {
		return nil, "", "", fmt.Errorf("auth: hash password: %w", err)
	}

	var session SessionData
	var access, refresh string

	err = s.inTx(ctx, func(q sqlcgen.Querier) error {
		u, err := q.CreateUser(ctx, sqlcgen.CreateUserParams{
			Email:        email,
			PasswordHash: hash,
			Name:         strings.TrimSpace(name),
		})
		if err != nil {
			return err
		}
		session.User = u

		if err := seedUserDefaults(ctx, q, session.User.ID); err != nil {
			return err
		}

		access, refresh, err = s.generateAuthResponse(ctx, q, session.User.ID)
		return err
	})
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == uniqueViolationCode {
			return nil, "", "", ErrEmailInUse
		}
		return nil, "", "", fmt.Errorf("auth: register: %w", err)
	}

	if err := s.loadSessionData(ctx, &session); err != nil {
		return nil, "", "", fmt.Errorf("auth: load session data: %w", err)
	}

	return &session, access, refresh, nil
}

func (s *Service) Login(ctx context.Context, email, password string) (*SessionData, string, string, error) {
	email = strings.ToLower(strings.TrimSpace(email))

	user, err := s.q.GetUserByEmail(ctx, email)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, "", "", ErrInvalidCredentials
		}
		return nil, "", "", fmt.Errorf("auth: lookup user: %w", err)
	}

	ok, err := authpkg.VerifyPassword(password, user.PasswordHash)
	if err != nil || !ok {
		return nil, "", "", ErrInvalidCredentials
	}

	access, refresh, err := s.generateAuthResponse(ctx, s.q, user.ID)
	if err != nil {
		return nil, "", "", err
	}

	session := SessionData{User: user}
	if err := s.loadSessionData(ctx, &session); err != nil {
		return nil, "", "", fmt.Errorf("auth: load session data: %w", err)
	}

	return &session, access, refresh, nil
}

func (s *Service) Refresh(ctx context.Context, refreshPlain string) (string, string, error) {
	hashed := authpkg.HashRefreshToken(refreshPlain)

	var access, refresh string

	err := s.inTx(ctx, func(q sqlcgen.Querier) error {
		row, err := q.GetRefreshToken(ctx, hashed)
		if err != nil {
			return err
		}

		if err := q.RevokeRefreshToken(ctx, row.ID); err != nil {
			return err
		}

		access, refresh, err = s.generateAuthResponse(ctx, q, row.UserID)
		return err
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return "", "", ErrInvalidRefreshToken
		}
		return "", "", fmt.Errorf("auth: refresh: %w", err)
	}

	return access, refresh, nil
}

func (s *Service) Logout(ctx context.Context, refreshPlain string) error {
	hashed := authpkg.HashRefreshToken(refreshPlain)

	return s.inTx(ctx, func(q sqlcgen.Querier) error {
		row, err := q.GetRefreshToken(ctx, hashed)
		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return nil
			}
			return err
		}
		return q.RevokeRefreshToken(ctx, row.ID)
	})
}

func (s *Service) generateAuthResponse(ctx context.Context, q sqlcgen.Querier, userID pgtype.UUID) (string, string, error) {
	idStr := uid.UUIDToString(userID)

	access, err := authpkg.GenerateAccessToken(idStr, s.cfg.JWTSecret, authpkg.AccessTokenTTL)
	if err != nil {
		return "", "", fmt.Errorf("auth: sign access token: %w", err)
	}

	plain, hash, err := authpkg.GenerateRefreshToken()
	if err != nil {
		return "", "", fmt.Errorf("auth: generate refresh: %w", err)
	}

	expires := pgtype.Timestamptz{Time: time.Now().Add(authpkg.RefreshTokenTTL), Valid: true}
	if _, err := q.CreateRefreshToken(ctx, sqlcgen.CreateRefreshTokenParams{
		UserID:    userID,
		TokenHash: hash,
		ExpiresAt: expires,
	}); err != nil {
		return "", "", fmt.Errorf("auth: store refresh: %w", err)
	}

	return access, plain, nil
}

func (s *Service) loadSessionData(ctx context.Context, session *SessionData) error {
	userID := session.User.ID

	settings, err := s.q.GetUserSettings(ctx, userID)
	if err != nil {
		return fmt.Errorf("load settings: %w", err)
	}
	var prefs map[string]any
	if len(settings.Preferences) > 0 {
		_ = json.Unmarshal(settings.Preferences, &prefs)
	}
	if prefs == nil {
		prefs = make(map[string]any)
	}

	session.Settings = dto.SettingsResponse{
		Timezone:    settings.Timezone,
		Preferences: prefs,
		CreatedAt:   settings.CreatedAt.Time.Format(time.RFC3339),
		UpdatedAt:   settings.UpdatedAt.Time.Format(time.RFC3339),
	}

	return nil
}

func seedUserDefaults(ctx context.Context, q sqlcgen.Querier, userID pgtype.UUID) error {
	if _, err := q.CreateUserSettings(ctx, sqlcgen.CreateUserSettingsParams{
		UserID:   userID,
		Timezone: "UTC",
	}); err != nil {
		return fmt.Errorf("auth: seed user settings: %w", err)
	}

	content := "# Boas-vindas\n\nBem-vindo ao SupaNotes!"
	note, err := q.CreateNote(ctx, sqlcgen.CreateNoteParams{
		UserID:  userID,
		Content: content,
	})
	if err != nil {
		return fmt.Errorf("auth: seed welcome note: %w", err)
	}

	docJSON := []byte(`{
		"schemaVersion": 1,
		"blocks": [
			{
				"id": "welcome-header",
				"type": "header1",
				"delta": [{"insert": "Boas-vindas"}],
				"metadata": {}
			},
			{
				"id": "welcome-para",
				"type": "paragraph",
				"delta": [{"insert": "Bem-vindo ao SupaNotes!"}],
				"metadata": {}
			}
		]
	}`)

	if err := q.UpdateNoteDocument(ctx, sqlcgen.UpdateNoteDocumentParams{
		ID:               note.ID,
		Document:         docJSON,
		Revision:         0,
		Content:          content,
		Excerpt:          pgtype.Text{String: "Bem-vindo ao SupaNotes!", Valid: true},
		SnapshotRevision: 0,
	}); err != nil {
		return fmt.Errorf("auth: update welcome note document: %w", err)
	}

	return nil
}
