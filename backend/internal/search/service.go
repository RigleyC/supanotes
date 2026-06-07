package search

import (
	"context"
	"fmt"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/jackc/pgx/v5/pgtype"
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

	res := make([]SearchResult, len(rows))
	for i, r := range rows {
		res[i] = SearchResult{
			ID:        r.ID,
			Title:     r.Title.String,
			Content:   r.Content,
			Excerpt:   r.Excerpt.String,
			UpdatedAt: r.UpdatedAt,
			ContextID: r.ContextID,
			Favorite:  r.Favorite,
			Archived:  r.Archived,
			Score:     float64(r.Score),
		}
	}
	return res, nil
}

func (s *Service) searchSemantic(ctx context.Context, userID pgtype.UUID, query string, limit int32) ([]SearchResult, error) {
	return nil, fmt.Errorf("search: semantic mode not available — no real embedding API configured")
}

func (s *Service) searchHybrid(ctx context.Context, userID pgtype.UUID, query string, limit int32) ([]SearchResult, error) {
	return nil, fmt.Errorf("search: hybrid mode not available — no real embedding API configured")
}
