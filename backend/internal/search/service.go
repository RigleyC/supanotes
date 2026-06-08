package search

import (
	"context"
	"fmt"

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

func (s *Service) Search(ctx context.Context, userID pgtype.UUID, query string, mode string, limit int32) ([]SearchResult, error) {
	switch mode {
	case "fts":
		return s.searchFTS(ctx, userID, query, limit)
	case "semantic":
		return s.searchSemantic(ctx, userID, query, limit)
	case "hybrid":
		return s.searchHybrid(ctx, userID, query, limit)
	default:
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
	emb64, err := s.embedC.GenerateEmbedding(ctx, query)
	if err != nil {
		return nil, fmt.Errorf("generate query embedding: %w", err)
	}
	emb := make([]float32, len(emb64))
	for i := range emb64 {
		emb[i] = float32(emb64[i])
	}
	vec := pgvector.NewVector(emb)

	rows, err := s.q.SearchNotesSemantic(ctx, sqlcgen.SearchNotesSemanticParams{
		UserID:    userID,
		Embedding: vec,
		Limit:     limit,
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
			Score:     r.Score,
		}
	}
	return res, nil
}

func (s *Service) searchHybrid(ctx context.Context, userID pgtype.UUID, query string, limit int32) ([]SearchResult, error) {
	emb64, err := s.embedC.GenerateEmbedding(ctx, query)
	if err != nil {
		return nil, fmt.Errorf("generate query embedding: %w", err)
	}
	emb := make([]float32, len(emb64))
	for i := range emb64 {
		emb[i] = float32(emb64[i])
	}
	vec := pgvector.NewVector(emb)

	rows, err := s.q.SearchNotesHybrid(ctx, sqlcgen.SearchNotesHybridParams{
		UserID:        userID,
		Query:         query,
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
			Title:     r.Title.String,
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
