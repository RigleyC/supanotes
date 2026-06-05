package agent

import (
	"context"
	"fmt"
	"time"

	"golang.org/x/sync/errgroup"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/pgvector/pgvector-go"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/tasks"
)

type ContextBuilder struct {
	q        sqlcgen.Querier
	tasksSvc *tasks.Service
}

func NewContextBuilder(q sqlcgen.Querier, tasksSvc *tasks.Service) *ContextBuilder {
	return &ContextBuilder{q: q, tasksSvc: tasksSvc}
}

// Build compiles the tiered context RAG string by fetching data concurrently.
func (cb *ContextBuilder) Build(ctx context.Context, userID, sessionID pgtype.UUID, query string) (string, error) {
	var (
		soul        sqlcgen.Soul
		recentMsgs  []sqlcgen.Message
		todayTasks  []sqlcgen.Task
		recentNotes []sqlcgen.GetRecentNotesRow
		semNotes    []sqlcgen.Note
		linkedNotes []sqlcgen.Note
		semMemories []sqlcgen.Memory
	)

	g, gCtx := errgroup.WithContext(ctx)

	queryEmb := make([]float32, 1536)
	for i := range queryEmb {
		queryEmb[i] = 0.01
	}
	vec := pgvector.NewVector(queryEmb)

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

	g.Go(func() error {
		var err error
		semNotes, err = cb.q.SearchNotesByEmbedding(gCtx, sqlcgen.SearchNotesByEmbeddingParams{
			UserID:  userID,
			Column2: vec,
			Limit:   6,
		})
		if err != nil {
			return fmt.Errorf("search notes: %w", err)
		}

		var semNoteIDs []pgtype.UUID
		for _, sn := range semNotes {
			semNoteIDs = append(semNoteIDs, sn.ID)
		}

		if len(semNoteIDs) > 0 {
			linkedNotes, _ = cb.q.GetLinkedNotes(gCtx, sqlcgen.GetLinkedNotesParams{
				Column1: semNoteIDs,
				UserID:  userID,
			})
		}
		return nil
	})

	g.Go(func() error {
		var err error
		semMemories, err = cb.q.SearchMemoriesByEmbedding(gCtx, sqlcgen.SearchMemoriesByEmbeddingParams{
			UserID:  userID,
			Column2: vec,
			Limit:   5,
		})
		if err != nil {
			return fmt.Errorf("search memories: %w", err)
		}
		return nil
	})

	if err := g.Wait(); err != nil {
		return "", err
	}

	// Meta
	now := time.Now().Format(time.RFC1123)

	// Combine Context
	sysContext := fmt.Sprintf(`SOUL:
%s

CURRENT DATE & TIME:
%s

RECENT MESSAGES HISTORY (Up to 10):
`, soul.Personality, now)

	for _, m := range recentMsgs {
		sysContext += fmt.Sprintf("[%s]: %s\n", m.Role, m.Content)
	}

	sysContext += "\nTODAY/OVERDUE TASKS:\n"
	for _, t := range todayTasks {
		sysContext += fmt.Sprintf("- [%s] %s\n", t.Status, t.Title)
	}

	sysContext += "\nRECENT NOTES (Last 48h):\n"
	for _, n := range recentNotes {
		idStr := ""
		if n.ID.Valid {
			idStr = fmt.Sprintf("%x", n.ID.Bytes)
		}
		sysContext += fmt.Sprintf("- ID: %s | Title: %s\n", idStr, n.Title.String)
	}

	sysContext += "\nSEMANTICALLY RELEVANT NOTES:\n"
	for _, n := range semNotes {
		idStr := ""
		if n.ID.Valid {
			idStr = fmt.Sprintf("%x", n.ID.Bytes)
		}
		content := n.Content
		if len(content) > 1000 {
			content = content[:1000] + "... [TRUNCATED]"
		}
		sysContext += fmt.Sprintf("- ID: %s | Title: %s | Content: %s\n", idStr, n.Title.String, content)
	}

	if len(linkedNotes) > 0 {
		sysContext += "\nLINKED NOTES (Related to Semantic Notes):\n"
		for _, n := range linkedNotes {
			idStr := ""
			if n.ID.Valid {
				idStr = fmt.Sprintf("%x", n.ID.Bytes)
			}
			content := n.Content
			if len(content) > 500 {
				content = content[:500] + "... [TRUNCATED]"
			}
			sysContext += fmt.Sprintf("- ID: %s | Title: %s | Content: %s\n", idStr, n.Title.String, content)
		}
	}

	sysContext += "\nRELEVANT MEMORIES:\n"
	for _, m := range semMemories {
		sysContext += fmt.Sprintf("- %s\n", m.Content)
	}

	sysContext += "\nYou have access to tools to modify the database. If the user asks you to create a note, use add_note. If the user asks about a specific file/note that is not in the context, search for it using search_notes."

	return sysContext, nil
}

// BuildForRoutine builds the context RAG string concurrently, omitting the conversation history.
func (cb *ContextBuilder) BuildForRoutine(ctx context.Context, userID pgtype.UUID, routineType string) (string, error) {
	var (
		soul        sqlcgen.Soul
		todayTasks  []sqlcgen.Task
		recentNotes []sqlcgen.GetRecentNotesRow
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

	sysContext := fmt.Sprintf(`META:
Current User Time: %s
Routine Type: %s

SOUL (User Personality/Settings):
%s

TODAY / OVERDUE TASKS:
`, now.Format(time.RFC3339), routineType, soul.Personality)

	for _, t := range todayTasks {
		sysContext += fmt.Sprintf("- [ ] %s (Due: %v)\n", t.Title, t.DueDate.Time)
	}

	sysContext += "\nRECENT NOTES (Last 48h):\n"
	for _, n := range recentNotes {
		content := n.Content
		if len(content) > 500 {
			content = content[:500] + "... [TRUNCATED]"
		}
		sysContext += fmt.Sprintf("- Title: %s | Content: %s\n", n.Title.String, content)
	}

	sysContext += "\nMake the brief concise and actionable based on the above information."
	return sysContext, nil
}
