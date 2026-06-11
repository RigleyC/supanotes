package agent

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgtype"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/memories"
	"github.com/RigleyC/supanotes/internal/notes"
	"github.com/RigleyC/supanotes/internal/routines"
	"github.com/RigleyC/supanotes/internal/soul"
	"github.com/RigleyC/supanotes/internal/tasks"
	"github.com/RigleyC/supanotes/pkg/llm"
	"github.com/RigleyC/supanotes/pkg/uid"
	"github.com/pgvector/pgvector-go"
)

type ToolExecutor interface {
	Name() string
	Description() string
	SchemaJSON() string
	Execute(ctx context.Context, userID pgtype.UUID, argsJSON string) (string, error)
}

type ToolRegistry struct {
	tools map[string]ToolExecutor
}

func NewToolRegistry(q sqlcgen.Querier, notesSvc *notes.Service, tasksSvc *tasks.Service, memoriesSvc *memories.Service, routinesSvc *routines.Service, soulSvc *soul.Service, embedCL *llm.EmbeddingClient) *ToolRegistry {
	registry := &ToolRegistry{
		tools: make(map[string]ToolExecutor),
	}

	executors := []ToolExecutor{
		&AddNoteTool{notesSvc: notesSvc},
		&AddTaskTool{tasksSvc: tasksSvc},
		&SaveMemoryTool{memoriesSvc: memoriesSvc},
		&CompleteTaskTool{tasksSvc: tasksSvc},
		&GetOpenTasksTool{tasksSvc: tasksSvc},
		&ListMemoriesTool{memoriesSvc: memoriesSvc},
		&GetInboxNoteTool{notesSvc: notesSvc},
		&AppendToInboxTool{notesSvc: notesSvc},
		&SearchNotesTool{q: q, embedCL: embedCL},
		&GetSoulTool{q: q},
		&ListRoutinesTool{routinesSvc: routinesSvc},
		&TestDailyBriefTool{routinesSvc: routinesSvc},
		&TestWeeklyBriefTool{routinesSvc: routinesSvc},
		&SetDailyBriefScheduleTool{routinesSvc: routinesSvc},
		&SetWeeklyBriefScheduleTool{routinesSvc: routinesSvc},
		&GetNotesTool{notesSvc: notesSvc},
		&UpdateNoteTool{notesSvc: notesSvc},
		&AppendToNoteTool{notesSvc: notesSvc},
		&LinkNotesTool{q: q, notesSvc: notesSvc},
		&DeleteMemoryTool{memoriesSvc: memoriesSvc},
		&UpdateSoulTool{soulSvc: soulSvc},
		&GetTodayTasksTool{tasksSvc: tasksSvc},
		&UpdateTaskTool{tasksSvc: tasksSvc},
		&GetVaultContextTool{q: q},
	}

	for _, e := range executors {
		registry.tools[e.Name()] = e
	}

	return registry
}

func (tr *ToolRegistry) GetTools() []llm.Tool {
	var result []llm.Tool
	for _, e := range tr.tools {
		result = append(result, llm.Tool{
			Name:        e.Name(),
			Description: e.Description(),
			SchemaJSON:  e.SchemaJSON(),
		})
	}
	return result
}

func (tr *ToolRegistry) Execute(ctx context.Context, userID pgtype.UUID, toolName string, argsJSON string) (string, error) {
	executor, ok := tr.tools[toolName]
	if !ok {
		return "", fmt.Errorf("unknown tool: %s", toolName)
	}
	return executor.Execute(ctx, userID, argsJSON)
}

// --- helpers ---

func parseArgs[T any](argsJSON string) (T, error) {
	var args T
	if err := json.Unmarshal([]byte(argsJSON), &args); err != nil {
		return args, fmt.Errorf("parse args: %w", err)
	}
	return args, nil
}

func formatID(id pgtype.UUID) string {
	return uid.UUIDToString(id)
}

// --- AddNoteTool ---
type AddNoteTool struct {
	notesSvc *notes.Service
}

func (t *AddNoteTool) Name() string        { return "add_note" }
func (t *AddNoteTool) Description() string { return "Create a new note in the vault" }
func (t *AddNoteTool) SchemaJSON() string {
	return `{"type":"object","properties":{"title":{"type":"string"},"content":{"type":"string"}},"required":["title","content"]}`
}
func (t *AddNoteTool) Execute(ctx context.Context, userID pgtype.UUID, argsJSON string) (string, error) {
	args, err := parseArgs[struct {
		Title   string `json:"title"`
		Content string `json:"content"`
	}](argsJSON)
	if err != nil {
		return "", err
	}
	note, err := t.notesSvc.CreateNote(ctx, userID, &args.Title, args.Content, nil, false, false)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("Note created with ID: %s", formatID(note.ID)), nil
}

