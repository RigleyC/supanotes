package mcpapp

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/RigleyC/supanotes/internal/noteoperations"
	"github.com/RigleyC/supanotes/internal/notes"
	"github.com/RigleyC/supanotes/internal/tasks"
	"github.com/RigleyC/supanotes/pkg/uid"
)

var noParamSchema = map[string]any{"type": "object", "properties": map[string]any{}}

var listNotesSchema = map[string]any{
	"type": "object",
	"properties": map[string]any{
		"limit":             map[string]any{"type": "integer", "description": "Maximum number of notes to return (1-100)"},
		"cursor_updated_at": map[string]any{"type": "string", "description": "RFC3339 cursor timestamp"},
		"cursor_id":         map[string]any{"type": "string", "description": "Cursor note ID, required with cursor_updated_at"},
	},
}

var noteRevisionSchema = map[string]any{
	"type": "object",
	"properties": map[string]any{
		"note_id":        map[string]any{"type": "string", "description": "Note ID"},
		"after_revision": map[string]any{"type": "integer", "minimum": 0, "description": "Return operations after this revision"},
	},
	"required": []any{"note_id"},
}

var blockMutationSchema = map[string]any{
	"type": "object",
	"properties": map[string]any{
		"note_id":       map[string]any{"type": "string", "description": "Note ID"},
		"block_id":      map[string]any{"type": "string", "description": "Block ID"},
		"base_revision": map[string]any{"type": "integer", "minimum": 0, "description": "Document revision used as the operation base"},
		"payload":       map[string]any{"type": "object", "description": "Operation-specific payload"},
		"operation_id":  map[string]any{"type": "string", "description": "Optional UUID used for idempotent retries"},
		"client_id":     map[string]any{"type": "string", "description": "Optional caller identifier"},
	},
	"required": []any{"note_id", "base_revision"},
}

var idParamSchema = map[string]any{
	"type": "object",
	"properties": map[string]any{
		"id": map[string]any{
			"type":        "string",
			"description": "ID",
		},
	},
	"required": []any{"id"},
}

var noteContentSchema = map[string]any{
	"type": "object",
	"properties": map[string]any{
		"content": map[string]any{
			"type":        "string",
			"description": "Note content",
		},
	},
	"required": []any{"content"},
}

var updateNoteSchema = map[string]any{
	"type": "object",
	"properties": map[string]any{
		"id": map[string]any{
			"type":        "string",
			"description": "Note ID",
		},
		"content": map[string]any{
			"type":        "string",
			"description": "Note content",
		},
	},
	"required": []any{"id", "content"},
}

var taskTitleSchema = map[string]any{
	"type": "object",
	"properties": map[string]any{
		"title": map[string]any{
			"type":        "string",
			"description": "Task title",
		},
	},
	"required": []any{"title"},
}

var updateTaskSchema = map[string]any{
	"type": "object",
	"properties": map[string]any{
		"id": map[string]any{
			"type":        "string",
			"description": "Task ID",
		},
		"title": map[string]any{
			"type":        "string",
			"description": "Task title",
		},
	},
	"required": []any{"id", "title"},
}

func asText(v any) []mcp.Content {
	b, _ := json.Marshal(v)
	return []mcp.Content{&mcp.TextContent{Text: string(b)}}
}

func asError(err error) (*mcp.CallToolResult, error) {
	return &mcp.CallToolResult{
		IsError: true,
		Content: []mcp.Content{&mcp.TextContent{Text: err.Error()}},
	}, nil
}

func parseArgs(req *mcp.CallToolRequest) map[string]any {
	var m map[string]any
	json.Unmarshal(req.Params.Arguments, &m)
	return m
}

func getStr(args map[string]any, key string) string {
	if v, ok := args[key].(string); ok {
		return v
	}
	return ""
}

func getInt(args map[string]any, key string, fallback int32) int32 {
	if value, ok := args[key].(float64); ok {
		return int32(value)
	}
	return fallback
}

func getUUID(args map[string]any, key string) (pgtype.UUID, error) {
	id := getStr(args, key)
	if id == "" {
		return pgtype.UUID{}, fmt.Errorf("%s is required", key)
	}
	return uid.UUIDFromString(id)
}

func getOptionalTime(args map[string]any, key string) (*time.Time, error) {
	value := getStr(args, key)
	if value == "" {
		return nil, nil
	}
	parsed, err := time.Parse(time.RFC3339, value)
	if err != nil {
		return nil, fmt.Errorf("%s must be RFC3339: %w", key, err)
	}
	return &parsed, nil
}

func operationPayload(args map[string]any) (json.RawMessage, error) {
	payload, ok := args["payload"]
	if !ok {
		return json.RawMessage(`{}`), nil
	}
	encoded, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("invalid payload: %w", err)
	}
	return encoded, nil
}

