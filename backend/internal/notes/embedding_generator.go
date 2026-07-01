package notes

import (
	"context"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/pgvector/pgvector-go"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/pkg/llm"
)

type EmbeddingGenerator struct {
	q       sqlcgen.Querier
	embedCL *llm.EmbeddingClient
}

func NewEmbeddingGenerator(q sqlcgen.Querier, embedCL *llm.EmbeddingClient) *EmbeddingGenerator {
	return &EmbeddingGenerator{q: q, embedCL: embedCL}
}

func (g *EmbeddingGenerator) RegenerateNoteEmbedding(ctx context.Context, noteID pgtype.UUID) error {
	nodes, err := g.q.GetNodesByNoteId(ctx, noteID)
	if err != nil {
		return fmt.Errorf("get nodes: %w", err)
	}

	var sb strings.Builder
	for _, n := range nodes {
		sb.WriteString(string(n.Data))
		sb.WriteByte('\n')
	}
	content := sb.String()

	if strings.TrimSpace(content) == "" {
		return nil
	}

	emb, err := g.embedCL.GenerateEmbedding(ctx, content)
	if err != nil {
		_ = g.q.UpdateNoteEmbeddingStatus(ctx, sqlcgen.UpdateNoteEmbeddingStatusParams{
			ID:              noteID,
			EmbeddingStatus: "failed",
		})
		return fmt.Errorf("generate embedding: %w", err)
	}

	vec := make([]float32, len(emb))
	for i := range emb {
		vec[i] = float32(emb[i])
	}

	if err := g.q.UpsertNoteEmbedding(ctx, sqlcgen.UpsertNoteEmbeddingParams{
		NoteID:    noteID,
		Embedding: pgvector.NewVector(vec),
	}); err != nil {
		return fmt.Errorf("upsert embedding: %w", err)
	}

	return g.q.UpdateNoteEmbeddingStatus(ctx, sqlcgen.UpdateNoteEmbeddingStatusParams{
		ID:              noteID,
		EmbeddingStatus: "done",
	})
}
