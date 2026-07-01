package agent

import (
	"context"
	_ "embed"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/rs/zerolog/log"
	"golang.org/x/sync/errgroup"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/pgvector/pgvector-go"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/memories"
	"github.com/RigleyC/supanotes/internal/notes"
	"github.com/RigleyC/supanotes/internal/tasks"
	"github.com/RigleyC/supanotes/pkg/llm"
	"github.com/RigleyC/supanotes/pkg/uid"
)

//go:embed system_prompt.md
var systemPrompt string

const (
	MaxTier0Tokens  = 1200 // Soul
	MaxTierIBTokens = 800  // Intelligence Briefing
	MaxTier2Tokens  = 3500 // Tasks + recent notes
	MaxTier3Tokens  = 1500 // RAG semantic
	MaxTier4Tokens  = 800  // Related notes
	MaxTier5Tokens  = 800  // Memories
)

func buildIntelligenceBriefing(todayTasks []sqlcgen.Task, completedTasks []sqlcgen.Task, recentNotes []sqlcgen.Note, overdueCount int64) string {
	var b strings.Builder
	b.WriteString("INTELLIGENCE BRIEFING:\n")

	if len(completedTasks) > 0 {
		noteGroup := make(map[string]int)
		standalone := 0
		for _, t := range completedTasks {
			if t.NoteID.Valid {
				noteGroup[uid.UUIDToString(t.NoteID)]++
			} else {
				standalone++
			}
		}
		b.WriteString(fmt.Sprintf("- Completed last 7 days: %d tasks (%d with notes, %d standalone)\n", len(completedTasks), len(completedTasks)-standalone, standalone))
	}

	if overdueCount > 0 {
		b.WriteString(fmt.Sprintf("- Overdue: %d open tasks\n", overdueCount))
	}

	inboxCount := 0
	for _, n := range recentNotes {
		if n.IsInbox {
			inboxCount++
		}
	}
	if inboxCount > 0 {
		b.WriteString("- Inbox: Note has recent activity\n")
	}

	return b.String()
}

type ContextBuilder struct {
	q            sqlcgen.Querier
	tasksSvc     *tasks.Service
	memoriesRepo memories.Repository
	embedCL      *llm.EmbeddingClient
}

func NewContextBuilder(q sqlcgen.Querier, tasksSvc *tasks.Service, memoriesRepo memories.Repository, embedCL *llm.EmbeddingClient) *ContextBuilder {
	return &ContextBuilder{q: q, tasksSvc: tasksSvc, memoriesRepo: memoriesRepo, embedCL: embedCL}
}

type buildPolicy struct {
	fetchTasks       bool
	fetchRecentNotes bool
	searchNotes      bool
	searchMemories   bool
	fetchLinkedNotes bool
}

func policyForIntent(intent Intent) buildPolicy {
	switch intent {
	case IntentDailySummary:
		return buildPolicy{
			fetchTasks:       true,
			fetchRecentNotes: false,
			searchNotes:      false,
			searchMemories:   true,
			fetchLinkedNotes: false,
		}
	case IntentSearchKnowledge:
		return buildPolicy{
			fetchTasks:       false,
			fetchRecentNotes: true,
			searchNotes:      true,
			searchMemories:   true,
			fetchLinkedNotes: false,
		}
	case IntentProjectPlanning:
		return buildPolicy{
			fetchTasks:       true,
			fetchRecentNotes: false,
			searchNotes:      true,
			searchMemories:   false,
			fetchLinkedNotes: true,
		}
	case IntentTaskManagement:
		return buildPolicy{
			fetchTasks:       true,
			fetchRecentNotes: false,
			searchNotes:      false,
			searchMemories:   false,
			fetchLinkedNotes: false,
		}
	case IntentMemoryQuestion:
		return buildPolicy{
			fetchTasks:       false,
			fetchRecentNotes: true,
			searchNotes:      false,
			searchMemories:   true,
			fetchLinkedNotes: false,
		}
	case IntentOrganization:
		return buildPolicy{
			fetchTasks:       false,
			fetchRecentNotes: true,
			searchNotes:      false,
			searchMemories:   false,
			fetchLinkedNotes: false,
		}
	case IntentBrainstorming:
		return buildPolicy{
			fetchTasks:       false,
			fetchRecentNotes: true,
			searchNotes:      true,
			searchMemories:   true,
			fetchLinkedNotes: false,
		}
	case IntentGeneralChat:
		return buildPolicy{
			fetchTasks:       false,
			fetchRecentNotes: false,
			searchNotes:      false,
			searchMemories:   false,
			fetchLinkedNotes: false,
		}
	default:
		return buildPolicy{
			fetchTasks:       true,
			fetchRecentNotes: true,
			searchNotes:      true,
			searchMemories:   true,
			fetchLinkedNotes: true,
		}
	}
}

