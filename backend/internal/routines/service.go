package routines

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/pkg/llm"
)

var (
	ErrRoutineNotFound = errors.New("routine not found")
	ErrBriefNotFound   = errors.New("no brief available")
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
		return sqlcgen.Routine{}, err
	}
	return routine, nil
}

func (s *Service) UpdateRoutineByType(ctx context.Context, userID pgtype.UUID, routineType string, timeOfDay *string, daysOfWeek *[]int, enabled *bool, timezone *string) (*sqlcgen.Routine, error) {
	routines, err := s.GetRoutines(ctx, userID)
	if err != nil {
		return nil, err
	}

	var target *sqlcgen.Routine
	for i := range routines {
		if routines[i].Type == routineType {
			target = &routines[i]
			break
		}
	}
	if target == nil {
		return nil, ErrRoutineNotFound
	}

	// Build the UpdateRoutine call — convert new fields back to cron_expr
	// for backward compatibility
	expr := target.CronExpr
	if timeOfDay != nil && daysOfWeek != nil {
		t := *timeOfDay            // "HH:MM"
		dow := *daysOfWeek         // [0..6]
		minute := "0"
		hour := strings.Split(t, ":")[0]
		dowStr := strings.Trim(strings.Replace(fmt.Sprint(dow), " ", ",", -1), "[]")
		expr = fmt.Sprintf("%s %s * * %s", minute, hour, dowStr)
	}

	var cronStr *string
	if expr != target.CronExpr {
		cronStr = &expr
	}

	_, err = s.repo.UpdateRoutine(ctx, target.ID, userID, cronStr, enabled)
	if err != nil {
		return nil, err
	}
	return target, nil
}

func (s *Service) GetRoutineLogs(ctx context.Context, userID pgtype.UUID, limit, offset int32) ([]sqlcgen.RoutineLog, error) {
	return s.repo.GetRoutineLogsByUser(ctx, userID, limit, offset)
}

func (s *Service) GetLatestBrief(ctx context.Context, userID pgtype.UUID, briefType string) (string, error) {
	log, err := s.repo.GetLatestBriefByType(ctx, userID, briefType)
	if err != nil {
		if errors.Is(err, ErrBriefNotFound) {
			return "", ErrBriefNotFound
		}
		return "", err
	}
	if !log.Content.Valid {
		return "", ErrBriefNotFound
	}
	return log.Content.String, nil
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