// --- AddTaskTool ---
type AddTaskTool struct {
	tasksSvc *tasks.Service
}

func (t *AddTaskTool) Name() string        { return "add_task" }
func (t *AddTaskTool) Description() string { return "Create a new actionable task" }
func (t *AddTaskTool) SchemaJSON() string {
	return `{"type":"object","properties":{"title":{"type":"string"},"note_id":{"type":"string"},"due_date":{"type":"string","description":"ISO 8601 date"},"recurrence":{"type":"string","enum":["none","daily","weekdays","weekly","monthly"]}},"required":["title"]}`
}
func (t *AddTaskTool) Execute(ctx context.Context, userID pgtype.UUID, argsJSON string) (string, error) {
	args, err := parseArgs[struct {
		Title      string  `json:"title"`
		NoteID     *string `json:"note_id"`
		DueDate    *string `json:"due_date"`
		Recurrence *string `json:"recurrence"`
	}](argsJSON)
	if err != nil {
		return "", err
	}
	var noteID pgtype.UUID
	if args.NoteID != nil {
		nid, err := uid.UUIDFromString(*args.NoteID)
		if err != nil {
			return "", fmt.Errorf("invalid note_id: %w", err)
		}
		noteID = nid
	}
	var dueDateTime *time.Time
	if args.DueDate != nil {
		t, err := time.Parse("2006-01-02", *args.DueDate)
		if err != nil {
			return "", fmt.Errorf("invalid due_date format, use YYYY-MM-DD: %w", err)
		}
		dueDateTime = &t
	}
	task, err := t.tasksSvc.CreateTask(ctx, userID, noteID, args.Title, dueDateTime, args.Recurrence, 0)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("Task created with ID: %s", formatID(task.ID)), nil
}

// --- SaveMemoryTool ---
type SaveMemoryTool struct {
	memoriesSvc *memories.Service
}

func (t *SaveMemoryTool) Name() string { return "save_memory" }
func (t *SaveMemoryTool) Description() string {
	return "Save an important fact or preference about the user"
}
func (t *SaveMemoryTool) SchemaJSON() string {
	return `{"type":"object","properties":{"content":{"type":"string"}},"required":["content"]}`
}
func (t *SaveMemoryTool) Execute(ctx context.Context, userID pgtype.UUID, argsJSON string) (string, error) {
	args, err := parseArgs[struct {
		Content string `json:"content"`
	}](argsJSON)
	if err != nil {
		return "", err
	}
	mem, err := t.memoriesSvc.CreateMemory(ctx, userID, args.Content)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("Memory saved with ID: %s", formatID(mem.ID)), nil
}

// --- CompleteTaskTool ---
type CompleteTaskTool struct {
	tasksSvc *tasks.Service
}

func (t *CompleteTaskTool) Name() string        { return "complete_task" }
func (t *CompleteTaskTool) Description() string { return "Mark a task as complete" }
func (t *CompleteTaskTool) SchemaJSON() string {
	return `{"type":"object","properties":{"task_id":{"type":"string"}},"required":["task_id"]}`
}
func (t *CompleteTaskTool) Execute(ctx context.Context, userID pgtype.UUID, argsJSON string) (string, error) {
	args, err := parseArgs[struct {
		TaskID string `json:"task_id"`
	}](argsJSON)
	if err != nil {
		return "", err
	}
	tid, err := uid.UUIDFromString(args.TaskID)
	if err != nil {
		return "", err
	}
	_, err = t.tasksSvc.CompleteTask(ctx, userID, tid)
	if err != nil {
		return "", err
	}
	return "Task marked as completed", nil
}

// --- GetOpenTasksTool ---
type GetOpenTasksTool struct {
	tasksSvc *tasks.Service
}

