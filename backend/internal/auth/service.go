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

// SessionData holds the full user context returned on login / register
// so the client can bootstrap its local cache without extra round-trips.
type SessionData struct {
	User     sqlcgen.User
	Settings dto.SettingsResponse
	Soul     dto.SoulResponse
	Contexts []dto.ContextResponse
	Routines []sqlcgen.Routine
}

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

	// Load session data outside the auth tx so we don't hold it open.
	if err := s.loadSessionData(ctx, &session); err != nil {
		return nil, "", "", fmt.Errorf("auth: load session data: %w", err)
	}

	return &session, access, refresh, nil
}

// Login validates the credentials in constant time relative to the
// hash, then emits a fresh token pair. Both "user not found" and
// "wrong password" surface as ErrInvalidCredentials.
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

func (s *Service) loadSessionData(ctx context.Context, session *SessionData) error {
	userID := session.User.ID

	// Settings
	settings, err := s.q.GetUserSettings(ctx, userID)
	if err != nil {
		return fmt.Errorf("load settings: %w", err)
	}
	session.Settings = dto.SettingsResponse{
		Timezone:  settings.Timezone,
		CreatedAt: settings.CreatedAt.Time.Format(time.RFC3339),
		UpdatedAt: settings.UpdatedAt.Time.Format(time.RFC3339),
	}

	// Soul
	soul, err := s.q.GetSoul(ctx, userID)
	if err != nil {
		return fmt.Errorf("load soul: %w", err)
	}
	session.Soul = dto.SoulResponse{
		Personality: soul.Personality,
		CreatedAt:   soul.CreatedAt.Time.Format(time.RFC3339),
		UpdatedAt:   soul.UpdatedAt.Time.Format(time.RFC3339),
	}

	// Contexts
	ctxs, err := s.q.GetContexts(ctx, userID)
	if err != nil {
		return fmt.Errorf("load contexts: %w", err)
	}
	for _, c := range ctxs {
		session.Contexts = append(session.Contexts, dto.ContextResponse{
			ID:        uid.UUIDToString(c.ID),
			Slug:      c.Slug,
			Name:      c.Name,
			CreatedAt: c.CreatedAt.Time.Format(time.RFC3339),
			UpdatedAt: c.UpdatedAt.Time.Format(time.RFC3339),
		})
	}

	// Routines
	routines, err := s.q.GetRoutinesByUser(ctx, userID)
	if err != nil {
		return fmt.Errorf("load routines: %w", err)
	}
	session.Routines = routines

	return nil
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
		HideCompleted:   false,
	}); err != nil {
		return fmt.Errorf("auth: seed inbox note: %w", err)
	}

	personality := `# Personalidade
Você é o assistente pessoal SupaNotes — um parceiro de organização proativo, claro e direto. Seu tom é caloroso mas profissional, como um assistente executivo de confiança.

# Regras
1. Seja conciso. Prefira bullet points a parágrafos.
2. Seja proativo: sugira ações, não apenas liste informações.
3. Contexto é rei: use as notas, tarefas e memórias do usuário para personalizar cada interação.
4. Se o usuário pedir algo ambíguo, peça esclarecimento educadamente.
5. Ao organizar o inbox, agrupe ideias relacionadas e sugira títulos descritivos.
6. Mantenha confidencialidade — nunca compartilhe informações do usuário.
7. Se não souber algo, admita e sugira alternativas.

# Formato de Resposta
- Use Markdown para formatação
- Headings (##) para seções
- Bullet points para listas
- Checklist (- []) para tarefas sugeridas
- Citações em bloco para citações ou exemplos

# Briefs (Rotinas)
Nos briefs diários/semanais:
- Destaque tarefas urgentes primeiro
- Resuma notas recentes em 1-2 frases
- Sugira uma "intenção do dia" semanal
- Mantenha o brief em 3-5 parágrafos`
	if _, err := q.UpsertSoul(ctx, sqlcgen.UpsertSoulParams{
		UserID:      userID,
		Personality: personality,
	}); err != nil {
		return fmt.Errorf("auth: seed soul: %w", err)
	}

	if _, err := q.CreateRoutine(ctx, sqlcgen.CreateRoutineParams{
		UserID:    userID,
		Type:      "daily",
		CronExpr:  "0 8 * * 1-5",
		Enabled:   true,
		Name:      "Daily Brief",
		BriefType: "daily",
	}); err != nil {
		return fmt.Errorf("auth: seed daily routine: %w", err)
	}

	if _, err := q.CreateRoutine(ctx, sqlcgen.CreateRoutineParams{
		UserID:    userID,
		Type:      "weekly",
		CronExpr:  "0 9 * * 1",
		Enabled:   true,
		Name:      "Weekly Brief",
		BriefType: "weekly",
	}); err != nil {
		return fmt.Errorf("auth: seed weekly routine: %w", err)
	}

	return nil
}
