package agent

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/RigleyC/supanotes/internal/sync"
)

type YjsMutationService struct {
	pool *pgxpool.Pool
}

func NewYjsMutationService(pool *pgxpool.Pool) *YjsMutationService {
	return &YjsMutationService{pool: pool}
}

func (s *YjsMutationService) WriteNodeMutation(ctx context.Context, noteID string, update []byte) error {
	if _, err := s.pool.Exec(ctx,
		"INSERT INTO note_yjs_updates (note_id, update_data) VALUES ($1, $2)", noteID, update,
	); err != nil {
		return fmt.Errorf("write yjs update: %w", err)
	}
	if err := sync.ProjectToDB(ctx, s.pool, noteID, update); err != nil {
		return fmt.Errorf("project yjs update: %w", err)
	}
	return nil
}
