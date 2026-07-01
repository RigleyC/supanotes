package tools

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/pgvector/pgvector-go"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/notes"
	"github.com/RigleyC/supanotes/pkg/llm"
	"github.com/RigleyC/supanotes/pkg/uid"
)

type AddNoteTool struct {
	notesSvc *notes.Service
}

func (t *AddNoteTool) Name() string        { return "add_note" }
func (t *AddNoteTool) Description() string { return "Create a new note in the vault" }
func (t *AddNoteTool) Label() string       { return "Atualizando notas" }
func (t *AddNoteTool) Summary(string) string { return "[Note created successfully]" }

func (t *AddNoteTool) SchemaJSON() string {
	return `{"type":"object","properties":{"content":{"type":"string"}},"required":["content"]}`
}
func (t *AddNoteTool) Execute(ctx context.Context, userID pgtype.UUID, sessionID string, argsJSON string) (string, error) {
	args, err := parseArgs[struct {
		Content string `json:"content"`
	}](argsJSON)
	if err != nil {
		return "", err
	}
	note, err := t.notesSvc.CreateNote(ctx, userID, args.Content, nil, false)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("Note created with ID: %s", formatID(note.ID)), nil
}

type GetInboxNoteTool struct {
	notesSvc *notes.Service
}

func (t *GetInboxNoteTool) Name() string { return "get_inbox_note" }
func (t *GetInboxNoteTool) Description() string {
	return "Get the content of the user's Inbox note. The Inbox is a special note where the user quickly dumps ideas, reminders, and random thoughts. Read this when the user asks about quick notes or unorganized items."
}
func (t *GetInboxNoteTool) Label() string { return "Lendo notas" }
func (t *GetInboxNoteTool) Summary(string) string { return "[GetInboxNoteTool executed successfully]" }

func (t *GetInboxNoteTool) SchemaJSON() string {
	return `{"type":"object","properties":{}}`
}
func (t *GetInboxNoteTool) Execute(ctx context.Context, userID pgtype.UUID, sessionID string, argsJSON string) (string, error) {
	note, err := t.notesSvc.GetInboxNote(ctx, userID)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("Inbox:\n%s", note.Content), nil
}

type AppendToInboxTool struct {
	notesSvc *notes.Service
}

func (t *AppendToInboxTool) Name() string        { return "append_to_inbox" }
func (t *AppendToInboxTool) Description() string { return "Append text to the user's Inbox note" }
func (t *AppendToInboxTool) Label() string { return "Atualizando notas" }
func (t *AppendToInboxTool) Summary(string) string { return "[AppendToInboxTool executed successfully]" }

func (t *AppendToInboxTool) SchemaJSON() string {
	return `{"type":"object","properties":{"content":{"type":"string"}},"required":["content"]}`
}
func (t *AppendToInboxTool) Execute(ctx context.Context, userID pgtype.UUID, sessionID string, argsJSON string) (string, error) {
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

type SearchNotesTool struct {
	q       sqlcgen.Querier
	embedCL *llm.EmbeddingClient
}

func (t *SearchNotesTool) Name() string { return "search_notes" }
func (t *SearchNotesTool) Description() string {
	return "Search notes semantically by query. Returns matching notes with similarity scores. Use this to find relevant notes before answering user questions about specific topics (e.g., 'treino', 'mercado', 'trabalho')."
}
func (t *SearchNotesTool) Label() string { return "Buscando notas" }
func (t *SearchNotesTool) Summary(string) string { return "[Search results retrieved]" }

func (t *SearchNotesTool) SchemaJSON() string {
	return `{"type":"object","properties":{"query":{"type":"string"}},"required":["query"]}`
}
func (t *SearchNotesTool) Execute(ctx context.Context, userID pgtype.UUID, sessionID string, argsJSON string) (string, error) {
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
		b.WriteString(fmt.Sprintf("- [%s] %s (similarity: %.4f)\n", formatID(r.ID), r.Title, r.Similarity))
	}
	if b.Len() == 0 {
		return "No matching notes found", nil
	}
	return b.String(), nil
}

type GetNotesTool struct {
	notesSvc *notes.Service
}

