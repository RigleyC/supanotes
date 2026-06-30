package agent

import (
	"context"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

type WorkingMemoryService struct {
	q sqlcgen.Querier
}

func NewWorkingMemoryService(q sqlcgen.Querier) *WorkingMemoryService {
	return &WorkingMemoryService{q: q}
}

func (s *WorkingMemoryService) Set(ctx context.Context, userID, sessionID pgtype.UUID, key, value string) error {
	_, err := s.q.SetWorkingMemoryValue(ctx, sqlcgen.SetWorkingMemoryValueParams{
		UserID:    userID,
		SessionID: sessionID,
		Key:       key,
		Value:     value,
	})
	return err
}

func (s *WorkingMemoryService) Get(ctx context.Context, userID, sessionID pgtype.UUID, key string) (string, error) {
	return s.q.GetWorkingMemoryValue(ctx, sqlcgen.GetWorkingMemoryValueParams{
		UserID:    userID,
		SessionID: sessionID,
		Key:       key,
	})
}

func (s *WorkingMemoryService) GetAll(ctx context.Context, userID, sessionID pgtype.UUID) (map[string]string, error) {
	rows, err := s.q.GetWorkingMemoryForSession(ctx, sqlcgen.GetWorkingMemoryForSessionParams{
		UserID:    userID,
		SessionID: sessionID,
	})
	if err != nil {
		return nil, err
	}
	res := make(map[string]string)
	for _, r := range rows {
		res[r.Key] = r.Value
	}
	return res, nil
}

func (s *WorkingMemoryService) Clear(ctx context.Context, userID, sessionID pgtype.UUID) error {
	return s.q.DeleteWorkingMemoryForSession(ctx, sqlcgen.DeleteWorkingMemoryForSessionParams{
		UserID:    userID,
		SessionID: sessionID,
	})
}
