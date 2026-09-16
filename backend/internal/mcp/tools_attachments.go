package mcpapp

import (
	"bytes"
	"context"
	"encoding/base64"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/RigleyC/supanotes/internal/attachments"
	"github.com/RigleyC/supanotes/internal/noteoperations"
	"github.com/RigleyC/supanotes/pkg/uid"
)

func addAttachmentTools(server *mcp.Server, security SecurityStore, service attachments.Service, reader noteoperations.DocumentReader) {
	addTool(server, security, &mcp.Tool{Name: toolUploadAttachment, Description: "Upload an attachment to a note", InputSchema: attachmentUploadSchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			if err := requireWriteScope(ctx); err != nil {
				return asError(err)
			}
			if service == nil {
				return asError(fmt.Errorf("attachment service is not configured"))
			}
			args, err := decodeToolArgs[attachmentUploadToolArgs](request)
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
			filename, err := requiredToolString(args.Filename, "filename")
			if err != nil {
				return asError(err)
			}
			encoded, err := requiredToolString(args.ContentBase64, "content_base64")
			if err != nil {
				return asError(err)
			}
			content, err := base64.StdEncoding.DecodeString(encoded)
			if err != nil {
				return asError(fmt.Errorf("content_base64 is invalid: %w", err))
			}
			attachment, err := service.Upload(ctx, noteID, userID, filename, bytes.NewReader(content), int64(len(content)))
			if err != nil {
				return asError(err)
			}
			return asTextResult(attachment)
		},
	)
	addTool(server, security, &mcp.Tool{Name: toolListNoteAttachments, Description: "List attachments for a note", InputSchema: idParamSchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			if err := requireReadScope(ctx); err != nil {
				return asError(err)
			}
			if service == nil {
				return asError(fmt.Errorf("attachment service is not configured"))
			}
			args, err := decodeToolArgs[idToolArgs](request)
			if err != nil {
				return asError(err)
			}
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			noteIDValue, err := toolUUID(args.ID, "id")
			if err != nil {
				return asError(err)
			}
			noteID, err := uid.UUIDFromString(noteIDValue)
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
			return asTextResult(items)
		},
	)
	addTool(server, security, &mcp.Tool{Name: toolDeleteAttachment, Description: "Delete an attachment from a note", InputSchema: attachmentDeleteSchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			if err := requireWriteScope(ctx); err != nil {
				return asError(err)
			}
			if service == nil {
				return asError(fmt.Errorf("attachment service is not configured"))
			}
			args, err := decodeToolArgs[attachmentDeleteToolArgs](request)
			if err != nil {
				return asError(err)
			}
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			attachmentIDValue, err := toolUUID(args.AttachmentID, "attachment_id")
			if err != nil {
				return asError(err)
			}
			attachmentID, err := uid.UUIDFromString(attachmentIDValue)
			if err != nil {
				return asError(err)
			}
			confirmationLease, err := requireConfirmation(ctx, security, request, toolDeleteAttachment, "attachment:"+attachmentID.String())
			if err != nil {
				return asError(err)
			}
			if replay, ok, replayErr := replayConfirmation(confirmationLease); replayErr != nil {
				return asError(replayErr)
			} else if ok {
				return replay, nil
			}
			transactionalService, ok := service.(interface {
				DeleteInTransaction(context.Context, pgx.Tx, pgtype.UUID, pgtype.UUID) error
			})
			if !ok {
				return asError(fmt.Errorf("attachment service does not support confirmed deletion"))
			}
			result, err := finishConfirmationMutation(ctx, confirmationLease, func(ctx context.Context, tx pgx.Tx) (any, error) {
				if err := transactionalService.DeleteInTransaction(ctx, tx, userID, attachmentID); err != nil {
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
