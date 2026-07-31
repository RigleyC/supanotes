package mcpapp

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"time"

	"github.com/RigleyC/supanotes/internal/attachments"
	"github.com/RigleyC/supanotes/internal/dto"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/RigleyC/supanotes/internal/noteoperations"
	"github.com/RigleyC/supanotes/internal/notes"
	"github.com/RigleyC/supanotes/internal/settings"
	"github.com/RigleyC/supanotes/internal/shares"
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

var taskOccurrenceSchema = map[string]any{
	"type": "object",
	"properties": map[string]any{
		"note_id":       map[string]any{"type": "string"},
		"block_id":      map[string]any{"type": "string"},
		"base_revision": map[string]any{"type": "integer", "minimum": 0},
		"scheduled_at":  map[string]any{"type": "string", "description": "Scheduled occurrence timestamp"},
		"completed_at":  map[string]any{"type": "string", "description": "Completion timestamp; omit to reopen"},
		"operation_id":  map[string]any{"type": "string"},
	},
	"required": []any{"note_id", "block_id", "base_revision", "scheduled_at"},
}

var attachmentSchema = map[string]any{
	"type": "object",
	"properties": map[string]any{
		"note_id":        map[string]any{"type": "string"},
		"attachment_id":  map[string]any{"type": "string"},
		"filename":       map[string]any{"type": "string"},
		"content_base64": map[string]any{"type": "string", "description": "Base64 file content"},
	},
	"required": []any{"note_id"},
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

func addTaskOccurrenceTool(server *mcp.Server, name string, commands noteoperations.DocumentCommandService, reopen bool) {
	server.AddTool(&mcp.Tool{Name: name, Description: "Complete or reopen a task occurrence in the canonical document", InputSchema: taskOccurrenceSchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			if commands == nil {
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
			blockID := getStr(args, "block_id")
			if blockID == "" {
				return asError(fmt.Errorf("block_id is required"))
			}
			baseRevision := int64(getInt(args, "base_revision", -1))
			if baseRevision < 0 {
				return asError(fmt.Errorf("base_revision is required"))
			}
			scheduledAt := getStr(args, "scheduled_at")
			if scheduledAt == "" {
				return asError(fmt.Errorf("scheduled_at is required"))
			}
			operationID := getStr(args, "operation_id")
			if operationID == "" {
				operationID = uuid.NewString()
			}
			if _, err := uuid.Parse(operationID); err != nil {
				return asError(fmt.Errorf("operation_id must be a UUID: %w", err))
			}
			var completedAt *string
			if !reopen {
				value := getStr(args, "completed_at")
				if value == "" {
					value = time.Now().UTC().Format(time.RFC3339)
				}
				completedAt = &value
			}
			payload, err := json.Marshal(noteoperations.CompleteTaskOccurrencePayload{
				TaskID: blockID, ScheduledAt: scheduledAt, CompletedAt: completedAt,
			})
			if err != nil {
				return asError(err)
			}
			result, err := commands.SyncOperations(ctx, noteID, userID, noteoperations.SyncRequest{
				KnownRevision: baseRevision, ClientID: "mcp",
				Operations: []noteoperations.OperationRequest{{
					OperationID: operationID, BaseRevision: baseRevision,
					Kind: string(noteoperations.KindCompleteTaskOccurrence), BlockID: &blockID, Payload: payload,
				}},
			})
			if err != nil {
				return asError(err)
			}
			return &mcp.CallToolResult{Content: asText(result)}, nil
		},
	)
}

func addAttachmentTools(server *mcp.Server, service attachments.Service, reader noteoperations.DocumentReader) {
	server.AddTool(&mcp.Tool{Name: "upload_attachment", Description: "Upload an attachment to a note", InputSchema: attachmentSchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			if service == nil {
				return asError(fmt.Errorf("attachment service is not configured"))
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
			filename := getStr(args, "filename")
			encoded := getStr(args, "content_base64")
			if filename == "" || encoded == "" {
				return asError(fmt.Errorf("filename and content_base64 are required"))
			}
			content, err := base64.StdEncoding.DecodeString(encoded)
			if err != nil {
				return asError(fmt.Errorf("content_base64 is invalid: %w", err))
			}
			attachment, err := service.Upload(ctx, noteID, userID, filename, bytes.NewReader(content), int64(len(content)))
			if err != nil {
				return asError(err)
			}
			return &mcp.CallToolResult{Content: asText(attachment)}, nil
		},
	)
	server.AddTool(&mcp.Tool{Name: "list_note_attachments", Description: "List attachments for a note", InputSchema: idParamSchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			if service == nil {
				return asError(fmt.Errorf("attachment service is not configured"))
			}
			args := parseArgs(request)
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			noteID, err := getUUID(args, "id")
			if err != nil {
				return asError(err)
			}
			if reader == nil {
				return asError(fmt.Errorf("document reader is not configured"))
			}
			if _, err := reader.GetDocument(ctx, noteID, userID); err != nil {
				return asError(err)
			}
			items, err := service.ListByNote(ctx, noteID)
			if err != nil {
				return asError(err)
			}
			return &mcp.CallToolResult{Content: asText(items)}, nil
		},
	)
	server.AddTool(&mcp.Tool{Name: "delete_attachment", Description: "Delete an attachment from a note", InputSchema: attachmentSchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			if service == nil {
				return asError(fmt.Errorf("attachment service is not configured"))
			}
			args := parseArgs(request)
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			attachmentID, err := getUUID(args, "attachment_id")
			if err != nil {
				return asError(err)
			}
			if err := service.Delete(ctx, userID, attachmentID); err != nil {
				return asError(err)
			}
			return &mcp.CallToolResult{Content: asText("deleted")}, nil
		},
	)
}

func addSharingAndSettingsTools(server *mcp.Server, sharesSvc *shares.Service, settingsSvc *settings.Service) {
	server.AddTool(&mcp.Tool{Name: "list_note_shares", Description: "List shares for a note", InputSchema: idParamSchema}, func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		if sharesSvc == nil {
			return asError(fmt.Errorf("shares service is not configured"))
		}
		args := parseArgs(request)
		userID, err := UserIDFromContext(ctx)
		if err != nil {
			return asError(err)
		}
		noteID, err := getUUID(args, "id")
		if err != nil {
			return asError(err)
		}
		result, err := sharesSvc.ListNoteShares(ctx, userID, noteID)
		if err != nil {
			return asError(err)
		}
		return &mcp.CallToolResult{Content: asText(result)}, nil
	})
	shareSchema := map[string]any{"type": "object", "properties": map[string]any{"note_id": map[string]any{"type": "string"}, "email": map[string]any{"type": "string"}, "permission": map[string]any{"type": "string", "enum": []any{"view", "edit"}}}, "required": []any{"note_id", "email", "permission"}}
	server.AddTool(&mcp.Tool{Name: "share_note", Description: "Share a note with a user", InputSchema: shareSchema}, func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		if sharesSvc == nil {
			return asError(fmt.Errorf("shares service is not configured"))
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
		result, err := sharesSvc.ShareNote(ctx, userID, noteID, getStr(args, "email"), getStr(args, "permission"))
		if err != nil {
			return asError(err)
		}
		return &mcp.CallToolResult{Content: asText(result)}, nil
	})
	removeSchema := map[string]any{"type": "object", "properties": map[string]any{"note_id": map[string]any{"type": "string"}, "user_id": map[string]any{"type": "string"}}, "required": []any{"note_id", "user_id"}}
	server.AddTool(&mcp.Tool{Name: "remove_note_share", Description: "Remove a note share", InputSchema: removeSchema}, func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		if sharesSvc == nil {
			return asError(fmt.Errorf("shares service is not configured"))
		}
		args := parseArgs(request)
		ownerID, err := UserIDFromContext(ctx)
		if err != nil {
			return asError(err)
		}
		noteID, err := getUUID(args, "note_id")
		if err != nil {
			return asError(err)
		}
		targetID, err := getUUID(args, "user_id")
		if err != nil {
			return asError(err)
		}
		if err := sharesSvc.DeleteNoteShare(ctx, ownerID, noteID, targetID); err != nil {
			return asError(err)
		}
		return &mcp.CallToolResult{Content: asText("deleted")}, nil
	})
	server.AddTool(&mcp.Tool{Name: "get_user_settings", Description: "Get current user settings", InputSchema: noParamSchema}, func(ctx context.Context, _ *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		if settingsSvc == nil {
			return asError(fmt.Errorf("settings service is not configured"))
		}
		userID, err := UserIDFromContext(ctx)
		if err != nil {
			return asError(err)
		}
		result, err := settingsSvc.Get(ctx, userID)
		if err != nil {
			return asError(err)
		}
		return &mcp.CallToolResult{Content: asText(result)}, nil
	})
	settingsSchema := map[string]any{"type": "object", "properties": map[string]any{"timezone": map[string]any{"type": "string"}, "preferences": map[string]any{"type": "object"}}}
	server.AddTool(&mcp.Tool{Name: "update_user_settings", Description: "Update supported user settings", InputSchema: settingsSchema}, func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		if settingsSvc == nil {
			return asError(fmt.Errorf("settings service is not configured"))
		}
		args := parseArgs(request)
		userID, err := UserIDFromContext(ctx)
		if err != nil {
			return asError(err)
		}
		prefs := map[string]any{}
		if value, ok := args["preferences"].(map[string]any); ok {
			prefs = value
		}
		result, err := settingsSvc.Update(ctx, userID, dto.UpdateSettingsRequest{Timezone: getStr(args, "timezone"), Preferences: prefs})
		if err != nil {
			return asError(err)
		}
		return &mcp.CallToolResult{Content: asText(result)}, nil
	})
}