type contextData struct {
	soul                sqlcgen.Soul
	tzLoc               *time.Location
	todayTasks          []sqlcgen.Task
	recentNotes         []sqlcgen.Note
	completedTasks      []sqlcgen.Task
	overdueCount        int64
	semanticResults     []sqlcgen.SearchNotesByEmbeddingRow
	memResults          []sqlcgen.SearchMemoriesByEmbeddingRow
	linkedNotes         []sqlcgen.Note
	recentNotesRendered []string
}

// Build compiles the tiered context RAG string by fetching data concurrently
// based on the given intent's retrieval policy.
func (cb *ContextBuilder) Build(ctx context.Context, userID, sessionID pgtype.UUID, query string, intent Intent) (string, error) {
	policy := policyForIntent(intent)
	data, err := cb.fetchContextData(ctx, userID, sessionID, query, policy)
	if err != nil {
		return "", err
	}
	return cb.formatContextPrompt(data, policy), nil
}

func (cb *ContextBuilder) fetchContextData(ctx context.Context, userID, sessionID pgtype.UUID, query string, policy buildPolicy) (*contextData, error) {
	data := &contextData{
		tzLoc: time.UTC,
	}

	g, gCtx := errgroup.WithContext(ctx)

	g.Go(func() error {
		var err error
		data.soul, err = cb.q.GetSoul(gCtx, userID)
		if err != nil {
			return fmt.Errorf("get soul: %w", err)
		}
		return nil
	})

	if policy.fetchTasks {
		g.Go(func() error {
			// Fetch timezone preference and today's tasks sequentially in the same goroutine
			userSettings, err := cb.q.GetUserSettings(gCtx, userID)
			if err == nil && userSettings.Timezone != "" {
				if loc, locErr := time.LoadLocation(userSettings.Timezone); locErr == nil {
					data.tzLoc = loc
				} else {
					log.Warn().Err(locErr).Str("timezone", userSettings.Timezone).Msg("failed to load user timezone; falling back to UTC")
				}
			}

			var errToday error
			data.todayTasks, errToday = cb.tasksSvc.GetTodayTasksInTimezone(gCtx, userID, data.tzLoc)
			if errToday != nil {
				return fmt.Errorf("get today tasks: %w", errToday)
			}
			return nil
		})

		g.Go(func() error {
			var err error
			data.completedTasks, err = cb.tasksSvc.GetRecentlyCompletedTasks(gCtx, userID, 7)
			return err
		})
	}

	if policy.fetchRecentNotes {
		g.Go(func() error {
			rows, err := cb.q.GetRecentNotes(gCtx, userID)
			if err != nil {
				return fmt.Errorf("get recent notes: %w", err)
			}
			data.recentNotes = make([]sqlcgen.Note, len(rows))
			for i, r := range rows {
				data.recentNotes[i] = sqlcgen.Note{
					ID:              r.ID,
					UserID:          r.UserID,
					ContextID:       r.ContextID,
					Content:         r.Content,
					Excerpt:         r.Excerpt,
					IsInbox:         r.IsInbox,
					SearchVector:    r.SearchVector,
					CreatedAt:       r.CreatedAt,
					UpdatedAt:       r.UpdatedAt,
					DeletedAt:       r.DeletedAt,
					EmbeddingStatus: r.EmbeddingStatus,
					CollapseImages:  r.CollapseImages,
				}
			}
			return nil
		})
	}

	if err := g.Wait(); err != nil {
		return nil, err
	}

	if policy.fetchTasks {
		nowLocal := time.Now().In(data.tzLoc)
		todayBoundary := time.Date(nowLocal.Year(), nowLocal.Month(), nowLocal.Day(), 0, 0, 0, 0, data.tzLoc)
		for _, task := range data.todayTasks {
			if task.DueDate.Valid && task.DueDate.Time.Before(todayBoundary) {
				data.overdueCount++
			}
		}
	}

	if policy.searchNotes || policy.searchMemories {
		emb, embErr := cb.embedCL.GenerateEmbedding(ctx, query)
		if embErr != nil {
			log.Warn().Err(embErr).Msg("generate query embedding failed; skipping semantic search")
		} else {
			vec := pgvector.NewVector(float64ToFloat32(emb))

			if policy.searchNotes {
				var sErr error
				data.semanticResults, sErr = cb.q.SearchNotesByEmbedding(ctx, sqlcgen.SearchNotesByEmbeddingParams{
					UserID:  userID,
					Column2: vec,
					Limit:   5,
				})
				if sErr != nil {
					log.Warn().Err(sErr).Msg("search notes by embedding failed; skipping semantic results")
				}
			}

			if policy.searchMemories {
				var mErr error
				data.memResults, mErr = cb.memoriesRepo.SearchMemories(ctx, userID, vec, 5)
				if mErr != nil {
					log.Warn().Err(mErr).Msg("search memories by embedding failed; skipping semantic results")
				}
			}
		}
	}

	if policy.fetchLinkedNotes && len(data.recentNotes) > 0 {
		noteIDs := make([]pgtype.UUID, 0, len(data.recentNotes))
		for _, n := range data.recentNotes {
			noteIDs = append(noteIDs, n.ID)
		}
		var lErr error
		data.linkedNotes, lErr = cb.q.GetLinkedNotes(ctx, sqlcgen.GetLinkedNotesParams{
			Column1: noteIDs,
			UserID:  userID,
		})
		if lErr != nil {
			log.Warn().Err(lErr).Msg("get linked notes failed; skipping related notes")
		}
	}

	if policy.fetchRecentNotes && len(data.recentNotes) > 0 {
		data.recentNotesRendered = make([]string, 0, len(data.recentNotes))
		for _, n := range data.recentNotes {
			nodes, err := cb.q.GetNodesByNoteId(ctx, n.ID)
			if err != nil {
				log.Warn().Err(err).Str("note_id", uid.UUIDToString(n.ID)).Msg("failed to fetch nodes for recent note; using content directly")
				data.recentNotesRendered = append(data.recentNotesRendered, n.Content)
				continue
			}

			noteTasks, err := cb.q.GetTasksByNoteID(ctx, sqlcgen.GetTasksByNoteIDParams{
				UserID: userID,
				NoteID: n.ID,
			})
			if err != nil {
				log.Warn().Err(err).Str("note_id", uid.UUIDToString(n.ID)).Msg("failed to fetch tasks for recent note; rendering without tasks")
				data.recentNotesRendered = append(data.recentNotesRendered, notes.RenderNoteToMarkdown(nodes, nil))
				continue
			}

			taskMap := make(map[pgtype.UUID]sqlcgen.Task)
			for _, t := range noteTasks {
				if t.NodeID.Valid {
					taskMap[t.NodeID] = t
				}
			}

			rendered := notes.RenderNoteToMarkdown(nodes, taskMap)
			data.recentNotesRendered = append(data.recentNotesRendered, rendered)
		}
	}

	return data, nil
}

