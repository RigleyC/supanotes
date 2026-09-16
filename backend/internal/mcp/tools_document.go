package mcpapp

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/RigleyC/supanotes/internal/noteoperations"
	"github.com/RigleyC/supanotes/pkg/uid"
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
			args, err := decodeToolArgs[updateBlockToolArgs](request)
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
			baseRevision, err := toolBaseRevision(args.BaseRevision)
			if err != nil {
				return asError(err)
			}
			if destructive && strings.TrimSpace(args.OperationID) == "" {
				return asError(fmt.Errorf("operation_id is required for destructive mutations"))
			}
			operationID, err := toolOperationID(args.OperationID)
			if err != nil {
				return asError(err)
			}
			payload, err := objectPayload(args.Payload)
			if err != nil {
				return asError(err)
			}
			blockID := strings.TrimSpace(args.BlockID)
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
				if replay, ok, replayErr := replayConfirmation(confirmationLease); replayErr != nil {
					return asError(replayErr)
				} else if ok {
					return replay, nil
				}
			}
			clientID := strings.TrimSpace(args.ClientID)
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
				return asError(finishConfirmation(ctx, confirmationLease, nil, err))
			}
			confirmationErr := finishConfirmation(ctx, confirmationLease, result, nil)
			return asTextResultWithWarning(result, confirmationErr)
		},
	)
}

func addTaskOccurrenceTool(server *mcp.Server, security SecurityStore, name string, commands noteoperations.DocumentCommandService, reopen bool) {
	inputSchema := taskOccurrenceSchema
	if reopen {
		inputSchema = destructiveTaskOccurrenceSchema
	}
	addTool(server, security, &mcp.Tool{Name: name, Description: "Complete or reopen a task occurrence in the canonical document", InputSchema: inputSchema},
		func(ctx context.Context, request *mcp.CallToolRequest) (*mcp.CallToolResult, error) {
			if err := requireWriteScope(ctx); err != nil {
				return asError(err)
			}
			if commands == nil {
				return asError(fmt.Errorf("document command service is not configured"))
			}
			args, err := decodeToolArgs[taskOccurrenceToolArgs](request)
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
			blockID, err := requiredToolString(args.BlockID, "block_id")
			if err != nil {
				return asError(err)
			}
			baseRevision, err := toolBaseRevision(args.BaseRevision)
			if err != nil {
				return asError(err)
			}
			scheduledAt, err := requiredToolString(args.ScheduledAt, "scheduled_at")
			if err != nil {
				return asError(err)
			}
			if _, err := time.Parse(time.RFC3339, scheduledAt); err != nil {
				return asError(fmt.Errorf("scheduled_at must be RFC3339"))
			}
			if reopen && strings.TrimSpace(args.OperationID) == "" {
				return asError(fmt.Errorf("operation_id is required for reopening an occurrence"))
			}
			operationID, err := toolOperationID(args.OperationID)
			if err != nil {
				return asError(err)
			}
			var completedAt *string
			if !reopen {
				if args.CompletedAt == nil {
					value := time.Now().UTC().Format(time.RFC3339)
					completedAt = &value
				} else {
					value, valueErr := requiredToolString(*args.CompletedAt, "completed_at")
					if valueErr != nil {
						return asError(valueErr)
					}
					if _, valueErr = time.Parse(time.RFC3339, value); valueErr != nil {
						return asError(fmt.Errorf("completed_at must be RFC3339"))
					}
					completedAt = &value
				}
			} else if args.CompletedAt != nil {
				return asError(fmt.Errorf("completed_at is not allowed when reopening an occurrence"))
			}
			var confirmationLease ConfirmationLease
			if reopen {
				confirmationLease, err = requireConfirmation(ctx, security, request, name, "task:"+blockID+"/occurrence:"+scheduledAt)
				if err != nil {
					return asError(err)
				}
				if replay, ok, replayErr := replayConfirmation(confirmationLease); replayErr != nil {
					return asError(replayErr)
				} else if ok {
					return replay, nil
				}
			}
			operation, err := buildTaskOccurrenceOperation(blockID, scheduledAt, baseRevision, operationID, completedAt, reopen)
			if err != nil {
				return asError(err)
			}
			result, err := commands.SyncOperations(ctx, noteID, userID, noteoperations.SyncRequest{
				KnownRevision: baseRevision, ClientID: "mcp",
				Operations: []noteoperations.OperationRequest{operation},
			})
			if err != nil {
				return asError(finishConfirmation(ctx, confirmationLease, nil, err))
			}
			confirmationErr := finishConfirmation(ctx, confirmationLease, result, nil)
			return asTextResultWithWarning(result, confirmationErr)
		},
	)
}

// Task occurrences use one canonical document operation. Reopening is
// represented by the same operation with a null completedAt, which keeps the
// TaskNode ownership and operation idempotency at the document seam.
func buildTaskOccurrenceOperation(
	blockID, scheduledAt string,
	baseRevision int64,
	operationID string,
	completedAt *string,
	reopen bool,
) (noteoperations.OperationRequest, error) {
	if reopen {
		completedAt = nil
	}
	payload, err := json.Marshal(noteoperations.CompleteTaskOccurrencePayload{
		TaskID: blockID, ScheduledAt: scheduledAt, CompletedAt: completedAt,
	})
	if err != nil {
		return noteoperations.OperationRequest{}, err
	}
	return noteoperations.OperationRequest{
		OperationID: operationID, BaseRevision: baseRevision,
		Kind:    string(noteoperations.KindCompleteTaskOccurrence),
		BlockID: &blockID,
		Payload: payload,
	}, nil
}