func (t *GetNotesTool) Name() string { return "get_notes" }
func (t *GetNotesTool) Description() string {
	return "List notes in the vault with their titles and IDs. Use get_note to read the full content of a specific note after listing."
}
func (t *GetNotesTool) Label() string { return "Lendo notas" }
func (t *GetNotesTool) Summary(string) string { return "[GetNotesTool executed successfully]" }

func (t *GetNotesTool) SchemaJSON() string {
	return `{"type":"object","properties":{"limit":{"type":"integer"}},"required":[]}`
}
func (t *GetNotesTool) Execute(ctx context.Context, userID pgtype.UUID, sessionID string, argsJSON string) (string, error) {
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
		b.WriteString(fmt.Sprintf("- [%s] %s\n", formatID(n.ID), notes.DeriveTitle(n.Content)))
	}
	if b.Len() == 0 {
		return "No notes found", nil
	}
	return b.String(), nil
}

type GetNoteTool struct {
	notesSvc *notes.Service
}

func (t *GetNoteTool) Name() string { return "get_note" }
func (t *GetNoteTool) Description() string {
	return "Retrieve the full content of a specific note by ID. Returns title and complete markdown content including all tasks and bullet points. Always use this when you need the full context of a note to answer the user."
}
func (t *GetNoteTool) Label() string { return "Lendo notas" }
func (t *GetNoteTool) Summary(string) string { return "[Retrieved note contents successfully]" }

func (t *GetNoteTool) SchemaJSON() string {
	return `{"type":"object","properties":{"note_id":{"type":"string"}},"required":["note_id"]}`
}
func (t *GetNoteTool) Execute(ctx context.Context, userID pgtype.UUID, sessionID string, argsJSON string) (string, error) {
	args, err := parseArgs[struct {
		NoteID string `json:"note_id"`
	}](argsJSON)
	if err != nil {
		return "", err
	}
	nid, err := uid.UUIDFromString(args.NoteID)
	if err != nil {
		return "", fmt.Errorf("invalid note ID format: %w", err)
	}
	note, err := t.notesSvc.GetNoteByID(ctx, nid, userID)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("Note [%s] %s:\n%s", formatID(note.ID), notes.DeriveTitle(note.Content), note.Content), nil
}

type UpdateNoteTool struct {
	notesSvc *notes.Service
}

func (t *UpdateNoteTool) Name() string        { return "update_note" }
func (t *UpdateNoteTool) Description() string { return "Update content of a note" }
func (t *UpdateNoteTool) Label() string { return "Atualizando notas" }
func (t *UpdateNoteTool) Summary(string) string { return "[UpdateNoteTool executed successfully]" }

func (t *UpdateNoteTool) SchemaJSON() string {
	return `{"type":"object","properties":{"note_id":{"type":"string"},"content":{"type":"string"}},"required":["note_id"]}`
}
func (t *UpdateNoteTool) Execute(ctx context.Context, userID pgtype.UUID, sessionID string, argsJSON string) (string, error) {
	args, err := parseArgs[struct {
		NoteID  string  `json:"note_id"`
		Content *string `json:"content"`
	}](argsJSON)
	if err != nil {
		return "", err
	}
	nid, err := uid.UUIDFromString(args.NoteID)
	if err != nil {
		return "", err
	}
	note, err := t.notesSvc.UpdateNote(ctx, userID, nid, args.Content, nil, nil)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("Note updated: [%s] %s", formatID(note.ID), notes.DeriveTitle(note.Content)), nil
}

type AppendToNoteTool struct {
	notesSvc *notes.Service
}

func (t *AppendToNoteTool) Name() string        { return "append_to_note" }
func (t *AppendToNoteTool) Description() string { return "Append text to an existing note by ID" }
func (t *AppendToNoteTool) Label() string { return "Atualizando notas" }
func (t *AppendToNoteTool) Summary(string) string { return "[AppendToNoteTool executed successfully]" }

func (t *AppendToNoteTool) SchemaJSON() string {
	return `{"type":"object","properties":{"note_id":{"type":"string"},"content":{"type":"string"}},"required":["note_id","content"]}`
}
func (t *AppendToNoteTool) Execute(ctx context.Context, userID pgtype.UUID, sessionID string, argsJSON string) (string, error) {
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
	updated, err := t.notesSvc.UpdateNote(ctx, userID, nid, &newContent, nil, nil)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("Content appended to note [%s] %s", formatID(updated.ID), notes.DeriveTitle(updated.Content)), nil
}