func (t *GetOpenTasksTool) Name() string        { return "get_open_tasks" }
func (t *GetOpenTasksTool) Description() string { return "List all open tasks" }
func (t *GetOpenTasksTool) SchemaJSON() string {
	return `{"type":"object","properties":{}}`
}
func (t *GetOpenTasksTool) Execute(ctx context.Context, userID pgtype.UUID, argsJSON string) (string, error) {
	openStatus := "open"
	tasksList, err := t.tasksSvc.GetTasks(ctx, userID, nil, &openStatus, nil, nil, 100, 0)
	if err != nil {
		return "", err
	}
	result := "Open Tasks:\n"
	for _, t := range tasksList {
		if t.Status == "open" {
			result += fmt.Sprintf("- [%s] %s\n", formatID(t.ID), t.Title)
		}
	}
	return result, nil
}

// --- ListMemoriesTool ---
type ListMemoriesTool struct {
	memoriesSvc *memories.Service
}

func (t *ListMemoriesTool) Name() string        { return "list_memories" }
func (t *ListMemoriesTool) Description() string { return "List all saved memories for the user" }
func (t *ListMemoriesTool) SchemaJSON() string {
	return `{"type":"object","properties":{}}`
}
func (t *ListMemoriesTool) Execute(ctx context.Context, userID pgtype.UUID, argsJSON string) (string, error) {
	mems, err := t.memoriesSvc.GetMemories(ctx, userID, 100, 0)
	if err != nil {
		return "", err
	}
	result := "Memories:\n"
	for _, m := range mems {
		result += fmt.Sprintf("- [%s] %s\n", formatID(m.ID), m.Content)
	}
	return result, nil
}

// --- GetInboxNoteTool ---
type GetInboxNoteTool struct {
	notesSvc *notes.Service
}

func (t *GetInboxNoteTool) Name() string { return "get_inbox_note" }
func (t *GetInboxNoteTool) Description() string {
	return "Get the current content of the user's Inbox note"
}
func (t *GetInboxNoteTool) SchemaJSON() string {
	return `{"type":"object","properties":{}}`
}
func (t *GetInboxNoteTool) Execute(ctx context.Context, userID pgtype.UUID, argsJSON string) (string, error) {
	note, err := t.notesSvc.GetInboxNote(ctx, userID)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("Inbox:\n%s", note.Content), nil
}

// --- AppendToInboxTool ---
type AppendToInboxTool struct {
	notesSvc *notes.Service
}

func (t *AppendToInboxTool) Name() string        { return "append_to_inbox" }
func (t *AppendToInboxTool) Description() string { return "Append text to the user's Inbox note" }
func (t *AppendToInboxTool) SchemaJSON() string {
	return `{"type":"object","properties":{"content":{"type":"string"}},"required":["content"]}`
}
func (t *AppendToInboxTool) Execute(ctx context.Context, userID pgtype.UUID, argsJSON string) (string, error) {
	args, err := parseArgs[struct {
		Content string `json:"content"`
	}](argsJSON)
	if err != nil {
		return "", err
	}
	_, err = t.notesSvc.AppendToInbox(ctx, userID, args.Content)
	if err != nil {
		return "", err
	}
	return "Content appended to Inbox", nil
}

// --- SearchNotesTool ---
type SearchNotesTool struct {
	q       sqlcgen.Querier
	embedCL *llm.EmbeddingClient
}

func (t *SearchNotesTool) Name() string { return "search_notes" }
func (t *SearchNotesTool) Description() string {
	return "Search for notes semantically related to a query"
}
func (t *SearchNotesTool) SchemaJSON() string {
	return `{"type":"object","properties":{"query":{"type":"string"}},"required":["query"]}`
}
func (t *SearchNotesTool) Execute(ctx context.Context, userID pgtype.UUID, argsJSON string) (string, error) {
	args, err := parseArgs[struct {
		Query string `json:"query"`
	}](argsJSON)
	if err != nil {
		return "", err
	}
	emb, err := t.embedCL.GenerateEmbedding(ctx, args.Query)
	if err != nil {
		return "", fmt.Errorf("generate embedding: %w", err)
	}
	vec := make([]float32, len(emb))
	for i := range emb {
		vec[i] = float32(emb[i])
	}
	results, err := t.q.SearchNotesByEmbedding(ctx, sqlcgen.SearchNotesByEmbeddingParams{
		UserID:  userID,
		Column2: pgvector.NewVector(vec),
		Limit:   10,
	})
	if err != nil {
		return "", err
	}
	var b strings.Builder
	for _, r := range results {
		b.WriteString(fmt.Sprintf("- [%s] %s (similarity: %d)\n", formatID(r.ID), r.Title.String, r.Similarity))
	}
	if b.Len() == 0 {
		return "No matching notes found", nil
	}
	return b.String(), nil
}

