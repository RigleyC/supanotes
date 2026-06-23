package search

import (
	"context"
	"fmt"
	"regexp"
	"strings"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/pkg/llm"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/pgvector/pgvector-go"
)

type SearchResult struct {
	ID        pgtype.UUID
	Title     string
	Content   string
	Excerpt   string
	UpdatedAt pgtype.Timestamptz
	ContextID pgtype.UUID
	Favorite  bool
	Archived  bool
	Score     float64
}

type Service struct {
	q      sqlcgen.Querier
	embedC *llm.EmbeddingClient
}

func NewService(q sqlcgen.Querier, embedC *llm.EmbeddingClient) *Service {
	return &Service{q: q, embedC: embedC}
}

func (s *Service) Search(ctx context.Context, userID pgtype.UUID, query string, limit int32) ([]SearchResult, error) {
	emb64, err := s.embedC.GenerateEmbedding(ctx, query)
	if err != nil {
		return nil, fmt.Errorf("generate query embedding: %w", err)
	}
	emb := make([]float32, len(emb64))
	for i := range emb64 {
		emb[i] = float32(emb64[i])
	}
	vec := pgvector.NewVector(emb)

	ftsQuery := toPrefixTsQuery(query)
	if ftsQuery == "" {
		return []SearchResult{}, nil
	}

	rows, err := s.q.SearchNotesHybrid(ctx, sqlcgen.SearchNotesHybridParams{
		UserID:        userID,
		Query:         ftsQuery,
		Limit:         limit,
		FtsLimit:      limit * 2,
		Embedding:     vec,
		SemanticLimit: limit * 2,
	})
	if err != nil {
		return nil, err
	}

	res := make([]SearchResult, len(rows))
	for i, r := range rows {
		res[i] = SearchResult{
			ID:        r.ID,
			Title:     r.Title,
			Content:   r.Content,
			Excerpt:   r.Excerpt.String,
			UpdatedAt: r.UpdatedAt,
			ContextID: r.ContextID,
			Favorite:  r.Favorite,
			Archived:  r.Archived,
			Score:     r.Score,
		}
	}
	return res, nil
}

// toPrefixTsQuery converts a plain-text query into a tsquery with
// prefix matching on each word so "tes" matches "teste".
func toPrefixTsQuery(query string) string {
	var re = regexp.MustCompile(`[^a-zA-Z0-9\s]`)
	safeQuery := re.ReplaceAllString(query, "")
	words := strings.Fields(safeQuery)
	if len(words) == 0 {
		return ""
	}
	parts := make([]string, len(words))
	for i, w := range words {
		safe := strings.ReplaceAll(w, "'", "''")
		parts[i] = safe + ":*"
	}
	return strings.Join(parts, " & ")
}
