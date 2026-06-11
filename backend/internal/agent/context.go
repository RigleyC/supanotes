package agent

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/rs/zerolog/log"
	"golang.org/x/sync/errgroup"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/pgvector/pgvector-go"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/memories"
	"github.com/RigleyC/supanotes/internal/tasks"
	"github.com/RigleyC/supanotes/pkg/llm"
	"github.com/RigleyC/supanotes/pkg/uid"
)

const (
	MaxTier0Tokens = 800  // Soul
	MaxTier1Tokens = 2000 // Recent messages
	MaxTier2Tokens = 1500 // Tasks + recent notes
	MaxTier3Tokens = 1000 // RAG semantic
	MaxTier4Tokens = 500  // Related notes
	MaxTier5Tokens = 500  // Memories
)

type ContextBuilder struct {
	q            sqlcgen.Querier
	tasksSvc     *tasks.Service
	memoriesRepo memories.Repository
	embedCL      *llm.EmbeddingClient
}

func NewContextBuilder(q sqlcgen.Querier, tasksSvc *tasks.Service, memoriesRepo memories.Repository, embedCL *llm.EmbeddingClient) *ContextBuilder {
	return &ContextBuilder{q: q, tasksSvc: tasksSvc, memoriesRepo: memoriesRepo, embedCL: embedCL}
}

// Build compiles the tiered context RAG string by fetching data concurrently.
func (cb *ContextBuilder) Build(ctx context.Context, userID, sessionID pgtype.UUID, query string) (string, error) {
	var (
		soul        sqlcgen.Soul
		recentMsgs  []sqlcgen.Message
		todayTasks  []sqlcgen.Task
		recentNotes []sqlcgen.Note
	)

	g, gCtx := errgroup.WithContext(ctx)

	g.Go(func() error {
		var err error
		soul, err = cb.q.GetSoul(gCtx, userID)
		if err != nil {
			return fmt.Errorf("get soul: %w", err)
		}
		return nil
	})

	g.Go(func() error {
		var err error
		recentMsgs, err = cb.q.GetMessages(gCtx, sqlcgen.GetMessagesParams{
			UserID:    userID,
			SessionID: sessionID,
			Limit:     10,
			Offset:    0,
		})
		if err != nil {
			return fmt.Errorf("get recent msgs: %w", err)
		}
		return nil
	})

	g.Go(func() error {
		var err error
		todayTasks, err = cb.tasksSvc.GetTodayTasks(gCtx, userID)
		if err != nil {
			return fmt.Errorf("get today tasks: %w", err)
		}
		return nil
	})

	g.Go(func() error {
		var err error
		recentNotes, err = cb.q.GetRecentNotes(gCtx, userID)
		if err != nil {
			return fmt.Errorf("get recent notes: %w", err)
		}
		return nil
	})

	if err := g.Wait(); err != nil {
		return "", err
	}

	now := time.Now().Format(time.RFC1123)

	var (
		semanticResults []sqlcgen.SearchNotesByEmbeddingRow
		memResults      []sqlcgen.SearchMemoriesByEmbeddingRow
		linkedNotes     []sqlcgen.Note
	)

	if emb, err := cb.embedCL.GenerateEmbedding(ctx, query); err != nil {
		log.Warn().Err(err).Msg("generate query embedding failed; skipping semantic note search")
	} else {
		vec := pgvector.NewVector(float64ToFloat32(emb))
		var sErr error
		semanticResults, sErr = cb.q.SearchNotesByEmbedding(ctx, sqlcgen.SearchNotesByEmbeddingParams{
			UserID:  userID,
			Column2: vec,
			Limit:   5,
		})
		if sErr != nil {
			log.Warn().Err(sErr).Msg("search notes by embedding failed; skipping semantic results")
		}
	}

	if emb, err := cb.embedCL.GenerateEmbedding(ctx, query); err != nil {
		log.Warn().Err(err).Msg("generate memory embedding failed; skipping semantic memory search")
	} else {
		vec := pgvector.NewVector(float64ToFloat32(emb))
		var mErr error
		memResults, mErr = cb.memoriesRepo.SearchMemories(ctx, userID, vec, 5)
		if mErr != nil {
			log.Warn().Err(mErr).Msg("search memories by embedding failed; skipping semantic results")
		}
	}

	noteIDs := make([]pgtype.UUID, 0, len(recentNotes))
	for _, n := range recentNotes {
		noteIDs = append(noteIDs, n.ID)
	}
	if len(noteIDs) > 0 {
		var lErr error
		linkedNotes, lErr = cb.q.GetLinkedNotes(ctx, sqlcgen.GetLinkedNotesParams{
			Column1: noteIDs,
			UserID:  userID,
		})
		if lErr != nil {
			log.Warn().Err(lErr).Msg("get linked notes failed; skipping related notes")
		}
	}

	var b strings.Builder
	b.WriteString(truncate(fmt.Sprintf(`SOUL:
%s

CURRENT DATE & TIME:
%s

RECENT MESSAGES HISTORY (Up to 10):
`, soul.Personality, now), MaxTier0Tokens+MaxTier1Tokens))

	for _, m := range recentMsgs {
		b.WriteString(fmt.Sprintf("[%s]: %s\n", m.Role, m.Content))
	}

	tier2 := &strings.Builder{}
	tier2.WriteString("\nTODAY/OVERDUE TASKS:\n")
	writeTasksWithStatus(tier2, todayTasks)
	tier2.WriteString("\nRECENT NOTES (Last 48h):\n")
	writeNotesWithID(tier2, recentNotes)
	b.WriteString(truncate(tier2.String(), MaxTier2Tokens))

	tier3 := &strings.Builder{}
	tier3.WriteString("\nSEMANTIC SEARCH RESULTS:\n")
	for _, r := range semanticResults {
		tier3.WriteString(fmt.Sprintf("- [%s] %s (similarity: %d)\n", uid.UUIDToString(r.ID), r.Title.String, r.Similarity))
	}
	if len(semanticResults) == 0 {
		tier3.WriteString("(none)\n")
	}
	b.WriteString(truncate(tier3.String(), MaxTier3Tokens))

	tier4 := &strings.Builder{}
	tier4.WriteString("\nRELATED NOTES:\n")
	writeNotesWithID(tier4, linkedNotes)
	if len(linkedNotes) == 0 {
		tier4.WriteString("(none)\n")
	}
	b.WriteString(truncate(tier4.String(), MaxTier4Tokens))

	tier5 := &strings.Builder{}
	tier5.WriteString("\nRELEVANT MEMORIES:\n")
	for _, m := range memResults {
		tier5.WriteString(fmt.Sprintf("- %s (similarity: %d)\n", m.Content, m.Similarity))
	}
	if len(memResults) == 0 {
		tier5.WriteString("(none)\n")
	}
	b.WriteString(truncate(tier5.String(), MaxTier5Tokens))

	b.WriteString("\nYou have access to tools to modify the database. If the user asks you to create a note, use add_note. If the user asks about a specific file/note that is not in the context, search for it using search_notes.")

	return b.String(), nil
}

