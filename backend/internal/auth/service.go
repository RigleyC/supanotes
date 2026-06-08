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

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	authpkg "github.com/RigleyC/supanotes/pkg/auth"
	"github.com/RigleyC/supanotes/pkg/config"
	"github.com/RigleyC/supanotes/pkg/uid"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

var (
	ErrEmailInUse          = errors.New("auth: email already in use")
	ErrInvalidCredentials  = errors.New("auth: invalid credentials")
	ErrInvalidRefreshToken = errors.New("auth: invalid refresh token")
)

const uniqueViolationCode = "23505"

type Service struct {
	q    sqlcgen.Querier
	pool *pgxpool.Pool
	cfg  *config.Config
}

func NewService(q sqlcgen.Querier, cfg *config.Config, pool *pgxpool.Pool) *Service {
	return &Service{q: q, pool: pool, cfg: cfg}
}

// inTx runs fn inside a transaction when a pool is available.
// In tests (pool is nil), it runs fn directly on s.q.
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

// Register creates the user, seeds defaults, and emits the access/refresh
// token pair — all inside a single transaction so a failure at any step
// leaves no partial state.
// Email is lowercased before insert; password is hashed with Argon2id.
func (s *Service) Register(ctx context.Context, email, password, name string) (*sqlcgen.User, string, string, error) {
	email = strings.ToLower(strings.TrimSpace(email))

	hash, err := authpkg.HashPassword(password)
	if err != nil {
		return nil, "", "", fmt.Errorf("auth: hash password: %w", err)
	}

	var user sqlcgen.User
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
		user = u

		if err := seedUserDefaults(ctx, q, user.ID); err != nil {
			return err
		}

		access, refresh, err = s.generateAuthResponse(ctx, q, user.ID)
		return err
	})
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == uniqueViolationCode {
			return nil, "", "", ErrEmailInUse
		}
		return nil, "", "", fmt.Errorf("auth: register: %w", err)
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

	access, refresh, err := s.generateAuthResponse(ctx, s.q, user.ID)
	if err != nil {
		return nil, "", "", err
	}
	return &user, access, refresh, nil
}

// Refresh rotates the supplied refresh token: validates by hash,
// revokes the old row, then mints a new pair — all inside a single
// transaction to avoid orphaned tokens or double-use.
// Unknown/expired/revoked tokens collapse to ErrInvalidRefreshToken.
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

// Logout best-effort revokes the supplied refresh token. Unknown
// tokens are not an error — logout should never leak whether a token
// existed.
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

func seedUserDefaults(ctx context.Context, q sqlcgen.Querier, userID pgtype.UUID) error {
	if _, err := q.CreateUserSettings(ctx, sqlcgen.CreateUserSettingsParams{
		UserID:   userID,
		Timezone: "UTC",
	}); err != nil {
		return fmt.Errorf("auth: seed user settings: %w", err)
	}

	title := "Rascunho"
	content := "Bem-vindo ao SupaNotes! Esta é sua nota de inbox, o lugar perfeito para despejar ideias rapidamente."
	if _, err := q.CreateNote(ctx, sqlcgen.CreateNoteParams{
		UserID:          userID,
		Title:           pgtype.Text{String: title, Valid: true},
		Content:         content,
		IsInbox:         true,
		Favorite:        false,
		Archived:        false,
		EmbeddingStatus: "pending",
	}); err != nil {
		return fmt.Errorf("auth: seed inbox note: %w", err)
	}

	personality := "Você é o assistente SupaNotes. Você deve ser claro, objetivo, proativo e prestativo, auxiliando na organização pessoal e resgate de ideias do usuário."
	if _, err := q.UpsertSoul(ctx, sqlcgen.UpsertSoulParams{
		UserID:      userID,
		Personality: personality,
	}); err != nil {
		return fmt.Errorf("auth: seed soul: %w", err)
	}

	if _, err := q.CreateRoutine(ctx, sqlcgen.CreateRoutineParams{
		UserID:   userID,
		Type:     "daily",
		CronExpr: "0 8 * * 1-5",
		Enabled:  true,
	}); err != nil {
		return fmt.Errorf("auth: seed daily routine: %w", err)
	}

	if _, err := q.CreateRoutine(ctx, sqlcgen.CreateRoutineParams{
		UserID:   userID,
		Type:     "weekly",
		CronExpr: "0 9 * * 1",
		Enabled:  true,
	}); err != nil {
		return fmt.Errorf("auth: seed weekly routine: %w", err)
	}

	return nil
}
