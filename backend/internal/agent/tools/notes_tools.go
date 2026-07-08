package tools

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/pgvector/pgvector-go"
	"github.com/reearth/ygo/crdt"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/notes"
	"github.com/RigleyC/supanotes/pkg/llm"
	"github.com/RigleyC/supanotes/pkg/uid"
)

type AddNoteTool struct {
	notesSvc *notes.Service
	q        sqlcgen.Querier
	yjsSvc   YjsMutationService
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

	note, err := t.q.CreateNote(ctx, sqlcgen.CreateNoteParams{
		UserID:          userID,
		Content:         args.Content,
		EmbeddingStatus: "pending",
	})
	if err != nil {
		return "", err
	}

	noteIDStr := formatID(note.ID)
	userIDStr := formatID(userID)

	parsed := notes.ParseMarkdownToNodes(args.Content)
	doc := crdt.New(crdt.WithGC(false))
	nodesMap := doc.GetMap("nodes")
	tasksMap := doc.GetMap("tasks")
	now := float64(time.Now().UnixMilli())

	doc.Transact(func(txn *crdt.Transaction) {
		for i, nd := range parsed {
			nodeID := formatID(nd.ID)
			ndJSON := serializeNoteNode(nodeID, nd.Type, nd.Data, float64(i), now)
			nodesMap.Set(txn, nodeID, string(ndJSON))

			// Create YText for character-level CRDT on text content
			if nd.Text != "" {
				textType := doc.GetText("content/" + nodeID)
				textType.Insert(txn, 0, nd.Text, nil)
			}

			if nd.IsTask {
				taskID := uuid.New().String()
				status := "open"
				if nd.Complete {
					status = "done"
				}
				tdJSON := serializeTask(taskID, noteIDStr, userIDStr, nd.Text, status, float64(i), now)
				tasksMap.Set(txn, taskID, string(tdJSON))
			}
		}
	})
	update := crdt.EncodeStateAsUpdateV1(doc, nil)

	if err := t.yjsSvc.WriteNodeMutation(ctx, noteIDStr, update); err != nil {
		return "", fmt.Errorf("write node mutation: %w", err)
	}

	return fmt.Sprintf("Note created with ID: %s", formatID(note.ID)), nil
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
		b.WriteString(fmt.Sprintf("- [%s] %s\n", formatID(n.ID), n.Title))
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
	markdown, err := t.notesSvc.GetNoteMarkdownByID(ctx, nid, userID)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("Note [%s] %s:\n%s", formatID(note.ID), notes.DeriveTitle(markdown), markdown), nil
}

type AppendToNoteTool struct {
	notesSvc *notes.Service
	q        sqlcgen.Querier
	yjsSvc   YjsMutationService
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

	existingNodes, err := t.q.GetNodesByNoteId(ctx, nid)
	if err != nil {
		return "", fmt.Errorf("get existing nodes: %w", err)
	}
	startPos := len(existingNodes)
	noteIDStr := formatID(nid)
	userIDStr := formatID(userID)

	parsed := notes.ParseMarkdownToNodes(args.Content)
	doc := crdt.New(crdt.WithGC(false))
	nodesMap := doc.GetMap("nodes")
	tasksMap := doc.GetMap("tasks")
	now := float64(time.Now().UnixMilli())

	doc.Transact(func(txn *crdt.Transaction) {
		for i, nd := range parsed {
			nodeID := formatID(nd.ID)
			pos := float64(startPos + i)
			ndJSON := serializeNoteNode(nodeID, nd.Type, nd.Data, pos, now)
			nodesMap.Set(txn, nodeID, string(ndJSON))

			// Create YText for character-level CRDT on text content
			if nd.Text != "" {
				textType := doc.GetText("content/" + nodeID)
				textType.Insert(txn, 0, nd.Text, nil)
			}

			if nd.IsTask {
				taskID := uuid.New().String()
				status := "open"
				if nd.Complete {
					status = "done"
				}
				tdJSON := serializeTask(taskID, noteIDStr, userIDStr, nd.Text, status, pos, now)
				tasksMap.Set(txn, taskID, string(tdJSON))
			}
		}
	})
	update := crdt.EncodeStateAsUpdateV1(doc, nil)

	if err := t.yjsSvc.WriteNodeMutation(ctx, noteIDStr, update); err != nil {
		return "", fmt.Errorf("write node mutation: %w", err)
	}

	updated, err := t.notesSvc.AppendToNoteContent(ctx, userID, nid, args.Content)
	if err != nil {
		return "", fmt.Errorf("append to note content: %w", err)
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

type noteNodeJSON struct {
	ID        string          `json:"id"`
	ParentID  string          `json:"parentId,omitempty"`
	Position  float64         `json:"position"`
	Type      string          `json:"type"`
	Data      json.RawMessage `json:"data"`
	CreatedAt float64         `json:"createdAt,omitempty"`
	UpdatedAt float64         `json:"updatedAt,omitempty"`
}

type taskJSON struct {
	ID          string  `json:"id"`
	NoteID      string  `json:"noteId"`
	UserID      string  `json:"userId,omitempty"`
	Title       string  `json:"title"`
	Status      string  `json:"status"`
	Position    float64 `json:"position"`
	Recurrence  string  `json:"recurrence,omitempty"`
	DueDate     string  `json:"dueDate,omitempty"`
	CreatedAt   float64 `json:"createdAt,omitempty"`
	CompletedAt float64 `json:"completedAt,omitempty"`
}

func serializeNoteNode(id, typ string, data []byte, position, createdAt float64) []byte {
	j := noteNodeJSON{ID: id, Type: typ, Data: data, Position: position, CreatedAt: createdAt}
	b, _ := json.Marshal(j)
	return b
}

func serializeTask(id, noteID, userID, title, status string, position, createdAt float64) []byte {
	j := taskJSON{ID: id, NoteID: noteID, UserID: userID, Title: title, Status: status, Position: position, CreatedAt: createdAt}
	b, _ := json.Marshal(j)
	return b
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


