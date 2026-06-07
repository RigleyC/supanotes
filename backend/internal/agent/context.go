package agent

import (
	"context"
	"fmt"
	"strings"
	"time"

	"golang.org/x/sync/errgroup"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/tasks"
	"github.com/RigleyC/supanotes/pkg/uid"
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

	var b strings.Builder
	b.WriteString(fmt.Sprintf(`SOUL:
%s

CURRENT DATE & TIME:
%s

RECENT MESSAGES HISTORY (Up to 10):
`, soul.Personality, now))

	for _, m := range recentMsgs {
		b.WriteString(fmt.Sprintf("[%s]: %s\n", m.Role, m.Content))
	}

	b.WriteString("\nTODAY/OVERDUE TASKS:\n")
	writeTasksWithStatus(&b, todayTasks)

	b.WriteString("\nRECENT NOTES (Last 48h):\n")
	writeNotesWithID(&b, recentNotes)

	b.WriteString("\nYou have access to tools to modify the database. If the user asks you to create a note, use add_note. If the user asks about a specific file/note that is not in the context, search for it using search_notes.")

	return b.String(), nil
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

func writeNotesWithContent(b *strings.Builder, notes []sqlcgen.Note, maxContentLen int) {
	for _, n := range notes {
		content := n.Content
		if maxContentLen > 0 && len(content) > maxContentLen {
			content = content[:maxContentLen] + "... [TRUNCATED]"
		}
		b.WriteString(fmt.Sprintf("- Title: %s | Content: %s\n", n.Title.String, content))
	}
}