// --- GetSoulTool ---
type GetSoulTool struct {
	q sqlcgen.Querier
}

func (t *GetSoulTool) Name() string { return "get_soul" }
func (t *GetSoulTool) Description() string {
	return "Get the agent's Soul (personality and core directives)"
}
func (t *GetSoulTool) SchemaJSON() string {
	return `{"type":"object","properties":{}}`
}
func (t *GetSoulTool) Execute(ctx context.Context, userID pgtype.UUID, argsJSON string) (string, error) {
	soul, err := t.q.GetSoul(ctx, userID)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("Soul:\n%s", soul.Personality), nil
}

// --- ListRoutinesTool ---
type ListRoutinesTool struct {
	routinesSvc *routines.Service
}

func (t *ListRoutinesTool) Name() string { return "list_routines" }
func (t *ListRoutinesTool) Description() string {
	return "List all active routines (daily/weekly briefs)"
}
func (t *ListRoutinesTool) SchemaJSON() string {
	return `{"type":"object","properties":{}}`
}
func (t *ListRoutinesTool) Execute(ctx context.Context, userID pgtype.UUID, argsJSON string) (string, error) {
	rs, err := t.routinesSvc.GetRoutines(ctx, userID)
	if err != nil {
		return "", err
	}
	b, err := json.Marshal(rs)
	if err != nil {
		slog.Error("marshal routines response", "error", err)
		return "", err
	}
	return string(b), nil
}

// --- TestDailyBriefTool ---
type TestDailyBriefTool struct {
	routinesSvc *routines.Service
}

func (t *TestDailyBriefTool) Name() string { return "test_daily_brief" }
func (t *TestDailyBriefTool) Description() string {
	return "Run a dry-run test of the daily brief routine"
}
func (t *TestDailyBriefTool) SchemaJSON() string {
	return `{"type":"object","properties":{}}`
}
func (t *TestDailyBriefTool) Execute(ctx context.Context, userID pgtype.UUID, argsJSON string) (string, error) {
	resp, err := t.routinesSvc.TestRoutine(ctx, userID, "daily")
	if err != nil {
		return "", err
	}
	return resp, nil
}

// --- TestWeeklyBriefTool ---
type TestWeeklyBriefTool struct {
	routinesSvc *routines.Service
}

func (t *TestWeeklyBriefTool) Name() string { return "test_weekly_brief" }
func (t *TestWeeklyBriefTool) Description() string {
	return "Run a dry-run test of the weekly brief routine"
}
func (t *TestWeeklyBriefTool) SchemaJSON() string {
	return `{"type":"object","properties":{}}`
}
func (t *TestWeeklyBriefTool) Execute(ctx context.Context, userID pgtype.UUID, argsJSON string) (string, error) {
	resp, err := t.routinesSvc.TestRoutine(ctx, userID, "weekly")
	if err != nil {
		return "", err
	}
	return resp, nil
}

// --- SetDailyBriefScheduleTool ---
type SetDailyBriefScheduleTool struct {
	routinesSvc *routines.Service
}

func (t *SetDailyBriefScheduleTool) Name() string { return "set_daily_brief_schedule" }
func (t *SetDailyBriefScheduleTool) Description() string {
	return "Update the cron schedule or status for the daily brief"
}
func (t *SetDailyBriefScheduleTool) SchemaJSON() string {
	return `{"type":"object","properties":{"cron_expr":{"type":"string"},"enabled":{"type":"boolean"}}}`
}
func (t *SetDailyBriefScheduleTool) Execute(ctx context.Context, userID pgtype.UUID, argsJSON string) (string, error) {
	args, err := parseArgs[struct {
		CronExpr *string `json:"cron_expr"`
		Enabled  *bool   `json:"enabled"`
	}](argsJSON)
	if err != nil {
		return "", err
	}
	rs, err := t.routinesSvc.GetRoutines(ctx, userID)
	if err != nil {
		return "", err
	}
	for _, r := range rs {
		if r.Type == "daily" {
			updated, err := t.routinesSvc.UpdateRoutine(ctx, r.ID, userID, args.CronExpr, args.Enabled)
			if err != nil {
				return "", err
			}
			b, err := json.Marshal(updated)
			if err != nil {
				slog.Error("marshal updated daily routine", "error", err)
				return "", err
			}
			return string(b), nil
		}
	}
	return "Daily routine not found", nil
}