func addBlockMutationTool(
	server *mcp.Server,
	name string,
	kind noteoperations.Kind,
	documentCommands noteoperations.DocumentCommandService,
) {
	server.AddTool(&mcp.Tool{Name: name, Description: "Apply a REST/OT block operation", InputSchema: blockMutationSchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			if documentCommands == nil {
				return asError(fmt.Errorf("document command service is not configured"))
			}
			args := parseArgs(request)
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			noteID, err := getUUID(args, "note_id")
			if err != nil {
				return asError(err)
			}
			baseRevision := int64(getInt(args, "base_revision", -1))
			if baseRevision < 0 {
				return asError(fmt.Errorf("base_revision is required"))
			}
			operationID := getStr(args, "operation_id")
			if operationID == "" {
				operationID = uuid.NewString()
			}
			if _, err := uuid.Parse(operationID); err != nil {
				return asError(fmt.Errorf("operation_id must be a UUID: %w", err))
			}
			payload, err := operationPayload(args)
			if err != nil {
				return asError(err)
			}
			blockID := getStr(args, "block_id")
			var blockIDPtr *string
			if blockID != "" {
				blockIDPtr = &blockID
			}
			clientID := getStr(args, "client_id")
			if clientID == "" {
				clientID = "mcp"
			}
			result, err := documentCommands.SyncOperations(ctx, noteID, userID, noteoperations.SyncRequest{
				KnownRevision: baseRevision,
				ClientID:      clientID,
				Operations: []noteoperations.OperationRequest{{
					OperationID: operationID, BaseRevision: baseRevision,
					Kind: string(kind), BlockID: blockIDPtr, Payload: payload,
				}},
			})
			if err != nil {
				return asError(err)
			}
			return &mcp.CallToolResult{Content: asText(result)}, nil
		},
	)
}