func (cb *ContextBuilder) formatContextPrompt(data *contextData, policy buildPolicy) string {
	var b strings.Builder

	b.WriteString(truncate(fmt.Sprintf("IDENTITY:\n%s\n\n", data.soul.Personality), MaxTier0Tokens))
	b.WriteString(formatProfile(data.soul.Profile))

	nowStr := time.Now().In(data.tzLoc).Format("2006-01-02 15:04:05 MST")
	weekday := time.Now().In(data.tzLoc).Weekday().String()

	b.WriteString(fmt.Sprintf("CURRENT CONTEXT:\nDate/Time: %s\nDay: %s\nTimezone: %s\n\n", nowStr, weekday, data.tzLoc.String()))

	briefing := buildIntelligenceBriefing(data.todayTasks, data.completedTasks, data.recentNotes, data.overdueCount)
	b.WriteString(truncate(briefing, MaxTierIBTokens))
	b.WriteString("\n")

	if policy.fetchTasks {
		tier2 := &strings.Builder{}
		tier2.WriteString("\nTODAY/OVERDUE TASKS:\n")
		writeTasksWithStatus(tier2, data.todayTasks)

		tier2.WriteString("\nRECENTLY COMPLETED (last 7 days):\n")
		writeTasksWithStatus(tier2, data.completedTasks)
		b.WriteString(truncate(tier2.String(), MaxTier2Tokens))
	}

	if policy.fetchRecentNotes {
		tier2 := &strings.Builder{}
		tier2.WriteString("\nRECENT NOTES (Last 48h):\n")
		for i, n := range data.recentNotes {
			tier2.WriteString(fmt.Sprintf("--- [%s] %s ---\n", uid.UUIDToString(n.ID), notes.DeriveTitle(n.Content)))
			if i < len(data.recentNotesRendered) {
				tier2.WriteString(data.recentNotesRendered[i])
			} else {
				tier2.WriteString(n.Content)
			}
			tier2.WriteString("\n")
		}
		b.WriteString(truncate(tier2.String(), MaxTier2Tokens))
	}

	if policy.searchNotes {
		tier3 := &strings.Builder{}
		tier3.WriteString("\nSEMANTIC SEARCH RESULTS:\n")
		for _, r := range data.semanticResults {
			tier3.WriteString(fmt.Sprintf("- [%s] %s (similarity: %.4f):\n%s\n", uid.UUIDToString(r.ID), notes.DeriveTitle(r.Content), r.Similarity, r.Content))
		}
		if len(data.semanticResults) == 0 {
			tier3.WriteString("(none)\n")
		}
		b.WriteString(truncate(tier3.String(), MaxTier3Tokens))
	}

	if policy.fetchLinkedNotes {
		tier4 := &strings.Builder{}
		tier4.WriteString("\nRELATED NOTES:\n")
		writeNotesWithID(tier4, data.linkedNotes)
		if len(data.linkedNotes) == 0 {
			tier4.WriteString("(none)\n")
		}
		b.WriteString(truncate(tier4.String(), MaxTier4Tokens))
	}

	if policy.searchMemories {
		tier5 := &strings.Builder{}
		tier5.WriteString("\nRELEVANT MEMORIES:\n")
		for _, m := range data.memResults {
			tier5.WriteString(fmt.Sprintf("- %s (similarity: %.4f)\n", m.Content, m.Similarity))
		}
		if len(data.memResults) == 0 {
			tier5.WriteString("(none)\n")
		}
		b.WriteString(truncate(tier5.String(), MaxTier5Tokens))
	}

	b.WriteString("\n")
	b.WriteString(systemPrompt)

	return b.String()
}