// --- GetNotesTool ---
type GetNotesTool struct {
	notesSvc *notes.Service
}

func (t *GetNotesTool) Name() string        { return "get_notes" }
func (t *GetNotesTool) Description() string { return "List notes in the vault" }
func (t *GetNotesTool) SchemaJSON() string {
	return `{"type":"object","properties":{"limit":{"type":"integer"}},"required":[]}`
}
func (t *GetNotesTool) Execute(ctx context.Context, userID pgtype.UUID, argsJSON string) (string, error) {
	args, err := parseArgs[struct {
		Limit int32 `json:"limit"`
	}](argsJSON)
	if err != nil {
		return "", err
	}
	if args.Limit <= 0 || args.Limit > 50 {
		args.Limit = 20
	}
	notesList, err := t.notesSvc.GetNotes(ctx, userID, nil, nil, args.Limit, nil, nil)
	if err != nil {
		return "", err
	}
	var b strings.Builder
	for _, n := range notesList {
		b.WriteString(fmt.Sprintf("- [%s] %s\n", formatID(n.ID), n.Title.String))
	}
	if b.Len() == 0 {
		return "No notes found", nil
	}
	return b.String(), nil
}

// --- UpdateNoteTool ---
type UpdateNoteTool struct {
	notesSvc *notes.Service
}

func (t *UpdateNoteTool) Name() string        { return "update_note" }
func (t *UpdateNoteTool) Description() string { return "Update title or content of a note" }
func (t *UpdateNoteTool) SchemaJSON() string {
	return `{"type":"object","properties":{"note_id":{"type":"string"},"title":{"type":"string"},"content":{"type":"string"}},"required":["note_id"]}`
}
func (t *UpdateNoteTool) Execute(ctx context.Context, userID pgtype.UUID, argsJSON string) (string, error) {
	args, err := parseArgs[struct {
		NoteID  string  `json:"note_id"`
		Title   *string `json:"title"`
		Content *string `json:"content"`
	}](argsJSON)
	if err != nil {
		return "", err
	}
	nid, err := uid.UUIDFromString(args.NoteID)
	if err != nil {
		return "", err
	}
	note, err := t.notesSvc.UpdateNote(ctx, userID, nid, args.Title, args.Content, nil, nil, nil)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("Note updated: [%s] %s", formatID(note.ID), note.Title.String), nil
}

// --- AppendToNoteTool ---
type AppendToNoteTool struct {
	notesSvc *notes.Service
}

func (t *AppendToNoteTool) Name() string        { return "append_to_note" }
func (t *AppendToNoteTool) Description() string { return "Append text to an existing note by ID" }
func (t *AppendToNoteTool) SchemaJSON() string {
	return `{"type":"object","properties":{"note_id":{"type":"string"},"content":{"type":"string"}},"required":["note_id","content"]}`
}
func (t *AppendToNoteTool) Execute(ctx context.Context, userID pgtype.UUID, argsJSON string) (string, error) {
	args, err := parseArgs[struct {
		NoteID  string `json:"note_id"`
		Content string `json:"content"`
	}](argsJSON)
	if err != nil {
		return "", err
	}
	nid, err := uid.UUIDFromString(args.NoteID)
	if err != nil {
		return "", err
	}
	note, err := t.notesSvc.GetNoteByID(ctx, nid, userID)
	if err != nil {
		return "", err
	}
	newContent := note.Content + "\n" + args.Content
	updated, err := t.notesSvc.UpdateNote(ctx, userID, nid, nil, &newContent, nil, nil, nil)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("Content appended to note [%s] %s", formatID(updated.ID), updated.Title.String), nil
}

// --- LinkNotesTool ---
type LinkNotesTool struct {
	q        sqlcgen.Querier
	notesSvc *notes.Service
}