type LinkNotesTool struct {
	q        sqlcgen.Querier
	notesSvc *notes.Service
}

func (t *LinkNotesTool) Name() string        { return "link_notes" }
func (t *LinkNotesTool) Description() string { return "Create a bi-directional link between two notes" }
func (t *LinkNotesTool) Label() string { return "Atualizando notas" }
func (t *LinkNotesTool) Summary(string) string { return "[LinkNotesTool executed successfully]" }

func (t *LinkNotesTool) SchemaJSON() string {
	return `{"type":"object","properties":{"source_id":{"type":"string"},"target_id":{"type":"string"}},"required":["source_id","target_id"]}`
}
func (t *LinkNotesTool) Execute(ctx context.Context, userID pgtype.UUID, sessionID string, argsJSON string) (string, error) {
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

type GetVaultContextTool struct {
	q sqlcgen.Querier
}

func (t *GetVaultContextTool) Name() string { return "get_vault_context" }
func (t *GetVaultContextTool) Description() string {
	return "Returns stats about the vault: total notes, tasks, contexts, tags"
}
func (t *GetVaultContextTool) Label() string { return "Lendo notas" }
func (t *GetVaultContextTool) Summary(string) string { return "[GetVaultContextTool executed successfully]" }

func (t *GetVaultContextTool) SchemaJSON() string {
	return `{"type":"object","properties":{}}`
}
func (t *GetVaultContextTool) Execute(ctx context.Context, userID pgtype.UUID, sessionID string, argsJSON string) (string, error) {
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

type PlanInboxOrganizationTool struct {
	notesSvc  *notes.Service
	llmClient llm.Client
}

func (t *PlanInboxOrganizationTool) Name() string { return "plan_inbox_organization" }
func (t *PlanInboxOrganizationTool) Description() string {
	return "Analyze the inbox content and propose how to organize snippets into notes, without editing anything"
}
func (t *PlanInboxOrganizationTool) Label() string { return "Analisando notas" }
func (t *PlanInboxOrganizationTool) Summary(string) string { return "[PlanInboxOrganizationTool executed successfully]" }

func (t *PlanInboxOrganizationTool) SchemaJSON() string {
	return `{"type":"object","properties":{}}`
}
func (t *PlanInboxOrganizationTool) Execute(ctx context.Context, userID pgtype.UUID, sessionID string, argsJSON string) (string, error) {
	items, err := t.notesSvc.PlanInboxOrganization(ctx, userID, t.llmClient)
	if err != nil {
		return "", err
	}
	bytes, err := json.Marshal(items)
	if err != nil {
		return "", err
	}
	return string(bytes), nil
}

type ApplyInboxOrganizationTool struct {
	notesSvc *notes.Service
}

func (t *ApplyInboxOrganizationTool) Name() string { return "apply_inbox_organization" }
func (t *ApplyInboxOrganizationTool) Description() string {
	return "Apply a confirmed inbox organization plan and remove organized items from the inbox"
}
func (t *ApplyInboxOrganizationTool) Label() string { return "Atualizando notas" }
func (t *ApplyInboxOrganizationTool) Summary(string) string { return "[ApplyInboxOrganizationTool executed successfully]" }

func (t *ApplyInboxOrganizationTool) SchemaJSON() string {
	return `{"type":"object","properties":{"items":{"type":"array","items":{"type":"object","properties":{"item_id":{"type":"string"},"destination_type":{"type":"string"},"destination_note_id":{"type":"string"},"destination_title":{"type":"string"},"accepted":{"type":"boolean"}},"required":["item_id","destination_type","accepted"]}}},"required":["items"]}`
}
func (t *ApplyInboxOrganizationTool) Execute(ctx context.Context, userID pgtype.UUID, sessionID string, argsJSON string) (string, error) {
	var args struct {
		Items []notes.PlanOrganizationItem `json:"items"`
	}
	if err := json.Unmarshal([]byte(argsJSON), &args); err != nil {
		return "", fmt.Errorf("parse args: %w", err)
	}
	if err := t.notesSvc.ApplyOrganization(ctx, userID, args.Items); err != nil {
		return "", err
	}
	return "Inbox organization plan applied successfully", nil
}
