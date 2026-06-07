package onboarding

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

type Service struct {
	pool *pgxpool.Pool
}

func NewService(pool *pgxpool.Pool) *Service {
	return &Service{pool: pool}
}

// OnboardUser creates all initial user data inside a single pgx.Tx transaction.
// If any step fails, the entire transaction is rolled back.
func (s *Service) OnboardUser(ctx context.Context, userID pgtype.UUID) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("onboarding: begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	qtx := sqlcgen.New(tx)

	// 1. Create default user settings (UTC timezone)
	if _, err := qtx.CreateUserSettings(ctx, sqlcgen.CreateUserSettingsParams{
		UserID:   userID,
		Timezone: "UTC",
	}); err != nil {
		return fmt.Errorf("onboarding: create settings: %w", err)
	}

	// 2. Create inbox note
	title := "Rascunho"
	content := "Bem-vindo ao SupaNotes! Esta é sua nota de inbox, o lugar perfeito para despejar ideias rapidamente."
	if _, err := qtx.CreateNote(ctx, sqlcgen.CreateNoteParams{
		UserID:          userID,
		Title:           pgtype.Text{String: title, Valid: true},
		Content:         content,
		IsInbox:         true,
		Favorite:        false,
		Archived:        false,
		EmbeddingStatus: "pending",
	}); err != nil {
		return fmt.Errorf("onboarding: create inbox note: %w", err)
	}

	// 3. Create soul
	defaultPersonality := "Você é o assistente SupaNotes. Você deve ser claro, objetivo, proativo e prestativo, auxiliando na organização pessoal e resgate de ideias do usuário."
	if _, err := qtx.UpsertSoul(ctx, sqlcgen.UpsertSoulParams{
		UserID:      userID,
		Personality: defaultPersonality,
	}); err != nil {
		return fmt.Errorf("onboarding: create soul: %w", err)
	}

	// 4. Create daily routine (08:00 weekdays)
	if _, err := qtx.CreateRoutine(ctx, sqlcgen.CreateRoutineParams{
		UserID:   userID,
		Type:     "daily",
		CronExpr: "0 8 * * 1-5",
		Enabled:  true,
	}); err != nil {
		return fmt.Errorf("onboarding: create daily routine: %w", err)
	}

	// 5. Create weekly routine (09:00 Mondays)
	if _, err := qtx.CreateRoutine(ctx, sqlcgen.CreateRoutineParams{
		UserID:   userID,
		Type:     "weekly",
		CronExpr: "0 9 * * 1",
		Enabled:  true,
	}); err != nil {
		return fmt.Errorf("onboarding: create weekly routine: %w", err)
	}

	return tx.Commit(ctx)
}