func (t *LinkNotesTool) Name() string        { return "link_notes" }
func (t *LinkNotesTool) Description() string { return "Create a bi-directional link between two notes" }
func (t *LinkNotesTool) SchemaJSON() string {
	return `{"type":"object","properties":{"source_id":{"type":"string"},"target_id":{"type":"string"}},"required":["source_id","target_id"]}`
}
func (t *LinkNotesTool) Execute(ctx context.Context, userID pgtype.UUID, argsJSON string) (string, error) {
	args, err := parseArgs[struct {
		SourceID string `json:"source_id"`
		TargetID string `json:"target_id"`
	}](argsJSON)
	if err != nil {
		return "", err
	}

	srcID, err := uid.UUIDFromString(args.SourceID)
	if err != nil {
		return "", fmt.Errorf("invalid source_id: %w", err)
	}
	tgtID, err := uid.UUIDFromString(args.TargetID)
	if err != nil {
		return "", fmt.Errorf("invalid target_id: %w", err)
	}

	if _, err := t.notesSvc.GetNoteByID(ctx, srcID, userID); err != nil {
		return "", fmt.Errorf("source note not found: %w", err)
	}
	if _, err := t.notesSvc.GetNoteByID(ctx, tgtID, userID); err != nil {
		return "", fmt.Errorf("target note not found: %w", err)
	}

	if err := t.q.CreateNoteLink(ctx, sqlcgen.CreateNoteLinkParams{
		SourceID: srcID,
		TargetID: tgtID,
	}); err != nil {
		return "", fmt.Errorf("create link: %w", err)
	}

	return fmt.Sprintf("Bi-directional link created between [%s] and [%s]", args.SourceID, args.TargetID), nil
}

// --- DeleteMemoryTool ---
type DeleteMemoryTool struct {
	memoriesSvc *memories.Service
}

func (t *DeleteMemoryTool) Name() string        { return "delete_memory" }
func (t *DeleteMemoryTool) Description() string { return "Delete a specific memory by ID" }
func (t *DeleteMemoryTool) SchemaJSON() string {
	return `{"type":"object","properties":{"memory_id":{"type":"string"}},"required":["memory_id"]}`
}
func (t *DeleteMemoryTool) Execute(ctx context.Context, userID pgtype.UUID, argsJSON string) (string, error) {
	args, err := parseArgs[struct {
		MemoryID string `json:"memory_id"`
	}](argsJSON)
	if err != nil {
		return "", err
	}
	mid, err := uid.UUIDFromString(args.MemoryID)
	if err != nil {
		return "", err
	}
	if err := t.memoriesSvc.DeleteMemory(ctx, mid, userID); err != nil {
		return "", err
	}
	return "Memory deleted", nil
}

// --- UpdateSoulTool ---
type UpdateSoulTool struct {
	soulSvc *soul.Service
}

func (t *UpdateSoulTool) Name() string        { return "update_soul" }
func (t *UpdateSoulTool) Description() string { return "Update the agent's personality (Soul)" }
func (t *UpdateSoulTool) SchemaJSON() string {
	return `{"type":"object","properties":{"content":{"type":"string"}},"required":["content"]}`
}
func (t *UpdateSoulTool) Execute(ctx context.Context, userID pgtype.UUID, argsJSON string) (string, error) {
	args, err := parseArgs[struct {
		Content string `json:"content"`
	}](argsJSON)
	if err != nil {
		return "", err
	}
	if _, err := t.soulSvc.Update(ctx, userID, args.Content); err != nil {
		return "", err
	}
	return "Soul updated", nil
}

// --- GetTodayTasksTool ---
type GetTodayTasksTool struct {
	tasksSvc *tasks.Service
}

func (t *GetTodayTasksTool) Name() string        { return "get_today_tasks" }
func (t *GetTodayTasksTool) Description() string { return "List today's tasks" }
func (t *GetTodayTasksTool) SchemaJSON() string {
	return `{"type":"object","properties":{}}`
}
func (t *GetTodayTasksTool) Execute(ctx context.Context, userID pgtype.UUID, argsJSON string) (string, error) {
	ts, err := t.tasksSvc.GetTodayTasks(ctx, userID)
	if err != nil {
		return "", err
	}
	var b strings.Builder
	for _, task := range ts {
		b.WriteString(fmt.Sprintf("- [%s] %s (Due: %v)\n", task.Status, task.Title, task.DueDate.Time))
	}
	if b.Len() == 0 {
		return "No tasks for today", nil
	}
	return b.String(), nil
}

// --- UpdateTaskTool ---
type UpdateTaskTool struct {
	tasksSvc *tasks.Service
}

