package mcpapp

import (
	"context"
	"fmt"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/RigleyC/supanotes/internal/noteoperations"
	"github.com/RigleyC/supanotes/internal/notes"
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
			args, err := decodeToolArgs[listNotesToolArgs](request)
			if err != nil {
				return asError(err)
			}
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			limit := int32(50)
			if args.Limit != nil {
				limit = *args.Limit
			}
			if limit < 1 || limit > 100 {
				return asError(fmt.Errorf("limit must be between 1 and 100"))
			}
			cursorTime, err := optionalToolTime(args.CursorUpdatedAt, "cursor_updated_at")
			if err != nil {
				return asError(err)
			}
			var cursorID *pgtype.UUID
			if strings.TrimSpace(args.CursorID) != "" {
				cursorValue, parseErr := toolUUID(args.CursorID, "cursor_id")
				if parseErr != nil {
					return asError(parseErr)
				}
				parsed, parseErr := uid.UUIDFromString(cursorValue)
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
			args, err := decodeToolArgs[idToolArgs](request)
			if err != nil {
				return asError(err)
			}
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			id, err := toolUUID(args.ID, "id")
			if err != nil {
				return asError(err)
			}
			noteID, err := uid.UUIDFromString(id)
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
			args, err := decodeToolArgs[noteRevisionToolArgs](request)
			if err != nil {
				return asError(err)
			}
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			noteIDValue, err := toolUUID(args.NoteID, "note_id")
			if err != nil {
				return asError(err)
			}
			noteID, err := uid.UUIDFromString(noteIDValue)
			if err != nil {
				return asError(err)
			}
			afterRevision := int64(0)
			if args.AfterRevision != nil {
				afterRevision = *args.AfterRevision
			}
			if afterRevision < 0 {
				return asError(fmt.Errorf("after_revision must be non-negative"))
			}
			operations, err := documentReader.GetOperationsSince(ctx, noteID, userID, afterRevision)
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
			args, err := decodeToolArgs[idToolArgs](request)
			if err != nil {
				return asError(err)
			}
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			idValue, err := toolUUID(args.ID, "id")
			if err != nil {
				return asError(err)
			}
			id, err := uid.UUIDFromString(idValue)
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
			args, err := decodeToolArgs[noteContentToolArgs](request)
			if err != nil {
				return asError(err)
			}
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			content := args.Content
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
	addTool(server, security, &mcp.Tool{Name: toolDeleteNote, Description: "Delete note", InputSchema: destructiveIDSchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			if err := requireWriteScope(ctx); err != nil {
				return asError(err)
			}
			args, err := decodeToolArgs[destructiveIDToolArgs](request)
			if err != nil {
				return asError(err)
			}
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			idValue, err := toolUUID(args.ID, "id")
			if err != nil {
				return asError(err)
			}
			id, err := uid.UUIDFromString(idValue)
			if err != nil {
				return asError(err)
			}
			confirmationLease, err := requireConfirmation(ctx, security, request, toolDeleteNote, "note:"+id.String())
			if err != nil {
				return asError(err)
			}
			if replay, ok, replayErr := replayConfirmation(confirmationLease); replayErr != nil {
				return asError(replayErr)
			} else if ok {
				return replay, nil
			}
			result, err := finishConfirmationMutation(ctx, confirmationLease, func(ctx context.Context, tx pgx.Tx) (any, error) {
				if err := notesSvc.DeleteNoteInTransaction(ctx, tx, userID, id); err != nil {
					return nil, err
				}
				return "deleted", nil
			})
			if err != nil {
				return asError(err)
			}
			return asTextResult(result)
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
