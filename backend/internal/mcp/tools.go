package mcpapp

import (
	"context"
	"encoding/json"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/RigleyC/supanotes/internal/memories"
	"github.com/RigleyC/supanotes/internal/notes"
	"github.com/RigleyC/supanotes/internal/soul"
	"github.com/RigleyC/supanotes/internal/tags"
	"github.com/RigleyC/supanotes/internal/tasks"
	"github.com/RigleyC/supanotes/pkg/uid"
)

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
	memoriesSvc *memories.Service,
	tagsSvc *tags.Service,
	soulSvc *soul.Service,
) {
	emptySchema := map[string]any{"type": "object", "properties": map[string]any{}}

	// Notes
	server.AddTool(&mcp.Tool{Name: "list_notes", Description: "List notes", InputSchema: emptySchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			res, err := notesSvc.GetNotes(ctx, userID, nil, nil, 50, nil, nil)
			if err != nil {
				return asError(err)
			}
			return &mcp.CallToolResult{Content: asText(res)}, nil
		},
	)
	server.AddTool(&mcp.Tool{Name: "get_note", Description: "Get note", InputSchema: emptySchema},
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
	server.AddTool(&mcp.Tool{Name: "create_note", Description: "Create note", InputSchema: emptySchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			args := parseArgs(request)
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			content := getStr(args, "content")
			res, err := notesSvc.CreateNote(ctx, userID, content, nil, false)
			if err != nil {
				return asError(err)
			}
			return &mcp.CallToolResult{Content: asText(res)}, nil
		},
	)
	server.AddTool(&mcp.Tool{Name: "update_note", Description: "Update note", InputSchema: emptySchema},
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
			res, err := notesSvc.UpdateNote(ctx, userID, id, &content, nil, nil)
			if err != nil {
				return asError(err)
			}
			return &mcp.CallToolResult{Content: asText(res)}, nil
		},
	)
	server.AddTool(&mcp.Tool{Name: "delete_note", Description: "Delete note", InputSchema: emptySchema},
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
	server.AddTool(&mcp.Tool{Name: "list_tasks", Description: "List tasks", InputSchema: emptySchema},
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
	server.AddTool(&mcp.Tool{Name: "create_task", Description: "Create task", InputSchema: emptySchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			args := parseArgs(request)
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			title := getStr(args, "title")
			res, err := tasksSvc.CreateTask(ctx, userID, pgtype.UUID{}, title, nil, nil, 0)
			if err != nil {
				return asError(err)
			}
			return &mcp.CallToolResult{Content: asText(res)}, nil
		},
	)
	server.AddTool(&mcp.Tool{Name: "update_task", Description: "Update task", InputSchema: emptySchema},
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
	server.AddTool(&mcp.Tool{Name: "complete_task", Description: "Complete task", InputSchema: emptySchema},
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
	server.AddTool(&mcp.Tool{Name: "reopen_task", Description: "Reopen task", InputSchema: emptySchema},
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
	server.AddTool(&mcp.Tool{Name: "delete_task", Description: "Delete task", InputSchema: emptySchema},
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

	// Memories
	server.AddTool(&mcp.Tool{Name: "list_memories", Description: "List memories", InputSchema: emptySchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			res, err := memoriesSvc.GetMemories(ctx, userID, 50, 0)
			if err != nil {
				return asError(err)
			}
			return &mcp.CallToolResult{Content: asText(res)}, nil
		},
	)
	server.AddTool(&mcp.Tool{Name: "create_memory", Description: "Create memory", InputSchema: emptySchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			args := parseArgs(request)
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			content := getStr(args, "content")
			res, err := memoriesSvc.CreateMemory(ctx, userID, content)
			if err != nil {
				return asError(err)
			}
			return &mcp.CallToolResult{Content: asText(res)}, nil
		},
	)
	server.AddTool(&mcp.Tool{Name: "delete_memory", Description: "Delete memory", InputSchema: emptySchema},
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
			err = memoriesSvc.DeleteMemory(ctx, id, userID)
			if err != nil {
				return asError(err)
			}
			return &mcp.CallToolResult{Content: asText("deleted")}, nil
		},
	)

	// Tags
	server.AddTool(&mcp.Tool{Name: "list_tags", Description: "List tags", InputSchema: emptySchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			res, err := tagsSvc.List(ctx, userID)
			if err != nil {
				return asError(err)
			}
			return &mcp.CallToolResult{Content: asText(res)}, nil
		},
	)
	server.AddTool(&mcp.Tool{Name: "create_tag", Description: "Create tag", InputSchema: emptySchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			args := parseArgs(request)
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			name := getStr(args, "name")
			res, err := tagsSvc.Create(ctx, userID, name)
			if err != nil {
				return asError(err)
			}
			return &mcp.CallToolResult{Content: asText(res)}, nil
		},
	)
	server.AddTool(&mcp.Tool{Name: "add_tag_to_note", Description: "Add tag to note", InputSchema: emptySchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			args := parseArgs(request)
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			noteIDStr := getStr(args, "note_id")
			noteID, err := uid.UUIDFromString(noteIDStr)
			if err != nil {
				return asError(err)
			}
			tagIDStr := getStr(args, "tag_id")
			tagID, err := uid.UUIDFromString(tagIDStr)
			if err != nil {
				return asError(err)
			}
			err = tagsSvc.AddTagToNote(ctx, noteID, tagID, userID)
			if err != nil {
				return asError(err)
			}
			return &mcp.CallToolResult{Content: asText("added")}, nil
		},
	)
	server.AddTool(&mcp.Tool{Name: "remove_tag_from_note", Description: "Remove tag from note", InputSchema: emptySchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			args := parseArgs(request)
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			noteIDStr := getStr(args, "note_id")
			noteID, err := uid.UUIDFromString(noteIDStr)
			if err != nil {
				return asError(err)
			}
			tagIDStr := getStr(args, "tag_id")
			tagID, err := uid.UUIDFromString(tagIDStr)
			if err != nil {
				return asError(err)
			}
			err = tagsSvc.RemoveTagFromNote(ctx, noteID, tagID, userID)
			if err != nil {
				return asError(err)
			}
			return &mcp.CallToolResult{Content: asText("removed")}, nil
		},
	)

	// Soul
	server.AddTool(&mcp.Tool{Name: "get_soul", Description: "Get soul", InputSchema: emptySchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			res, err := soulSvc.Get(ctx, userID)
			if err != nil {
				return asError(err)
			}
			return &mcp.CallToolResult{Content: asText(res)}, nil
		},
	)
	server.AddTool(&mcp.Tool{Name: "update_soul", Description: "Update soul", InputSchema: emptySchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			args := parseArgs(request)
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			personality := getStr(args, "personality")
			res, err := soulSvc.Update(ctx, userID, personality)
			if err != nil {
				return asError(err)
			}
			return &mcp.CallToolResult{Content: asText(res)}, nil
		},
	)
}