func truncate(s string, maxBytes int) string {
	if len(s) <= maxBytes {
		return s
	}
	return s[:maxBytes] + "... [TRUNCATED]"
}

// BuildForRoutine builds the context RAG string concurrently, omitting the conversation history.
func (cb *ContextBuilder) BuildForRoutine(ctx context.Context, userID pgtype.UUID, routineType string) (string, error) {
	var (
		soul        sqlcgen.Soul
		todayTasks  []sqlcgen.Task
		recentNotes []sqlcgen.Note
	)

	g, gCtx := errgroup.WithContext(ctx)

	g.Go(func() error {
		var err error
		soul, err = cb.q.GetSoul(gCtx, userID)
		return err
	})

	g.Go(func() error {
		var err error
		todayTasks, err = cb.tasksSvc.GetTodayTasks(gCtx, userID)
		return err
	})

	g.Go(func() error {
		var err error
		recentNotes, err = cb.q.GetRecentNotes(gCtx, userID)
		return err
	})

	if err := g.Wait(); err != nil {
		return "", err
	}

	now := time.Now()

	var (
		semanticResults []sqlcgen.SearchNotesByEmbeddingRow
	)

	query := fmt.Sprintf("routine %s context", routineType)
	if emb, err := cb.embedCL.GenerateEmbedding(ctx, query); err != nil {
		log.Warn().Err(err).Msg("generate routine embedding failed; skipping semantic search")
	} else {
		vec := pgvector.NewVector(float64ToFloat32(emb))
		if results, err := cb.q.SearchNotesByEmbedding(ctx, sqlcgen.SearchNotesByEmbeddingParams{
			UserID:  userID,
			Column2: vec,
			Limit:   5,
		}); err == nil {
			semanticResults = results
		} else {
			log.Warn().Err(err).Msg("routine semantic search failed")
		}
	}

	var b strings.Builder
	b.WriteString(fmt.Sprintf(`META:
Current User Time: %s
Routine Type: %s

SOUL (User Personality/Settings):
%s

TODAY / OVERDUE TASKS:
`, now.Format(time.RFC3339), routineType, soul.Personality))

	writeTasksWithDueDate(&b, todayTasks)

	b.WriteString("\nRECENT NOTES (Last 48h):\n")
	writeNotesWithContent(&b, recentNotes, 500)

	if len(semanticResults) > 0 {
		b.WriteString("\nRELEVANT NOTES (via semantic search):\n")
		for _, r := range semanticResults {
			b.WriteString(fmt.Sprintf("- [%s] %s (similarity: %d)\n", uid.UUIDToString(r.ID), r.Title.String, r.Similarity))
		}
	}

	b.WriteString("\nMake the brief concise and actionable based on the above information.")
	return b.String(), nil
}

// --- formatting helpers ---

func writeTasksWithStatus(b *strings.Builder, tasks []sqlcgen.Task) {
	for _, t := range tasks {
		b.WriteString(fmt.Sprintf("- [%s] %s\n", t.Status, t.Title))
	}
}

func writeTasksWithDueDate(b *strings.Builder, tasks []sqlcgen.Task) {
	for _, t := range tasks {
		b.WriteString(fmt.Sprintf("- [ ] %s (Due: %v)\n", t.Title, t.DueDate.Time))
	}
}

func writeNotesWithID(b *strings.Builder, notes []sqlcgen.Note) {
	for _, n := range notes {
		b.WriteString(fmt.Sprintf("- ID: %s | Title: %s\n", uid.UUIDToString(n.ID), n.Title.String))
	}
}

func float64ToFloat32(src []float64) []float32 {
	dst := make([]float32, len(src))
	for i := range src {
		dst[i] = float32(src[i])
	}
	return dst
}

func writeNotesWithContent(b *strings.Builder, notes []sqlcgen.Note, maxContentLen int) {
	for _, n := range notes {
		content := n.Content
		if maxContentLen > 0 && len(content) > maxContentLen {
			content = content[:maxContentLen] + "... [TRUNCATED]"
		}
		b.WriteString(fmt.Sprintf("- Title: %s | Content: %s\n", n.Title.String, content))
	}
}