func (t *UpdateTaskTool) Name() string { return "update_task" }
func (t *UpdateTaskTool) Description() string {
	return "Update a task's title, due_date, or recurrence"
}
func (t *UpdateTaskTool) SchemaJSON() string {
	return `{"type":"object","properties":{"task_id":{"type":"string"},"title":{"type":"string"},"due_date":{"type":"string","description":"ISO 8601 date"},"recurrence":{"type":"string","enum":["daily","weekdays","weekly","monthly"]}},"required":["task_id"]}`
}
func (t *UpdateTaskTool) Execute(ctx context.Context, userID pgtype.UUID, argsJSON string) (string, error) {
	args, err := parseArgs[struct {
		TaskID     string  `json:"task_id"`
		Title      *string `json:"title"`
		DueDate    *string `json:"due_date"`
		Recurrence *string `json:"recurrence"`
	}](argsJSON)
	if err != nil {
		return "", err
	}
	tid, err := uid.UUIDFromString(args.TaskID)
	if err != nil {
		return "", err
	}
	var dueDateTime *time.Time
	if args.DueDate != nil {
		t, err := time.Parse("2006-01-02", *args.DueDate)
		if err != nil {
			return "", fmt.Errorf("invalid due_date format, use YYYY-MM-DD: %w", err)
		}
		dueDateTime = &t
	}
	updated, err := t.tasksSvc.UpdateTask(ctx, userID, tid, args.Title, nil, dueDateTime, args.Recurrence, nil)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("Task updated: [%s] %s", formatID(updated.ID), updated.Title), nil
}

// --- GetVaultContextTool ---
type GetVaultContextTool struct {
	q sqlcgen.Querier
}

func (t *GetVaultContextTool) Name() string { return "get_vault_context" }
func (t *GetVaultContextTool) Description() string {
	return "Returns stats about the vault: total notes, tasks, contexts, tags"
}
func (t *GetVaultContextTool) SchemaJSON() string {
	return `{"type":"object","properties":{}}`
}
func (t *GetVaultContextTool) Execute(ctx context.Context, userID pgtype.UUID, argsJSON string) (string, error) {
	noteCount, err := t.q.CountNotes(ctx, userID)
	if err != nil {
		return "", fmt.Errorf("count notes: %w", err)
	}
	openTaskCount, err := t.q.CountOpenTasks(ctx, userID)
	if err != nil {
		return "", fmt.Errorf("count open tasks: %w", err)
	}
	completedTaskCount, err := t.q.CountCompletedTasks(ctx, userID)
	if err != nil {
		return "", fmt.Errorf("count completed tasks: %w", err)
	}
	contexts, err := t.q.GetContexts(ctx, userID)
	if err != nil {
		return "", fmt.Errorf("get contexts: %w", err)
	}
	tags, err := t.q.GetTags(ctx, userID)
	if err != nil {
		return "", fmt.Errorf("get tags: %w", err)
	}
	return fmt.Sprintf(`Vault Stats:
- Notes: %d
- Open Tasks: %d
- Completed Tasks: %d
- Contexts: %d
- Tags: %d`, noteCount, openTaskCount, completedTaskCount, len(contexts), len(tags)), nil
}

// --- SetWeeklyBriefScheduleTool ---
type SetWeeklyBriefScheduleTool struct {
	routinesSvc *routines.Service
}

func (t *SetWeeklyBriefScheduleTool) Name() string { return "set_weekly_brief_schedule" }
func (t *SetWeeklyBriefScheduleTool) Description() string {
	return "Update the cron schedule or status for the weekly brief"
}
func (t *SetWeeklyBriefScheduleTool) SchemaJSON() string {
	return `{"type":"object","properties":{"cron_expr":{"type":"string"},"enabled":{"type":"boolean"}}}`
}
func (t *SetWeeklyBriefScheduleTool) Execute(ctx context.Context, userID pgtype.UUID, argsJSON string) (string, error) {
	args, err := parseArgs[struct {
		CronExpr *string `json:"cron_expr"`
		Enabled  *bool   `json:"enabled"`
	}](argsJSON)
	if err != nil {
		return "", err
	}
	rs, err := t.routinesSvc.GetRoutines(ctx, userID)
	if err != nil {
		return "", err
	}
	for _, r := range rs {
		if r.Type == "weekly" {
			updated, err := t.routinesSvc.UpdateRoutine(ctx, r.ID, userID, args.CronExpr, args.Enabled)
			if err != nil {
				return "", err
			}
			b, err := json.Marshal(updated)
			if err != nil {
				slog.Error("marshal updated weekly routine", "error", err)
				return "", err
			}
			return string(b), nil
		}
	}
	return "Weekly routine not found", nil
}
