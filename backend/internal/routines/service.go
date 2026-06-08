package routines

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/pkg/llm"
)

var (
	ErrRoutineNotFound = errors.New("routine not found")
)

type ContextBuilder interface {
	BuildForRoutine(ctx context.Context, userID pgtype.UUID, routineType string) (string, error)
}

type Service struct {
	repo         Repository
	agentCtxBldr ContextBuilder
	llmFactory   llm.Factory
}

func NewService(repo Repository, agentCtxBldr ContextBuilder, llmFactory llm.Factory) *Service {
	return &Service{
		repo:         repo,
		agentCtxBldr: agentCtxBldr,
		llmFactory:   llmFactory,
	}
}

func (s *Service) GetRoutines(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.Routine, error) {
	return s.repo.GetRoutinesByUser(ctx, userID)
}

func (s *Service) UpdateRoutine(ctx context.Context, id, userID pgtype.UUID, cronExpr *string, enabled *bool) (sqlcgen.Routine, error) {
	routine, err := s.repo.UpdateRoutine(ctx, id, userID, cronExpr, enabled)
	if err != nil {
		// In a real app we'd check pgx error for "no rows" and map to ErrRoutineNotFound
		return sqlcgen.Routine{}, err
	}
	return routine, nil
}

func (s *Service) GetRoutineLogs(ctx context.Context, userID pgtype.UUID, limit, offset int32) ([]sqlcgen.RoutineLog, error) {
	return s.repo.GetRoutineLogsByUser(ctx, userID, limit, offset)
}

// TestRoutine performs a dry-run of a routine by generating the LLM context and calling the LLM, but doesn't save any logs.
func (s *Service) TestRoutine(ctx context.Context, userID pgtype.UUID, rType string) (string, error) {
	// Build the tiered context WITHOUT conversation history
	ragContext, err := s.agentCtxBldr.BuildForRoutine(ctx, userID, rType)
	if err != nil {
		return "", err
	}

	sysPrompt := buildBriefPrompt(rType, ragContext)

	llmClient := s.llmFactory.For(llm.TaskTypeGenerate)
	req := llm.Request{
		System:   sysPrompt,
		Messages: []llm.Message{{Role: "user", Content: "Gere a rotina agora."}},
	}

	resp, err := llmClient.Complete(ctx, req)
	if err != nil {
		return "", err
	}

	return resp.Content, nil
}