func RegisterTools(
	server *mcp.Server,
	notesSvc *notes.Service,
	tasksSvc *tasks.Service,
	documentReader noteoperations.DocumentReader,
	documentCommands noteoperations.DocumentCommandService,
	attachmentsSvc attachments.Service,
	sharesSvc *shares.Service,
	settingsSvc *settings.Service,
) {
	addAttachmentTools(server, attachmentsSvc, documentReader)
	addSharingAndSettingsTools(server, sharesSvc, settingsSvc)
	addBlockMutationTool(server, "create_block", noteoperations.KindCreateBlock, documentCommands)
	addBlockMutationTool(server, "create_task_block", noteoperations.KindCreateBlock, documentCommands)
	addBlockMutationTool(server, "update_block_text", noteoperations.KindTextDelta, documentCommands)
	addBlockMutationTool(server, "move_block", noteoperations.KindMoveBlock, documentCommands)
	addBlockMutationTool(server, "delete_block", noteoperations.KindDeleteBlock, documentCommands)
	addBlockMutationTool(server, "set_block_type", noteoperations.KindSetBlockType, documentCommands)
	addBlockMutationTool(server, "set_block_metadata", noteoperations.KindSetBlockMetadata, documentCommands)
	addBlockMutationTool(server, "update_task_metadata", noteoperations.KindSetBlockMetadata, documentCommands)
	addTaskOccurrenceTool(server, "complete_task_occurrence", documentCommands, false)
	addTaskOccurrenceTool(server, "reopen_task_occurrence", documentCommands, true)

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
}
