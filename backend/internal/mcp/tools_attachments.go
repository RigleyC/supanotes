package mcpapp

import (
	"bytes"
	"context"
	"encoding/base64"
	"fmt"

	"github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/RigleyC/supanotes/internal/attachments"
	"github.com/RigleyC/supanotes/internal/noteoperations"
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
			args, err := parseArgs(request)
			if err != nil {
				return asError(err)
			}
			userID, err := UserIDFromContext(ctx)
			if err != nil {
				return asError(err)
			}
			attachmentID, err := getUUID(args, "attachment_id")
			if err != nil {
				return asError(err)
			}
			confirmationLease, err := requireConfirmation(ctx, security, request, toolDeleteAttachment, "attachment:"+attachmentID.String())
			if err != nil {
				return asError(err)
			}
			if err := service.Delete(ctx, userID, attachmentID); err != nil {
				return asError(finishConfirmation(ctx, confirmationLease, err))
			}
			confirmationErr := finishConfirmation(ctx, confirmationLease, nil)
			return asTextResultWithWarning("deleted", confirmationErr)
		},
	)
}