func formatProfile(profile []byte) string {
	if len(profile) == 0 {
		return ""
	}
	var m map[string]any
	if err := json.Unmarshal(profile, &m); err != nil {
		return ""
	}
	if len(m) == 0 {
		return ""
	}
	pretty, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return ""
	}
	return "USER PROFILE (stable preferences):\n" + string(pretty) + "\n"
}

func truncate(s string, maxBytes int) string {
	if len(s) <= maxBytes {
		return s
	}
	return s[:maxBytes] + "... [TRUNCATED]"
}

// BuildForRoutine builds the context RAG string concurrently, omitting the conversation history.
func (cb *ContextBuilder) BuildForRoutine(ctx context.Context, userID pgtype.UUID, routineType string) (string, error) {
	var tzLoc *time.Location = time.UTC

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
		// Fetch timezone preference and today's tasks sequentially in the same goroutine
		userSettings, err := cb.q.GetUserSettings(gCtx, userID)
		if err == nil && userSettings.Timezone != "" {
			if loc, locErr := time.LoadLocation(userSettings.Timezone); locErr == nil {
				tzLoc = loc
			}
		}

		var errToday error
		todayTasks, errToday = cb.tasksSvc.GetTodayTasksInTimezone(gCtx, userID, tzLoc)
		return errToday
	})

	g.Go(func() error {
		rows, err := cb.q.GetRecentNotes(gCtx, userID)
		if err != nil {
			return err
		}
		recentNotes = make([]sqlcgen.Note, len(rows))
		for i, r := range rows {
			recentNotes[i] = sqlcgen.Note{
				ID:              r.ID,
				UserID:          r.UserID,
				ContextID:       r.ContextID,
				Content:         r.Content,
				Excerpt:         r.Excerpt,
				IsInbox:         r.IsInbox,
				SearchVector:    r.SearchVector,
				CreatedAt:       r.CreatedAt,
				UpdatedAt:       r.UpdatedAt,
				DeletedAt:       r.DeletedAt,
				EmbeddingStatus: r.EmbeddingStatus,
				CollapseImages:  r.CollapseImages,
			}
		}
		return nil
	})

	if err := g.Wait(); err != nil {
		return "", err
	}

	now := time.Now().In(tzLoc)

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
`, now.Format(time.RFC3339), routineType, soul.Personality))

	profileStr := formatProfile(soul.Profile)
	if profileStr != "" {
		b.WriteString(fmt.Sprintf("\nUSER PROFILE:\n%s\n", profileStr))
	}

	b.WriteString(`TODAY / OVERDUE TASKS:
