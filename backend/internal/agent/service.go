package agent

import (
	"context"
	"fmt"
)

type yDocIngest interface {
	ApplyNodeMutation(ctx context.Context, noteID string, update []byte) error
}

type YjsMutationService struct {
	ydoc yDocIngest
}

func NewYjsMutationService(ydoc yDocIngest) *YjsMutationService {
	return &YjsMutationService{ydoc: ydoc}
}

func (s *YjsMutationService) WriteNodeMutation(ctx context.Context, noteID string, update []byte) error {
	if err := s.ydoc.ApplyNodeMutation(ctx, noteID, update); err != nil {
		return fmt.Errorf("ingest yjs update: %w", err)
	}
	return nil
}
