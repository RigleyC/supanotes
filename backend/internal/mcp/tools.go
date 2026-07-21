package mcpapp

import (
	"context"
	"encoding/json"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/RigleyC/supanotes/internal/notes"
	"github.com/RigleyC/supanotes/internal/tasks"
	"github.com/RigleyC/supanotes/pkg/uid"
)

var noParamSchema = map[string]any{"type": "object", "properties": map[string]any{}}

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

func RegisterTools(
	server *mcp.Server,
	notesSvc *notes.Service,
	tasksSvc *tasks.Service,
) {
	// Notes
	server.AddTool(&mcp.Tool{Name: "list_notes", Description: "List notes", InputSchema: noParamSchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			res, err := notesSvc.GetNotes(ctx, userID, nil, 50, nil, nil)
			if err != nil {
				return asError(err)
			}
			return &mcp.CallToolResult{Content: asText(res)}, nil
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
