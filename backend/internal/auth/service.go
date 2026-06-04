// Package auth wires the persistence layer (sqlcgen.Querier) with the
// stateless primitives in pkg/auth (Argon2id, JWT, refresh tokens).
//
// Handlers should always go through Service; the package never returns
// raw sqlcgen errors to callers — it normalises to ErrInvalidCredentials,
// ErrEmailInUse, ErrInvalidRefreshToken so the HTTP layer can map them
// to status codes without leaking storage details.
package auth

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgtype"

	authpkg "github.com/RigleyC/supanotes/pkg/auth"
	"github.com/RigleyC/supanotes/pkg/config"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

var (
	ErrEmailInUse          = errors.New("auth: email already in use")
	ErrInvalidCredentials  = errors.New("auth: invalid credentials")
	ErrInvalidRefreshToken = errors.New("auth: invalid refresh token")
)

const uniqueViolationCode = "23505"

type Service struct {
	q   sqlcgen.Querier
	cfg *config.Config
}

func NewService(q sqlcgen.Querier, cfg *config.Config) *Service {
	return &Service{q: q, cfg: cfg}
}

// Register creates the user, seeds default user_settings (UTC), and
// emits the access/refresh token pair. Email is lowercased before
// insert; password is hashed with Argon2id.
func (s *Service) Register(ctx context.Context, email, password, name string) (*sqlcgen.User, string, string, error) {
	email = strings.ToLower(strings.TrimSpace(email))

	hash, err := authpkg.HashPassword(password)
	if err != nil {
		return nil, "", "", fmt.Errorf("auth: hash password: %w", err)
	}

	user, err := s.q.CreateUser(ctx, sqlcgen.CreateUserParams{
		Email:        email,
		PasswordHash: hash,
		Name:         strings.TrimSpace(name),
	})
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == uniqueViolationCode {
			return nil, "", "", ErrEmailInUse
		}
		return nil, "", "", fmt.Errorf("auth: create user: %w", err)
	}

	if _, err := s.q.CreateUserSettings(ctx, sqlcgen.CreateUserSettingsParams{
		UserID:   user.ID,
		Timezone: "UTC",
	}); err != nil {
		return nil, "", "", fmt.Errorf("auth: create settings: %w", err)
	}

	access, refresh, err := s.generateAuthResponse(ctx, user.ID)
	if err != nil {
		return nil, "", "", err
	}
	return &user, access, refresh, nil
}

// Login validates the credentials in constant time relative to the
// hash, then emits a fresh token pair. Both "user not found" and
// "wrong password" surface as ErrInvalidCredentials.
func (s *Service) Login(ctx context.Context, email, password string) (*sqlcgen.User, string, string, error) {
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

	access, refresh, err := s.generateAuthResponse(ctx, user.ID)
	if err != nil {
		return nil, "", "", err
	}
	return &user, access, refresh, nil
}

// Refresh rotates the supplied refresh token: validates by hash,
// revokes the old row, then mints a new pair. Unknown/expired/revoked
// tokens collapse to ErrInvalidRefreshToken.
func (s *Service) Refresh(ctx context.Context, refreshPlain string) (string, string, error) {
	hashed := authpkg.HashRefreshToken(refreshPlain)

	row, err := s.q.GetRefreshToken(ctx, hashed)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return "", "", ErrInvalidRefreshToken
		}
		return "", "", fmt.Errorf("auth: lookup refresh: %w", err)
	}

	if err := s.q.RevokeRefreshToken(ctx, row.ID); err != nil {
		return "", "", fmt.Errorf("auth: revoke refresh: %w", err)
	}

	return s.generateAuthResponse(ctx, row.UserID)
}

// Logout best-effort revokes the supplied refresh token. Unknown
// tokens are not an error — logout should never leak whether a token
// existed.
func (s *Service) Logout(ctx context.Context, refreshPlain string) error {
	hashed := authpkg.HashRefreshToken(refreshPlain)

	row, err := s.q.GetRefreshToken(ctx, hashed)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil
		}
		return fmt.Errorf("auth: lookup refresh: %w", err)
	}
	return s.q.RevokeRefreshToken(ctx, row.ID)
}

func (s *Service) generateAuthResponse(ctx context.Context, userID pgtype.UUID) (string, string, error) {
	idStr := UUIDToString(userID)

	access, err := authpkg.GenerateAccessToken(idStr, s.cfg.JWTSecret, authpkg.AccessTokenTTL)
	if err != nil {
		return "", "", fmt.Errorf("auth: sign access token: %w", err)
	}

	plain, hash, err := authpkg.GenerateRefreshToken()
	if err != nil {
		return "", "", fmt.Errorf("auth: generate refresh: %w", err)
	}

	expires := pgtype.Timestamptz{Time: time.Now().Add(authpkg.RefreshTokenTTL), Valid: true}
	if _, err := s.q.CreateRefreshToken(ctx, sqlcgen.CreateRefreshTokenParams{
		UserID:    userID,
		TokenHash: hash,
		ExpiresAt: expires,
	}); err != nil {
		return "", "", fmt.Errorf("auth: store refresh: %w", err)
	}

	return access, plain, nil
}

// UUIDToString renders a pgtype.UUID as a canonical hyphenated string,
// or "" when the value is null.
func UUIDToString(u pgtype.UUID) string {
	if !u.Valid {
		return ""
	}
	return uuid.UUID(u.Bytes).String()
}

// UUIDFromString parses a canonical UUID; returns an invalid pgtype.UUID
// and an error on bad input.
func UUIDFromString(s string) (pgtype.UUID, error) {
	parsed, err := uuid.Parse(s)
	if err != nil {
		return pgtype.UUID{}, fmt.Errorf("auth: parse uuid: %w", err)
	}
	return pgtype.UUID{Bytes: parsed, Valid: true}, nil
}
