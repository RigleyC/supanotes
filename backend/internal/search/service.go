package search

import (
	"context"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
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
	q sqlcgen.Querier
}

func NewService(q sqlcgen.Querier) *Service {
	return &Service{q: q}
}

func (s *Service) Search(ctx context.Context, userID pgtype.UUID, query string, mode string, limit int32) ([]SearchResult, error) {
	switch mode {
	case "fts":
		return s.searchFTS(ctx, userID, query, limit)
	case "semantic":
		return s.searchSemantic(ctx, userID, query, limit)
	case "hybrid":
		return s.searchHybrid(ctx, userID, query, limit)
	default:
		// Se não especificar ou for inválido, cai pra FTS como fallback
		return s.searchFTS(ctx, userID, query, limit)
	}
}

func (s *Service) searchFTS(ctx context.Context, userID pgtype.UUID, query string, limit int32) ([]SearchResult, error) {
	rows, err := s.q.SearchNotesFTS(ctx, sqlcgen.SearchNotesFTSParams{
		UserID: userID,
		Query:  query,
		Limit:  limit,
	})
	if err != nil {
		return nil, err
	}

	res := make([]SearchResult, 0, len(rows))
	for _, r := range rows {
		res = append(res, SearchResult{
			ID:        r.ID,
			Title:     r.Title.String,
			Content:   r.Content,
			Excerpt:   r.Excerpt.String,
			UpdatedAt: r.UpdatedAt,
			ContextID: r.ContextID,
			Favorite:  r.Favorite,
			Archived:  r.Archived,
			Score:     float64(r.Score),
		})
	}
	return res, nil
}

func (s *Service) searchSemantic(ctx context.Context, userID pgtype.UUID, query string, limit int32) ([]SearchResult, error) {
	// Stub: Em produção (Feature 5 LLM) geraríamos o embedding real da query via OpenAI
	vec := make([]float32, 1536)
	for i := range vec {
		vec[i] = 0.01
	}

	rows, err := s.q.SearchNotesSemantic(ctx, sqlcgen.SearchNotesSemanticParams{
		UserID:    userID,
		Embedding: pgvector.NewVector(vec),
		Limit:     limit,
	})
	if err != nil {
		return nil, err
	}

	res := make([]SearchResult, 0, len(rows))
	for _, r := range rows {
		res = append(res, SearchResult{
			ID:        r.ID,
			Title:     r.Title.String,
			Content:   r.Content,
			Excerpt:   r.Excerpt.String,
			UpdatedAt: r.UpdatedAt,
			ContextID: r.ContextID,
			Favorite:  r.Favorite,
			Archived:  r.Archived,
			Score:     r.Score,
		})
	}
	return res, nil
}

func (s *Service) searchHybrid(ctx context.Context, userID pgtype.UUID, query string, limit int32) ([]SearchResult, error) {
	// Stub: Em produção geraríamos o embedding real da query via OpenAI
	vec := make([]float32, 1536)
	for i := range vec {
		vec[i] = 0.01
	}

	rows, err := s.q.SearchNotesHybrid(ctx, sqlcgen.SearchNotesHybridParams{
		Query:         query,
		UserID:        userID,
		FtsLimit:      limit * 2,
		Embedding:     pgvector.NewVector(vec),
		SemanticLimit: limit * 2,
		Limit:         limit,
	})
	if err != nil {
		return nil, err
	}

	res := make([]SearchResult, 0, len(rows))
	for _, r := range rows {
		res = append(res, SearchResult{
			ID:        r.ID,
			Title:     r.Title.String,
			Content:   r.Content,
			Excerpt:   r.Excerpt.String,
			UpdatedAt: r.UpdatedAt,
			ContextID: r.ContextID,
			Favorite:  r.Favorite,
			Archived:  r.Archived,
			Score:     r.Score,
		})
	}
	return res, nil

}
