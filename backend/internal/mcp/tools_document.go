package mcpapp

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/RigleyC/supanotes/internal/noteoperations"
)

func addBlockMutationTool(
	server *mcp.Server,
	security SecurityStore,
	name string,
	kind noteoperations.Kind,
	documentCommands noteoperations.DocumentCommandService,
	destructive bool,
) {
	inputSchema := blockMutationSchema
	if destructive {
		inputSchema = destructiveBlockMutationSchema
	}
	addTool(server, security, &mcp.Tool{Name: name, Description: "Apply a REST/OT block operation", InputSchema: inputSchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			if err := requireWriteScope(ctx); err != nil {
				return asError(err)
			}
			if documentCommands == nil {
				return asError(fmt.Errorf("document command service is not configured"))
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
			var confirmationLease ConfirmationLease
			if destructive {
				resource := "note:" + noteID.String()
				if blockID != "" {
					resource = "block:" + blockID
				}
				confirmationLease, err = requireConfirmation(ctx, security, request, name, resource)
				if err != nil {
					return asError(err)
				}
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
				return asError(finishConfirmation(ctx, confirmationLease, err))
			}
			confirmationErr := finishConfirmation(ctx, confirmationLease, nil)
			return asTextResultWithWarning(result, confirmationErr)
		},
	)
}

func addTaskOccurrenceTool(server *mcp.Server, security SecurityStore, name string, commands noteoperations.DocumentCommandService, reopen bool) {
	addTool(server, security, &mcp.Tool{Name: name, Description: "Complete or reopen a task occurrence in the canonical document", InputSchema: taskOccurrenceSchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			if err := requireWriteScope(ctx); err != nil {
				return asError(err)
			}
			if commands == nil {
				return asError(fmt.Errorf("document command service is not configured"))
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
			return asTextResult(result)
		},
	)
}