func RegisterTools(
	server *mcp.Server,
	notesSvc *notes.Service,
	tasksSvc *tasks.Service,
	documentReader noteoperations.DocumentReader,
	documentCommands noteoperations.DocumentCommandService,
) {
	addBlockMutationTool(server, "create_block", noteoperations.KindCreateBlock, documentCommands)
	addBlockMutationTool(server, "update_block_text", noteoperations.KindTextDelta, documentCommands)
	addBlockMutationTool(server, "move_block", noteoperations.KindMoveBlock, documentCommands)
	addBlockMutationTool(server, "delete_block", noteoperations.KindDeleteBlock, documentCommands)
	addBlockMutationTool(server, "set_block_type", noteoperations.KindSetBlockType, documentCommands)
	addBlockMutationTool(server, "set_block_metadata", noteoperations.KindSetBlockMetadata, documentCommands)

	// Notes
	server.AddTool(&mcp.Tool{Name: "list_notes", Description: "List notes", InputSchema: listNotesSchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			args := parseArgs(request)
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			limit := getInt(args, "limit", 50)
			if limit < 1 || limit > 100 {
				return asError(fmt.Errorf("limit must be between 1 and 100"))
			}
			cursorTime, err := getOptionalTime(args, "cursor_updated_at")
			if err != nil {
				return asError(err)
			}
			var cursorID *pgtype.UUID
			if getStr(args, "cursor_id") != "" {
				parsed, parseErr := getUUID(args, "cursor_id")
				if parseErr != nil {
					return asError(parseErr)
				}
				cursorID = &parsed
			}
			if (cursorTime == nil) != (cursorID == nil) {
				return asError(fmt.Errorf("cursor_updated_at and cursor_id must be provided together"))
			}
			res, err := notesSvc.GetNotes(ctx, userID, nil, limit, cursorTime, cursorID)
			if err != nil {
				return asError(err)
			}
			return &mcp.CallToolResult{Content: asText(res)}, nil
		},
	)
	server.AddTool(&mcp.Tool{Name: "get_note_document", Description: "Get the canonical REST/OT document for a note", InputSchema: idParamSchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			args := parseArgs(request)
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			noteID, err := getUUID(args, "id")
			if err != nil {
				return asError(err)
			}
			res, err := documentReader.GetDocument(ctx, noteID, userID)
			if err != nil {
				return asError(err)
			}
			return &mcp.CallToolResult{Content: asText(res)}, nil
		},
	)
	server.AddTool(&mcp.Tool{Name: "list_note_operations", Description: "List REST/OT operations for a note", InputSchema: noteRevisionSchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			args := parseArgs(request)
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			noteID, err := getUUID(args, "note_id")
			if err != nil {
				return asError(err)
			}
			operations, err := documentReader.GetOperationsSince(ctx, noteID, userID, int64(getInt(args, "after_revision", 0)))
			if err != nil {
				return asError(err)
			}
			return &mcp.CallToolResult{Content: asText(operations)}, nil
		},
	)
	server.AddTool(&mcp.Tool{Name: "get_note", Description: "Get note", InputSchema: idParamSchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			args := parseArgs(request)
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			idStr := getStr(args, "id")
			id, err := uid.UUIDFromString(idStr)
			if err != nil {
				return asError(err)
			}
			res, err := notesSvc.GetNoteByID(ctx, id, userID)
			if err != nil {
				return asError(err)
			}
			return &mcp.CallToolResult{Content: asText(res)}, nil
		},
	)
	server.AddTool(&mcp.Tool{Name: "create_note", Description: "Create note", InputSchema: noteContentSchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			args := parseArgs(request)
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			content := getStr(args, "content")
			res, err := notesSvc.CreateNote(ctx, userID, content, false)
			if err != nil {
				return asError(err)
			}
			return &mcp.CallToolResult{Content: asText(res)}, nil
		},
	)
	server.AddTool(&mcp.Tool{Name: "update_note", Description: "Update note", InputSchema: updateNoteSchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			args := parseArgs(request)
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			idStr := getStr(args, "id")
			id, err := uid.UUIDFromString(idStr)
			if err != nil {
				return asError(err)
			}
			content := getStr(args, "content")
			res, err := notesSvc.UpdateNote(ctx, userID, id, &content, nil)
			if err != nil {
				return asError(err)
			}
			return &mcp.CallToolResult{Content: asText(res)}, nil
		},
	)
	server.AddTool(&mcp.Tool{Name: "delete_note", Description: "Delete note", InputSchema: idParamSchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			args := parseArgs(request)
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			idStr := getStr(args, "id")
			id, err := uid.UUIDFromString(idStr)
			if err != nil {
				return asError(err)
			}
			err = notesSvc.DeleteNote(ctx, userID, id)
			if err != nil {
				return asError(err)
			}
			return &mcp.CallToolResult{Content: asText("deleted")}, nil
		},
	)

	// Tasks
	server.AddTool(&mcp.Tool{Name: "list_tasks", Description: "List tasks", InputSchema: noParamSchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			res, err := tasksSvc.GetTasks(ctx, userID, nil, nil, nil, nil, 50, 0)
			if err != nil {
				return asError(err)
			}
			return &mcp.CallToolResult{Content: asText(res)}, nil
		},
	)
	server.AddTool(&mcp.Tool{Name: "create_task", Description: "Create task", InputSchema: taskTitleSchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			args := parseArgs(request)
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			title := getStr(args, "title")
			res, err := tasksSvc.CreateTask(
				ctx,
				userID,
				pgtype.UUID{},
				title,
				nil,
				nil,
				"0",
				nil,
				nil,
			)
			if err != nil {
				return asError(err)
			}
			return &mcp.CallToolResult{Content: asText(res)}, nil
		},
	)
	server.AddTool(&mcp.Tool{Name: "update_task", Description: "Update task", InputSchema: updateTaskSchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			args := parseArgs(request)
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			idStr := getStr(args, "id")
			id, err := uid.UUIDFromString(idStr)
			if err != nil {
				return asError(err)
			}
			title := getStr(args, "title")
			opts := tasks.UpdateTaskOpts{Title: &title}
			res, err := tasksSvc.UpdateTask(ctx, userID, id, opts)
			if err != nil {
				return asError(err)
			}
			return &mcp.CallToolResult{Content: asText(res)}, nil
		},
	)
	server.AddTool(&mcp.Tool{Name: "complete_task", Description: "Complete task", InputSchema: idParamSchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			args := parseArgs(request)
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			idStr := getStr(args, "id")
			id, err := uid.UUIDFromString(idStr)
			if err != nil {
				return asError(err)
			}
			res, err := tasksSvc.CompleteTask(ctx, userID, id)
			if err != nil {
				return asError(err)
			}
			return &mcp.CallToolResult{Content: asText(res)}, nil
		},
	)
	server.AddTool(&mcp.Tool{Name: "reopen_task", Description: "Reopen task", InputSchema: idParamSchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			args := parseArgs(request)
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			idStr := getStr(args, "id")
			id, err := uid.UUIDFromString(idStr)
			if err != nil {
				return asError(err)
			}
			res, err := tasksSvc.ReopenTask(ctx, userID, id)
			if err != nil {
				return asError(err)
			}
			return &mcp.CallToolResult{Content: asText(res)}, nil
		},
	)
	server.AddTool(&mcp.Tool{Name: "delete_task", Description: "Delete task", InputSchema: idParamSchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			args := parseArgs(request)
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			idStr := getStr(args, "id")
			id, err := uid.UUIDFromString(idStr)
			if err != nil {
				return asError(err)
			}
			err = tasksSvc.DeleteTask(ctx, userID, id)
			if err != nil {
				return asError(err)
			}
			return &mcp.CallToolResult{Content: asText("deleted")}, nil
		},
	)
}
