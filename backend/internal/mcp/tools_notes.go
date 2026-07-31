package mcpapp

import (
	"context"
	"fmt"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/RigleyC/supanotes/internal/noteoperations"
	"github.com/RigleyC/supanotes/internal/notes"
	"github.com/RigleyC/supanotes/internal/tasks"
	"github.com/RigleyC/supanotes/pkg/uid"
)

func addNoteTools(
	server *mcp.Server,
	security SecurityStore,
	notesSvc *notes.Service,
	documentReader noteoperations.DocumentReader,
	documentCommands noteoperations.DocumentCommandService,
) {
	addTool(server, security, &mcp.Tool{Name: toolListNotes, Description: "List notes", InputSchema: listNotesSchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			if err := requireReadScope(ctx); err != nil {
				return asError(err)
			}
			args, err := parseArgs(request)
			if err != nil {
				return asError(err)
			}
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
			return asTextResult(res)
		},
	)
	addTool(server, security, &mcp.Tool{Name: toolGetNoteDocument, Description: "Get the canonical REST/OT document for a note", InputSchema: idParamSchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			if err := requireReadScope(ctx); err != nil {
				return asError(err)
			}
			args, err := parseArgs(request)
			if err != nil {
				return asError(err)
			}
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
			return asTextResult(res)
		},
	)
	addTool(server, security, &mcp.Tool{Name: toolListNoteOperations, Description: "List REST/OT operations for a note", InputSchema: noteRevisionSchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			if err := requireReadScope(ctx); err != nil {
				return asError(err)
			}
			args, err := parseArgs(request)
			if err != nil {
				return asError(err)
			}
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
			return asTextResult(operations)
		},
	)
	addTool(server, security, &mcp.Tool{Name: toolGetNote, Description: "Get note", InputSchema: idParamSchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			if err := requireReadScope(ctx); err != nil {
				return asError(err)
			}
			args, err := parseArgs(request)
			if err != nil {
				return asError(err)
			}
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			id, err := uid.UUIDFromString(getStr(args, "id"))
			if err != nil {
				return asError(err)
			}
			res, err := notesSvc.GetNoteByID(ctx, id, userID)
			if err != nil {
				return asError(err)
			}
			return asTextResult(res)
		},
	)
	addTool(server, security, &mcp.Tool{Name: toolCreateNote, Description: "Create note", InputSchema: noteContentSchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			if err := requireWriteScope(ctx); err != nil {
				return asError(err)
			}
			args, err := parseArgs(request)
			if err != nil {
				return asError(err)
			}
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			content := getStr(args, "content")
			if strings.TrimSpace(content) == "" {
				return asError(notes.ErrEmptyNote)
			}
			noteID := pgtype.UUID{Bytes: uuid.New(), Valid: true}
			res, err := syncNoteContent(ctx, documentCommands, noteID, userID, 0, noteoperations.NewEmptyDocument(), content)
			if err != nil {
				return asError(err)
			}
			return asTextResult(noteContentMutationResult{NoteID: uid.UUIDToString(noteID), Sync: res})
		},
	)
	addTool(server, security, &mcp.Tool{Name: toolUpdateNote, Description: "Update note", InputSchema: updateNoteSchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			if err := requireWriteScope(ctx); err != nil {
				return asError(err)
			}
			args, err := parseArgs(request)
			if err != nil {
				return asError(err)
			}
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			id, err := uid.UUIDFromString(getStr(args, "id"))
			if err != nil {
				return asError(err)
			}
			content := getStr(args, "content")
			documentResponse, err := documentReader.GetDocument(ctx, id, userID)
			if err != nil {
				return asError(err)
			}
			doc, err := noteoperations.UnmarshalDocument(documentResponse.Document)
			if err != nil {
				return asError(fmt.Errorf("decode canonical note document: %w", err))
			}
			res, err := syncNoteContent(ctx, documentCommands, id, userID, documentResponse.Revision, doc, content)
			if err != nil {
				return asError(err)
			}
			return asTextResult(noteContentMutationResult{NoteID: uid.UUIDToString(id), Sync: res})
		},
	)
	addTool(server, security, &mcp.Tool{Name: toolDeleteNote, Description: "Delete note", InputSchema: destructiveIDSchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			if err := requireWriteScope(ctx); err != nil {
				return asError(err)
			}
			args, err := parseArgs(request)
			if err != nil {
				return asError(err)
			}
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			id, err := uid.UUIDFromString(getStr(args, "id"))
			if err != nil {
				return asError(err)
			}
			confirmationLease, err := requireConfirmation(ctx, security, request, toolDeleteNote, "note:"+id.String())
			if err != nil {
				return asError(err)
			}
			if err := notesSvc.DeleteNote(ctx, userID, id); err != nil {
				return asError(finishConfirmation(ctx, confirmationLease, err))
			}
			confirmationErr := finishConfirmation(ctx, confirmationLease, nil)
			return asTextResultWithWarning("deleted", confirmationErr)
		},
	)
}

type noteContentMutationResult struct {
	NoteID string                      `json:"noteId"`
	Sync   noteoperations.SyncResponse `json:"sync"`
}

func syncNoteContent(
	ctx context.Context,
	commands noteoperations.DocumentCommandService,
	noteID pgtype.UUID,
	userID pgtype.UUID,
	knownRevision int64,
	doc noteoperations.Document,
	content string,
) (noteoperations.SyncResponse, error) {
	operations, err := noteoperations.BuildReplaceContentOperations(doc, content, knownRevision)
	if err != nil {
		return noteoperations.SyncResponse{}, fmt.Errorf("build canonical note content operations: %w", err)
	}

	return commands.SyncOperations(ctx, noteID, userID, noteoperations.SyncRequest{
		KnownRevision: knownRevision,
		Operations:    operations,
		ClientID:      "mcp",
	})
}

func addTaskTools(server *mcp.Server, security SecurityStore, tasksSvc *tasks.Service) {
	addTool(server, security, &mcp.Tool{Name: toolListTasks, Description: "List tasks", InputSchema: noParamSchema},
		func(ctx context.Context, _ *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			if err := requireReadScope(ctx); err != nil {
				return asError(err)
			}
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			res, err := tasksSvc.GetTasks(ctx, userID, nil, nil, nil, nil, 50, 0)
			if err != nil {
				return asError(err)
			}
			return asTextResult(res)
		},
	)
}
