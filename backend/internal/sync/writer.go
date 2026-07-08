package sync

import (
	"context"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
)

type NoteStateSyncer interface {
	SyncNoteToYjs(ctx context.Context, noteID pgtype.UUID) error
}

type noteStateSyncerImpl struct {
	ydoc *YDocService
	pool *pgxpool.Pool
}

func NewNoteStateSyncer(pool *pgxpool.Pool, ydoc *YDocService) NoteStateSyncer {
	return &noteStateSyncerImpl{pool: pool, ydoc: ydoc}
}

func (s *noteStateSyncerImpl) SyncNoteToYjs(ctx context.Context, noteID pgtype.UUID) error {
	if !noteID.Valid {
		return nil
	}
	noteIDStr := uuid.UUID(noteID.Bytes).String()
	update, err := ReconstructYDocFromNodes(ctx, s.pool, noteIDStr)
	if err != nil {
		return fmt.Errorf("reconstruct doc for note %s: %w", noteIDStr, err)
	}
	if err := s.ydoc.ApplyNodeMutation(ctx, noteIDStr, update); err != nil {
		return fmt.Errorf("ingest reconstructed update: %w", err)
	}
	return nil
}
