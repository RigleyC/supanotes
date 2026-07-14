package tools

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/pgvector/pgvector-go"
	"github.com/reearth/ygo/crdt"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/notes"
	syncpkg "github.com/RigleyC/supanotes/internal/sync"
	"github.com/RigleyC/supanotes/internal/utils"
	"github.com/RigleyC/supanotes/pkg/llm"
	"github.com/RigleyC/supanotes/pkg/uid"
)

type AddNoteTool struct {
	notesSvc *notes.Service
	q        sqlcgen.Querier
	yjsSvc   *syncpkg.YDocService
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
		Content:         "",
		EmbeddingStatus: "pending",
	})
	if err != nil {
		return "", err
	}

	noteIDStr := formatID(note.ID)

	parsed := notes.ParseMarkdownToNodes(args.Content)
	doc := crdt.New(crdt.WithGC(false))
	nodesMap := doc.GetMap("nodes")
	now := float64(time.Now().UnixMilli())

	doc.Transact(func(txn *crdt.Transaction) {
		prev := ""
		for _, nd := range parsed {
			nodeID := formatID(nd.ID)
			pos, err := utils.GenerateKeyBetween(prev, "")
			if err != nil {
				pos = prev + "1"
			}
			prev = pos

			nodeData := nd.Data
			if nd.IsTask {
				var dm map[string]interface{}
				json.Unmarshal(nd.Data, &dm)
				dm["completed"] = nd.Complete
				nodeData, _ = json.Marshal(dm)
			}

			ndJSON := serializeNoteNode(nodeID, nd.Type, nodeData, pos, now)
			nodesMap.Set(txn, nodeID, string(ndJSON))

			// Create YText for character-level CRDT on text content
			if nd.Text != "" {
				textType := doc.GetText("content/" + nodeID)
				textType.Insert(txn, 0, nd.Text, nil)
			}
		}
	})
	update := crdt.EncodeStateAsUpdateV1(doc, nil)

	if err := t.yjsSvc.ApplyNodeMutation(ctx, noteIDStr, update); err != nil {
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
	yjsSvc   *syncpkg.YDocService
	pool     *pgxpool.Pool
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

	var hasAccess bool
	err = t.pool.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM notes WHERE id = $1 AND user_id = $2
			UNION ALL
			SELECT 1 FROM note_shares WHERE note_id = $1 AND user_id = $2 AND permission = 'edit'
		)
	`, nid, userID).Scan(&hasAccess)
	if err != nil {
		return "", fmt.Errorf("permission check: %w", err)
	}
	if !hasAccess {
		return "", fmt.Errorf("access denied: note %s", formatID(nid))
	}

	// Find max position of existing nodes so new content appends at the end
	prev := ""
	if t.pool != nil {
		state, err := syncpkg.LoadYDocState(ctx, t.pool, formatID(nid))
		if err == nil && len(state) > 0 {
			existing := crdt.New(crdt.WithGC(false))
			if err := crdt.ApplyUpdateV1(existing, state, nil); err == nil {
				prev = lastNodePosition(existing)
			}
		}
	}

	parsed := notes.ParseMarkdownToNodes(args.Content)
	doc := crdt.New(crdt.WithGC(false))
	nodesMap := doc.GetMap("nodes")
	now := float64(time.Now().UnixMilli())

	doc.Transact(func(txn *crdt.Transaction) {
		for _, nd := range parsed {
			nodeID := formatID(nd.ID)
			pos, err := utils.GenerateKeyBetween(prev, "")
			if err != nil {
				pos = prev + "1"
			}
			prev = pos

			nodeData := nd.Data
			if nd.IsTask {
				var dm map[string]interface{}
				json.Unmarshal(nd.Data, &dm)
				dm["completed"] = nd.Complete
				nodeData, _ = json.Marshal(dm)
			}

			ndJSON := serializeNoteNode(nodeID, nd.Type, nodeData, pos, now)
			nodesMap.Set(txn, nodeID, string(ndJSON))

			// Create YText for character-level CRDT on text content
			if nd.Text != "" {
				textType := doc.GetText("content/" + nodeID)
				textType.Insert(txn, 0, nd.Text, nil)
			}
		}
	})
	update := crdt.EncodeStateAsUpdateV1(doc, nil)

	if err := t.yjsSvc.ApplyNodeMutation(ctx, formatID(nid), update); err != nil {
		return "", fmt.Errorf("write node mutation: %w", err)
	}

	return fmt.Sprintf("Content appended to note [%s]", formatID(nid)), nil
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
	Position  string          `json:"position"`
	Type      string          `json:"type"`
	Data      json.RawMessage `json:"data"`
	CreatedAt float64         `json:"createdAt,omitempty"`
	UpdatedAt float64         `json:"updatedAt,omitempty"`
}

func serializeNoteNode(id, typ string, data []byte, position string, createdAt float64) []byte {
	j := noteNodeJSON{ID: id, Type: typ, Data: data, Position: position, CreatedAt: createdAt}
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

// lastNodePosition returns the maximum position value across all YMap("nodes") entries.
func lastNodePosition(doc *crdt.Doc) string {
	nodesMap := doc.GetMap("nodes")
	if nodesMap == nil {
		return ""
	}
	var maxPos string
	for _, key := range nodesMap.Keys() {
		raw, ok := nodesMap.Get(key)
		if !ok {
			continue
		}
		nodeStr, ok := raw.(string)
		if !ok {
			continue
		}
		var nd struct {
			Position any `json:"position"`
		}
		if json.Unmarshal([]byte(nodeStr), &nd) != nil {
			continue
		}
		var posStr string
		if nd.Position != nil {
			switch v := nd.Position.(type) {
			case string:
				posStr = v
			case float64:
				posStr = fmt.Sprintf("%g", v)
			default:
				posStr = fmt.Sprintf("%v", nd.Position)
			}
		}
		if posStr > maxPos {
			maxPos = posStr
		}
	}
	return maxPos
}


