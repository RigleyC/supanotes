package contexts

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/dto"
	"github.com/RigleyC/supanotes/internal/mapper"
)

var (
	ErrContextHasNotes = errors.New("contexts: cannot delete context with linked notes")
)

type Service struct {
	q sqlcgen.Querier
}

func NewService(q sqlcgen.Querier) *Service {
	return &Service{q: q}
}

func (s *Service) List(ctx context.Context, userID pgtype.UUID) ([]dto.ContextResponse, error) {
	ctxs, err := s.q.GetContexts(ctx, userID)
	if err != nil {
		return nil, err
	}
	res := make([]dto.ContextResponse, 0, len(ctxs))
	for _, c := range ctxs {
		res = append(res, mapper.ContextFromSQLC(c))
	}
	return res, nil
}

func (s *Service) Create(ctx context.Context, userID pgtype.UUID, slug, name string) (dto.ContextResponse, error) {
	c, err := s.q.CreateContext(ctx, sqlcgen.CreateContextParams{
		UserID: userID,
		Slug:   slug,
		Name:   name,
	})
	if err != nil {
		return dto.ContextResponse{}, err
	}
	return mapper.ContextFromSQLC(c), nil
}

func (s *Service) Delete(ctx context.Context, userID, id pgtype.UUID) error {
	err := s.q.DeleteContext(ctx, sqlcgen.DeleteContextParams{ID: id, UserID: userID})
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23503" {
			return ErrContextHasNotes
		}
		return err
	}
	return nil
}