`)

	writeTasksWithDueDate(&b, todayTasks)

	b.WriteString("\nRECENT NOTES (Last 48h):\n")
	writeNotesWithContent(&b, recentNotes, 500)

	if len(semanticResults) > 0 {
		b.WriteString("\nRELEVANT NOTES (via semantic search):\n")
		for _, r := range semanticResults {
			b.WriteString(fmt.Sprintf("- [%s] %s (similarity: %.4f)\n", uid.UUIDToString(r.ID), notes.DeriveTitle(r.Content), r.Similarity))
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



func writeNotesWithID(b *strings.Builder, notesList []sqlcgen.Note) {
	for _, n := range notesList {
		b.WriteString(fmt.Sprintf("- ID: %s | Title: %s\n", uid.UUIDToString(n.ID), notes.DeriveTitle(n.Content)))
	}
}

func float64ToFloat32(src []float64) []float32 {
	dst := make([]float32, len(src))
	for i := range src {
		dst[i] = float32(src[i])
	}
	return dst
}

func writeNotesWithContent(b *strings.Builder, notesList []sqlcgen.Note, maxContentLen int) {
	for _, n := range notesList {
		content := n.Content
		if maxContentLen > 0 && len(content) > maxContentLen {
			content = content[:maxContentLen] + "... [TRUNCATED]"
		}
		b.WriteString(fmt.Sprintf("- Title: %s | Content: %s\n", notes.DeriveTitle(n.Content), content))
	}
}
