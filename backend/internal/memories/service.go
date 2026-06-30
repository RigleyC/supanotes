package memories

import (
	"context"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/pgvector/pgvector-go"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/pkg/llm"
)

const (
	maxMemories              = 100
	dedupSearchLimit         = 5
	dedupSimilarityThreshold = 0.85
)

type Service struct {
	repo    Repository
	embedCL *llm.EmbeddingClient
	llmCL   llm.Client
}

func NewService(repo Repository, embedCL *llm.EmbeddingClient, llmCL llm.Client) *Service {
	return &Service{repo: repo, embedCL: embedCL, llmCL: llmCL}
}

func (s *Service) GetMemories(ctx context.Context, userID pgtype.UUID, limit, offset int32) ([]sqlcgen.Memory, error) {
	return s.repo.GetMemories(ctx, userID, limit, offset)
}

func validateContent(content string) error {
	lowered := strings.ToLower(content)
	if strings.Contains(lowered, "ignore previous instructions") || strings.Contains(lowered, "system prompt:") {
		return fmt.Errorf("invalid memory content (prompt injection detected)")
	}
	return nil
}

func (s *Service) checkCapacity(ctx context.Context, userID pgtype.UUID) error {
	count, err := s.repo.CountMemories(ctx, userID)
	if err != nil {
		return fmt.Errorf("count for capacity: %w", err)
	}
	if count >= maxMemories {
		return fmt.Errorf("memory capacity reached (max %d)", maxMemories)
	}
	return nil
}

func (s *Service) resolveDuplicates(ctx context.Context, userID pgtype.UUID, content string, vec pgvector.Vector) (sqlcgen.Memory, bool, error) {
	memRows, err := s.repo.SearchMemories(ctx, userID, vec, dedupSearchLimit)
	if err != nil {
		return sqlcgen.Memory{}, false, fmt.Errorf("search for duplicates: %w", err)
	}

	for _, row := range memRows {
		if row.Similarity >= dedupSimilarityThreshold {
			decision, err := s.dedupDecision(ctx, content, row.Content)
			if err != nil {
				return sqlcgen.Memory{}, false, fmt.Errorf("dedup decision: %w", err)
			}
			switch decision {
			case "REJECT":
				return sqlcgen.Memory{
					ID:        row.ID,
					UserID:    userID,
					Content:   row.Content,
					CreatedAt: row.CreatedAt,
				}, true, nil
			case "REPLACE":
				newEmb, err := s.embedCL.GenerateEmbedding(ctx, content)
				if err != nil {
					return sqlcgen.Memory{}, false, fmt.Errorf("generate embedding for replace: %w", err)
				}
				newVec := pgvector.NewVector(float64ToFloat32(newEmb))
				mem, err := s.repo.UpdateMemory(ctx, row.ID, userID, content, newVec)
				return mem, true, err
			case "MERGE":
				merged := row.Content + "\n" + content
				mergedEmb, err := s.embedCL.GenerateEmbedding(ctx, merged)
				if err != nil {
					return sqlcgen.Memory{}, false, fmt.Errorf("generate embedding for merge: %w", err)
				}
				mergedVec := pgvector.NewVector(float64ToFloat32(mergedEmb))
				mem, err := s.repo.UpdateMemory(ctx, row.ID, userID, merged, mergedVec)
				return mem, true, err
			}
		}
	}
	return sqlcgen.Memory{}, false, nil
}

func (s *Service) CreateMemory(ctx context.Context, userID pgtype.UUID, content string) (sqlcgen.Memory, error) {
	if err := validateContent(content); err != nil {
		return sqlcgen.Memory{}, err
	}

	if err := s.checkCapacity(ctx, userID); err != nil {
		return sqlcgen.Memory{}, fmt.Errorf("memories: %w", err)
	}

	emb, err := s.embedCL.GenerateEmbedding(ctx, content)
	if err != nil {
		return sqlcgen.Memory{}, fmt.Errorf("memories: generate embedding: %w", err)
	}
	vec := pgvector.NewVector(float64ToFloat32(emb))

	resolvedMem, handled, err := s.resolveDuplicates(ctx, userID, content, vec)
	if err != nil {
		return sqlcgen.Memory{}, fmt.Errorf("memories: %w", err)
	}
	if handled {
		return resolvedMem, nil
	}

	return s.repo.CreateMemory(ctx, userID, content, vec)
}

func (s *Service) dedupDecision(ctx context.Context, candidate, existing string) (string, error) {
	prompt := fmt.Sprintf(
		`You are a memory deduplication system. Compare the CANDIDATE memory with the EXISTING memory and decide one of:
- REJECT: candidate is redundant or already fully covered
- REPLACE: candidate adds new information that makes existing obsolete
- MERGE: both have complementary information that should be combined

Respond with exactly one word: REJECT, REPLACE, or MERGE.

CANDIDATE: %s
EXISTING: %s`,
		candidate, existing,
	)
	req := llm.Request{
		Messages:    []llm.Message{{Role: llm.RoleUser, Content: prompt}},
		MaxTokens:   10,
		Temperature: 0.0,
	}
	resp, err := s.llmCL.Complete(ctx, req)
	if err != nil {
		return "", fmt.Errorf("memories: dedup llm: %w", err)
	}
	decision := strings.TrimSpace(resp.Content)
	switch decision {
	case "REJECT", "REPLACE", "MERGE":
		return decision, nil
	default:
		return "MERGE", nil
	}
}

func (s *Service) DeleteMemory(ctx context.Context, id, userID pgtype.UUID) error {
	return s.repo.DeleteMemory(ctx, id, userID)
}

func float64ToFloat32(src []float64) []float32 {
	dst := make([]float32, len(src))
	for i := range src {
		dst[i] = float32(src[i])
	}
	return dst
}
